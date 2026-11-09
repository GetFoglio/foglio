//! Foglio fork: how the lookup functions read the vector they search
//! (VLOOKUP/HLOOKUP, MATCH, LOOKUP, XLOOKUP, XMATCH), and the per-pass cache
//! of those vectors with a hash index for exact matches.
//!
//! # Reading a vector: only the used part
//!
//! A vector is read in order, cell by cell, exactly as the plain path read it
//! (so formulas in it are evaluated, and cycles detected, in the same way),
//! but only up to the last row (for a column) or column (for a row) of the
//! sheet that holds a cell. Past it every cell is empty. Those positions are
//! not visited: they are put on record as read empty in one go (a spill into
//! them later in the pass contradicts the read, as it would have one by one),
//! and the searches treat them as empty cells (`VectorData::get`). The bound
//! is looked at again after the walk, in case a formula evaluated during it
//! spilled further down: the walk goes on until it holds. So `VLOOKUP(k,
//! A:B, 2, FALSE)` on a sheet with 4 000 rows reads 4 000 cells, not
//! 1 048 576, with the same result — including when an empty cell matches
//! (`VLOOKUP(0, A:B, 2, FALSE)` finds the first empty cell, below the data).
//!
//! # The per-pass cache
//!
//! Without it every one of N lookups into a table of M rows reads (and, before
//! this module, copied) all M cells: N·M work. With it the first lookup into a
//! vector in a pass reads it as above and keeps the values; the following
//! lookups use them: a hash probe for exact matches, a binary search over the
//! kept values for approximate ones, a scan of them otherwise — no cell read,
//! nothing allocated.
//!
//! The cache is only a shortcut, never a different answer:
//! * A spill is the only thing that changes a value already read during a
//!   pass, and the reads made on behalf of each formula are what the pass uses
//!   to detect that (`evaluation.rs`). Formulas answered from the cache did
//!   not make those reads, so a spill into (or out of) a cached vector
//!   abandons the pass, which runs again without the cache
//!   (`Restart::LookupCacheConflict`). Every other value of the vector is
//!   final once read: formulas run once per pass.
//! * It is not used while a cell inside the vector is being evaluated (on the
//!   evaluation stack): the plain path would read that cell and detect the
//!   cycle.
//! * The hash index is only used for lookup values whose matches are exactly
//!   "same key": numbers of magnitude >= 1 (see `number_key`), and texts
//!   without wildcard characters (VLOOKUP/HLOOKUP/MATCH match text as
//!   wildcard patterns), non-empty for XLOOKUP (where "" also matches empty
//!   cells). None of these matches an empty cell. Everything else scans.
//! * If reading the vector was interrupted (the pass is being abandoned or
//!   the recursion is unwinding), nothing is stored.
//! * Outside a pass the cache is used only while the conditional formatting
//!   is evaluated (which is what evaluates the formulas of a workbook just
//!   loaded): nothing edits the workbook meanwhile, and a spill into a cached
//!   vector drops the cache for the rest of it. Without a driver there is no
//!   restart: the plain path would have read the old values too.

use std::collections::HashMap;
use std::sync::{Arc, OnceLock};

use crate::calc_result::CalcResult;
use crate::evaluation::KeyBuild;
use crate::expressions::types::CellReferenceIndex;
use crate::model::Model;
use crate::number_format::to_excel_precision;

use super::util::{compare_values, from_wildcard_to_regex, result_matches_regex, values_are_equal};

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

impl LookupMode {
    fn slot(self) -> usize {
        match self {
            LookupMode::Vlookup => 0,
            LookupMode::Match => 1,
            LookupMode::Xlookup => 2,
        }
    }
}

/// A vector of the cache: its rectangle (one row or one column), and whether
/// it was clipped to the used part of the sheet.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
struct VectorKey {
    sheet: u32,
    row1: i32,
    column1: i32,
    row2: i32,
    column2: i32,
    clipped: bool,
}

#[derive(Default)]
struct VectorIndex {
    numbers: HashMap<u64, u32, KeyBuild>,
    texts: HashMap<String, u32>,
}

