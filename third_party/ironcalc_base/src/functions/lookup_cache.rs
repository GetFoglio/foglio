//! Foglio fork: a per-pass hash index of lookup vectors for exact-match
//! lookups (VLOOKUP/HLOOKUP with FALSE, MATCH with 0, XLOOKUP in its default
//! exact mode).
//!
//! Without it every one of N lookups into a table of M rows reads and compares
//! all M cells: N·M work. With it the first lookup into a vector reads the
//! vector once (exactly as the plain path would, so formulas in it are
//! evaluated, and cycles detected, in the same way) and records, for each key,
//! the first position holding it; the following lookups are a hash probe.
//!
//! The index is only a shortcut, never a different answer:
//! * A spill is the only thing that changes a value already read during a
//!   pass, and the reads made on behalf of each formula are what the pass uses
//!   to detect that (`evaluation.rs`). Formulas answered from the index did
//!   not make those reads, so a spill into (or out of) a vector that has an
//!   index abandons the pass, which runs again without the index
//!   (`Restart::LookupCacheConflict`). Every other value of the vector is
//!   final once read: formulas run once per pass.
//! * It is not used while a cell inside the vector is being evaluated (on the
//!   evaluation stack): the plain path would read that cell and detect the
//!   cycle.
//! * It is only used for lookup values whose matches are exactly "same key":
//!   numbers of magnitude >= 1 (see `number_key`), and texts without
//!   wildcard characters (VLOOKUP/HLOOKUP/MATCH match text as wildcard
//!   patterns), non-empty for XLOOKUP (where "" also matches empty cells).
//!   Everything else takes the plain path.
//! * If building the index was interrupted (the pass is being abandoned or the
//!   recursion is unwinding), nothing is stored.

use std::collections::HashMap;

use crate::calc_result::CalcResult;
use crate::evaluation::KeyBuild;
use crate::expressions::types::CellReferenceIndex;
use crate::model::Model;
use crate::number_format::to_excel_precision;

/// How a function compares the lookup value with the cells.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub(crate) enum LookupMode {
    /// VLOOKUP, HLOOKUP: numbers with `compare_values` (15 significant
    /// digits), text as a case-insensitive pattern (`to_lowercase`).
    Vlookup,
    /// MATCH(…, 0): numbers with `values_are_equal` (exact), text as a
    /// case-insensitive pattern (`to_lowercase`).
    Match,
    /// XLOOKUP(…, 0, 1): numbers and text with `compare_values` (text compared
    /// with `to_uppercase`).
    Xlookup,
}

#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
struct VectorKey {
    sheet: u32,
    row1: i32,
    column1: i32,
    row2: i32,
    column2: i32,
    mode: LookupMode,
}

#[derive(Default)]
struct VectorIndex {
    numbers: HashMap<u64, u32, KeyBuild>,
    texts: HashMap<String, u32>,
}

/// See the module documentation.
#[derive(Default)]
pub(crate) struct LookupCache {
    enabled: bool,
    vectors: HashMap<VectorKey, VectorIndex>,
}

impl LookupCache {
    /// Starts a pass: forgets every index, and enables the cache for it or not.
    pub(crate) fn reset(&mut self, enabled: bool) {
        self.enabled = enabled;
        self.vectors.clear();
    }

    /// Whether any of these positions is in a vector an index was built from.
    pub(crate) fn covers_any<'k>(
        &self,
        mut positions: impl Iterator<Item = &'k (u32, i32, i32)>,
    ) -> bool {
        if self.vectors.is_empty() {
            return false;
        }
        positions.any(|(sheet, row, column)| {
            self.vectors.keys().any(|v| {
                v.sheet == *sheet
                    && v.row1 <= *row
                    && *row <= v.row2
                    && v.column1 <= *column
                    && *column <= v.column2
            })
        })
    }
}

/// The key of a number for `mode`, if numbers equal to it under that mode's
/// comparison are exactly the numbers with the same key.
///
/// * `compare_values` says two numbers are equal when their values rounded to
///   15 significant digits are less than `f64::EPSILON` apart. For a rounded
///   value of magnitude >= 1, two different 15-digit values are at least 1e-15
///   apart, so "equal" is "same rounded value".
/// * `values_are_equal` says equal when less than `f64::EPSILON` apart. For a
///   magnitude >= 1 neighbouring doubles are at least `f64::EPSILON` apart, so
///   "equal" is "same double".
///
/// Below 1 (zero included, which also matches empty cells) there is no key.
fn number_key(value: f64, mode: LookupMode) -> Option<u64> {
    let value = match mode {
        LookupMode::Vlookup | LookupMode::Xlookup => to_excel_precision(value, 15),
        LookupMode::Match => value,
    };
    if value.is_finite() && value.abs() >= 1.0 {
        Some(value.to_bits())
    } else {
        None
    }
}

/// The key a cell value is stored under (numbers below 1 are stored too:
/// they can never match a lookup value that has a key).
fn stored_number_key(value: f64, mode: LookupMode) -> u64 {
    match mode {
        LookupMode::Vlookup | LookupMode::Xlookup => to_excel_precision(value, 15).to_bits(),
        LookupMode::Match => value.to_bits(),
    }
}

fn text_key(text: &str, mode: LookupMode) -> String {
    match mode {
        LookupMode::Vlookup | LookupMode::Match => text.to_lowercase(),
        LookupMode::Xlookup => text.to_uppercase(),
    }
}

/// The key of the lookup value, if this lookup can use the index.
enum LookupKey {
    Number(u64),
    Text(String),
}

fn lookup_key(value: &CalcResult, mode: LookupMode) -> Option<LookupKey> {
    match value {
        CalcResult::Number(f) => number_key(*f, mode).map(LookupKey::Number),
        CalcResult::String(s) => match mode {
            LookupMode::Vlookup | LookupMode::Match => {
                if s.contains(['*', '?', '~']) {
                    None
                } else {
                    Some(LookupKey::Text(text_key(s, mode)))
                }
            }
            LookupMode::Xlookup => {
                if s.is_empty() {
                    None
                } else {
                    Some(LookupKey::Text(text_key(s, mode)))
                }
            }
        },
        _ => None,
    }
}

impl<'a> Model<'a> {
    /// Foglio fork: the 0-based position of the first cell of the vector
    /// `left..=right` (a single row or a single column) that matches
    /// `lookup_value` the way `mode` compares, using the per-pass index.
    ///
    /// `None` if the index cannot answer: the caller must take the plain path.
    /// `Some(None)` means "no match".
    pub(crate) fn cached_exact_lookup(
        &mut self,
        lookup_value: &CalcResult,
        left: CellReferenceIndex,
        right: CellReferenceIndex,
        mode: LookupMode,
    ) -> Option<Option<usize>> {
        if !self.evaluation.lookup_cache.enabled || !self.evaluation.in_pass {
            return None;
        }
        if left.sheet != right.sheet || (left.row != right.row && left.column != right.column) {
            return None;
        }
        let key = lookup_key(lookup_value, mode)?;
        if left.row > right.row || left.column > right.column {
            return None;
        }
        let vector = VectorKey {
            sheet: left.sheet,
            row1: left.row,
            column1: left.column,
            row2: right.row,
            column2: right.column,
            mode,
        };
        if vector.row1 < 1 || vector.column1 < 1 {
            return None;
        }
        // A cell of the vector being evaluated right now: the plain path reads
        // it and reports the cycle.
        if self.evaluation.stack.iter().any(|c| {
            c.sheet == vector.sheet
                && vector.row1 <= c.row
                && c.row <= vector.row2
                && vector.column1 <= c.column
                && c.column <= vector.column2
        }) {
            return None;
        }
        if !self.evaluation.lookup_cache.vectors.contains_key(&vector) {
            let index = self.build_vector_index(vector)?;
            self.evaluation.lookup_cache.vectors.insert(vector, index);
        }
        let index = self.evaluation.lookup_cache.vectors.get(&vector)?;
        let found = match key {
            LookupKey::Number(bits) => index.numbers.get(&bits),
            LookupKey::Text(text) => index.texts.get(&text),
        };
        Some(found.map(|i| *i as usize))
    }

    fn build_vector_index(&mut self, vector: VectorKey) -> Option<VectorIndex> {
        let vertical = vector.column1 == vector.column2 && vector.row1 != vector.row2;
        // Every cell is read, in order, as the plain path reads them: reading
        // a formula may spill an array further down the vector.
        let last = if vertical {
            vector.row2 - vector.row1 + 1
        } else {
            vector.column2 - vector.column1 + 1
        };
        let mut index = VectorIndex::default();
        for i in 0..last.max(0) {
            let position = if vertical {
                CellReferenceIndex {
                    sheet: vector.sheet,
                    row: vector.row1 + i,
                    column: vector.column1,
                }
            } else {
                CellReferenceIndex {
                    sheet: vector.sheet,
                    row: vector.row1,
                    column: vector.column1 + i,
                }
            };
            match self.evaluate_cell(position) {
                CalcResult::Number(f) => {
                    index
                        .numbers
                        .entry(stored_number_key(f, vector.mode))
                        .or_insert(i as u32);
                }
                CalcResult::String(s) => {
                    index
                        .texts
                        .entry(text_key(&s, vector.mode))
                        .or_insert(i as u32);
                }
                _ => {}
            }
        }
        if self.evaluation.restart.is_some() || self.evaluation.unwinding {
            return None;
        }
        Some(index)
    }
}