static EMPTY: CalcResult = CalcResult::EmptyCell;

#[cfg(test)]
thread_local! {
    /// Tests: read every lookup vector whole, cell by cell, on every call, with
    /// no cache and no index — what upstream did — to compare against.
    pub(crate) static NAIVE_LOOKUPS: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
}

fn naive_lookups() -> bool {
    #[cfg(test)]
    {
        NAIVE_LOOKUPS.with(|naive| naive.get())
    }
    #[cfg(not(test))]
    {
        false
    }
}

/// The values of a lookup vector, as read by `Model::lookup_vector`.
pub(crate) struct VectorData {
    /// The cells read, in order. When the vector was clipped, the positions
    /// from `values.len()` to `len` are empty cells that were not visited.
    pub(crate) values: Vec<CalcResult>,
    /// The length of the whole vector.
    len: usize,
    /// Kept in the cache: worth a hash index.
    cached: bool,
    /// Hash index per `LookupMode`, built the first time it is needed.
    indexes: [OnceLock<VectorIndex>; 3],
}

/// Shared: a cached vector is handed out without copying it.
pub(crate) type LookupVector = Arc<VectorData>;

impl VectorData {
    fn new(values: Vec<CalcResult>, len: usize) -> VectorData {
        VectorData {
            values,
            len,
            cached: false,
            indexes: Default::default(),
        }
    }

    /// Tests: `values` read, `len` in all, cached (hash index) or not.
    #[cfg(test)]
    pub(crate) fn for_test(values: Vec<CalcResult>, len: usize, cached: bool) -> VectorData {
        let mut data = VectorData::new(values, len);
        data.cached = cached;
        data
    }

    /// A vector made of values already at hand (an array argument).
    pub(crate) fn from_values(values: Vec<CalcResult>) -> LookupVector {
        let len = values.len();
        Arc::new(VectorData::new(values, len))
    }

    /// The length of the whole vector, unvisited empty cells included.
    pub(crate) fn len(&self) -> usize {
        self.len
    }

    /// The value at `index` (< `len()`).
    pub(crate) fn get(&self, index: usize) -> &CalcResult {
        self.values.get(index).unwrap_or(&EMPTY)
    }

    /// Whether the vector ends with empty cells that were not visited.
    fn has_unvisited(&self) -> bool {
        self.len > self.values.len()
    }

    fn index(&self, mode: LookupMode) -> &VectorIndex {
        self.indexes[mode.slot()].get_or_init(|| {
            let mut index = VectorIndex::default();
            for (i, value) in self.values.iter().enumerate() {
                match value {
                    CalcResult::Number(f) => {
                        index
                            .numbers
                            .entry(stored_number_key(*f, mode))
                            .or_insert(i as u32);
                    }
                    CalcResult::String(s) => {
                        index.texts.entry(text_key(s, mode)).or_insert(i as u32);
                    }
                    _ => {}
                }
            }
            index
        })
    }

    /// The first position matching `lookup_value` the way `mode` compares,
    /// from the hash index. `None` if the index cannot answer (the vector is
    /// not cached or the value has no key); `Some(None)`: no match.
    pub(crate) fn indexed_position(
        &self,
        lookup_value: &CalcResult,
        mode: LookupMode,
    ) -> Option<Option<usize>> {
        if !self.cached || self.values.len() > u32::MAX as usize {
            return None;
        }
        let key = lookup_key(lookup_value, mode)?;
        let index = self.index(mode);
        let found = match key {
            LookupKey::Number(bits) => index.numbers.get(&bits),
            LookupKey::Text(text) => index.texts.get(&text),
        };
        // No value with a key matches an empty cell, so the unvisited part
        // cannot hold the match.
        Some(found.map(|i| *i as usize))
    }

    /// The first position that matches `lookup_value` exactly, as VLOOKUP and
    /// HLOOKUP with FALSE (`LookupMode::Vlookup`) or MATCH with 0
    /// (`LookupMode::Match`) compare: text as a case-insensitive wildcard
    /// pattern, anything else with `compare_values` (VLOOKUP) or
    /// `values_are_equal` (MATCH).
    pub(crate) fn exact_position(
        &self,
        lookup_value: &CalcResult,
        mode: LookupMode,
    ) -> Option<usize> {
        if let Some(found) = self.indexed_position(lookup_value, mode) {
            return found;
        }
        let matches: Box<dyn Fn(&CalcResult) -> bool + '_> =
            if let CalcResult::String(s) = lookup_value {
                if let Ok(reg) = from_wildcard_to_regex(&s.to_lowercase(), true) {
                    Box::new(move |x| result_matches_regex(x, &reg))
                } else {
                    Box::new(move |_| false)
                }
            } else if mode == LookupMode::Match {
                Box::new(move |x| values_are_equal(x, lookup_value))
            } else {
                Box::new(move |x| compare_values(x, lookup_value) == 0)
            };
        if let Some(found) = self.values.iter().position(&matches) {
            return Some(found);
        }
        // The first unvisited cell, if an empty cell matches.
        if self.has_unvisited() && matches(&EMPTY) {
            return Some(self.values.len());
        }
        None
    }

    /// Upstream's `binary_search_on_array` over the whole vector: the index of
    /// a matching element or of the largest element smaller than `target`
    /// (assuming ascending order), `-2` if `target` is smaller than every
    /// element. Same probes, same answer; unvisited cells are empty.
    pub(crate) fn binary_search(&self, target: &CalcResult) -> i32 {
        let mut l = 0;
        let mut r = self.len;
        while l < r {
            let m = (l + r) / 2;
            match compare_values(self.get(m), target) {
                -1 => {
                    l = m + 1;
                }
                1 => {
                    r = m;
                }
                _ => {
                    return m as i32;
                }
            }
        }
        if l == 0 {
            return -2;
        }
        (l - 1) as i32
    }
}

/// See the module documentation.
#[derive(Default)]
pub(crate) struct LookupCache {
    enabled: bool,
    vectors: HashMap<VectorKey, LookupVector>,
    /// Spills written outside a pass so far. A vector during whose reading
    /// one happened may hold a value from before it: it is not kept.
    spills_outside_pass: u64,
}

impl LookupCache {
    /// Starts a pass: forgets every vector, and enables the cache for it or
    /// not.
    pub(crate) fn reset(&mut self, enabled: bool) {
        self.enabled = enabled;
        self.vectors.clear();
    }

    /// Whether any of these positions is in a cached vector.
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
    /// Foglio fork: the values of the vector `left..=right` (a single row or a
    /// single column; `vertical` says which way to walk a single cell).
    ///
    /// Read in order as the plain path reads it, up to the last row/column of
    /// the sheet that has a cell when `clip` is set (see the module
    /// documentation), or taken from the per-pass cache.
    pub(crate) fn lookup_vector(
        &mut self,
        left: CellReferenceIndex,
        right: CellReferenceIndex,
        vertical: bool,
        clip: bool,
    ) -> LookupVector {
        if naive_lookups() {
            return Arc::new(self.read_vector(left, right, vertical, false));
        }
        let key = VectorKey {
            sheet: left.sheet,
            row1: left.row,
            column1: left.column,
            row2: right.row,
            column2: right.column,
            clipped: clip,
        };
        let cacheable = self.evaluation.lookup_cache.enabled
            && left.sheet == right.sheet
            && key.row1 >= 1
            && key.column1 >= 1
            && key.row1 <= key.row2
            && key.column1 <= key.column2
            && (key.row1 == key.row2 || key.column1 == key.column2)
            // A cell of the vector being evaluated right now: the plain path
            // reads it and reports the cycle.
            && !self.evaluation.stack.iter().any(|c| {
                c.sheet == key.sheet
                    && key.row1 <= c.row
                    && c.row <= key.row2
                    && key.column1 <= c.column
                    && c.column <= key.column2
            });
        if cacheable {
            if let Some(vector) = self.evaluation.lookup_cache.vectors.get(&key) {
                return Arc::clone(vector);
            }
        }
        let spills_before = self.evaluation.lookup_cache.spills_outside_pass;
        let mut data = self.read_vector(left, right, vertical, clip);
        if cacheable
            && self.evaluation.restart.is_none()
            && !self.evaluation.unwinding
            && self.evaluation.lookup_cache.spills_outside_pass == spills_before
        {
            data.cached = true;
            let vector = Arc::new(data);
            // Reading it may have dropped the cache (a spill outside a pass).
            if self.evaluation.lookup_cache.enabled {
                self.evaluation
                    .lookup_cache
                    .vectors
                    .insert(key, Arc::clone(&vector));
            }
            return vector;
        }
        Arc::new(data)
    }

    /// The last row (`vertical`) of the sheet, or the last column of `row`,
    /// that holds a cell; 0 if none.
    fn used_end(&self, sheet: u32, vertical: bool, row: i32) -> i32 {
        match self.workbook.worksheet(sheet) {
            Ok(worksheet) => {
                if vertical {
                    worksheet.sheet_data.last_row_with_cells()
                } else {
                    worksheet.sheet_data.last_column_in_rows(row, row)
                }
            }
            Err(_) => 0,
        }
    }

    fn read_vector(
        &mut self,
        left: CellReferenceIndex,
        right: CellReferenceIndex,
        vertical: bool,
        clip: bool,
    ) -> VectorData {
        let sheet = left.sheet;
        let (first, last) = if vertical {
            (left.row, right.row)
        } else {
            (left.column, right.column)
        };
        let len = (last as i64 - first as i64 + 1).max(0) as usize;
        let position = |i: i32| {
            if vertical {
                CellReferenceIndex {
                    sheet,
                    row: i,
                    column: left.column,
                }
            } else {
                CellReferenceIndex {
                    sheet,
                    row: left.row,
                    column: i,
                }
            }
        };
        let mut next = first;
        let mut bound = if clip {
            last.min(self.used_end(sheet, vertical, left.row))
        } else {
            last
        };
        let mut values = Vec::with_capacity((bound as i64 - first as i64 + 1).max(0) as usize);
        loop {
            while next <= bound {
                values.push(self.evaluate_cell(position(next)));
                next += 1;
            }
            if next > last {
                break;
            }
            // A formula evaluated during the walk may have spilled further.
            let end = last.min(self.used_end(sheet, vertical, left.row));
            if end <= bound {
                break;
            }
            bound = end;
        }
        if next <= last && self.evaluation.restart.is_none() && !self.evaluation.unwinding {
            // The rest is empty: read, as far as spills are concerned.
            let (row1, column1, row2, column2) = if vertical {
                (next, left.column, last, left.column)
            } else {
                (left.row, next, left.row, last)
            };
            self.record_seen_empty_range(sheet, row1, column1, row2, column2);
        }
        VectorData::new(values, len)
    }

    /// Foglio fork: a spill outside a pass is about to write or clear these
    /// positions. If the cache holds any of them, it is dropped for the rest
    /// of what is being evaluated (see the module documentation).
    pub(crate) fn lookup_cache_before_spill_outside_pass<'k>(
        &mut self,
        positions: impl Iterator<Item = &'k (u32, i32, i32)>,
    ) {
        let cache = &mut self.evaluation.lookup_cache;
        cache.spills_outside_pass += 1;
        if cache.covers_any(positions) {
            cache.reset(false);
        }
    }

    /// Foglio fork: runs `f` with the lookup cache on, outside a pass (the
    /// conditional formatting). Nothing else may run meanwhile.
    pub(crate) fn with_lookup_cache_outside_pass<T>(
        &mut self,
        f: impl FnOnce(&mut Self) -> T,
    ) -> T {
        if self.evaluation.in_pass {
            return f(self);
        }
        self.evaluation.lookup_cache.reset(true);
        let result = f(self);
        self.evaluation.lookup_cache.reset(false);
        result
    }
}
