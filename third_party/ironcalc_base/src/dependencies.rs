//! Foglio fork: a reverse-dependency index of the formulas of a workbook, used
//! for incremental recalculation (see `evaluation.rs`, `Model::evaluate_pending`).
//!
//! For every formula cell the index knows, statically, which positions its
//! formula may read: the single cells and the rectangles it references, with
//! relative references resolved against the cell. The index answers the reverse
//! question, "which formulas may read this position?".
//!
//! The analysis must over-approximate: a formula that can read a position the
//! analysis does not see would not be recalculated when that position changes.
//! Everything that is not a plain reference is therefore treated as "may read
//! anything": the formula is *volatile* and is recalculated on every evaluation,
//! as are the formulas that depend on it. That covers the volatile functions
//! (`NOW`, `RAND`, …), the functions that build references at run time
//! (`INDIRECT`, `OFFSET`), defined names, table references, the range operator
//! between computed references (`A1:INDEX(…)`) and the spill operator (`A1#`).
//!
//! Storage, per `(sheet, column)`:
//! * `points`: the single-cell references into that column, `(row, dependent)`,
//!   sorted by row (plus a small unsorted tail for recent additions);
//! * `rects`: the rectangles at most `NARROW_COLUMNS` wide that cover that
//!   column, `(row1, row2, dependent)`.
//!
//! Wider rectangles (whole rows, `A1:Z100`…) live in one list per workbook.
//! A whole-column reference such as `A:A` is a single entry, not a million.

use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use crate::constants::{LAST_COLUMN, LAST_ROW};
use crate::evaluation::{CellKey, KeyBuild};
use crate::expressions::parser::Node;
use crate::functions::Function;

/// Rectangles at most this many columns wide are stored in the bucket of every
/// column they cover; wider ones are kept in a single list that every query scans.
const NARROW_COLUMNS: i32 = 16;

/// Above this many unsorted points in a column, the column is sorted again.
const TAIL_LIMIT: usize = 64;

/// A reference of a formula, as written: relative parts are offsets from the
/// formula cell.
#[derive(Clone, Copy, Debug)]
enum RefTemplate {
    Cell {
        sheet: u32,
        absolute_row: bool,
        absolute_column: bool,
        row: i32,
        column: i32,
    },
    Range {
        sheet: u32,
        absolute_row1: bool,
        absolute_column1: bool,
        row1: i32,
        column1: i32,
        absolute_row2: bool,
        absolute_column2: bool,
        row2: i32,
        column2: i32,
    },
}

/// What a parsed formula may read, independent of the cell it is in.
#[derive(Debug, Default)]
pub(crate) struct FormulaTemplate {
    refs: Vec<RefTemplate>,
    /// The formula may read positions the analysis cannot see, or its value
    /// may change on its own: it is recalculated on every evaluation.
    pub(crate) volatile: bool,
}

/// Functions whose value can change although nothing they reference did, or
/// which read positions computed at run time.
fn is_volatile_function(kind: &Function) -> bool {
    matches!(
        kind,
        Function::Now
            | Function::Today
            | Function::Rand
            | Function::Randbetween
            | Function::Randarray
            | Function::Indirect
            | Function::Offset
            | Function::Cell
            | Function::Info
            | Function::Sheet
            | Function::Sheets
    )
}

impl FormulaTemplate {
    pub(crate) fn of(node: &Node) -> FormulaTemplate {
        let mut template = FormulaTemplate::default();
        template.collect(node);
        template
    }

    fn collect(&mut self, node: &Node) {
        use Node::*;
        match node {
            BooleanKind(_)
            | NumberKind(_)
            | StringKind(_)
            | ErrorKind(_)
            | EmptyArgKind
            | ArrayKind(_)
            | WrongReferenceKind { .. }
            | WrongRangeKind { .. }
            | ParseErrorKind { .. }
            // A variable holds what a node elsewhere in the same formula
            // evaluated to; that node is collected where it is.
            | NamedVariableKind { .. } => {}
            ReferenceKind {
                sheet_index,
                absolute_row,
                absolute_column,
                row,
                column,
                ..
            } => self.refs.push(RefTemplate::Cell {
                sheet: *sheet_index,
                absolute_row: *absolute_row,
                absolute_column: *absolute_column,
                row: *row,
                column: *column,
            }),
            RangeKind {
                sheet_index,
                absolute_row1,
                absolute_column1,
                row1,
                column1,
                absolute_row2,
                absolute_column2,
                row2,
                column2,
                ..
            } => self.refs.push(RefTemplate::Range {
                sheet: *sheet_index,
                absolute_row1: *absolute_row1,
                absolute_column1: *absolute_column1,
                row1: *row1,
                column1: *column1,
                absolute_row2: *absolute_row2,
                absolute_column2: *absolute_column2,
                row2: *row2,
                column2: *column2,
            }),
            // References computed at run time, or defined elsewhere.
            OpRangeKind { .. }
            | DefinedNameKind(_)
            | TableNameKind(_)
            | SpillRangeOperator { .. } => self.volatile = true,
            OpConcatenateKind { left, right }
            | OpSumKind { left, right, .. }
            | OpProductKind { left, right, .. }
            | OpPowerKind { left, right }
            | CompareKind { left, right, .. } => {
                self.collect(left);
                self.collect(right);
            }
            FunctionKind { kind, args } => {
                if is_volatile_function(kind) {
                    self.volatile = true;
                }
                for arg in args {
                    self.collect(arg);
                }
            }
            LambdaDefKind { body, .. } => self.collect(body),
            LambdaCallKind { lambda, args } => {
                self.collect(lambda);
                for arg in args {
                    self.collect(arg);
                }
            }
            NamedFunctionKind { id, args, .. } => {
                // Not bound by LET: a LAMBDA stored in a defined name.
                if id.is_none() {
                    self.volatile = true;
                }
                for arg in args {
                    self.collect(arg);
                }
            }
            ImplicitIntersection { child, .. } => self.collect(child),
            UnaryKind { right, .. } => self.collect(right),
        }
    }

    /// Calls `found` for every reference, resolved for a formula in
    /// `(row, column)`.
    fn resolve(&self, row: i32, column: i32, mut found: impl FnMut(Resolved)) {
        let mut cell = |sheet, r, c| found(Resolved::Cell(sheet, r, c));
        let mut pending_rects: Vec<Resolved> = Vec::new();
        let mut rect = |sheet, r1, c1, r2, c2| pending_rects.push(Resolved::Rect(sheet, r1, c1, r2, c2));
        for reference in &self.refs {
            match *reference {
                RefTemplate::Cell {
                    sheet,
                    absolute_row,
                    absolute_column,
                    row: r,
                    column: c,
                } => {
                    let r = if absolute_row { r } else { r + row };
                    let c = if absolute_column { c } else { c + column };
                    cell(sheet, r, c);
                }
                RefTemplate::Range {
                    sheet,
                    absolute_row1,
                    absolute_column1,
                    row1,
                    column1,
                    absolute_row2,
                    absolute_column2,
                    row2,
                    column2,
                } => {
                    let r1 = if absolute_row1 { row1 } else { row1 + row };
                    let r2 = if absolute_row2 { row2 } else { row2 + row };
                    let c1 = if absolute_column1 {
                        column1
                    } else {
                        column1 + column
                    };
                    let c2 = if absolute_column2 {
                        column2
                    } else {
                        column2 + column
                    };
                    let (r1, r2) = (r1.min(r2), r1.max(r2));
                    let (c1, c2) = (c1.min(c2), c1.max(c2));
                    if r1 == r2 && c1 == c2 {
                        cell(sheet, r1, c1);
                    } else {
                        rect(sheet, r1, c1, r2, c2);
                    }
                }
            }
        }
        for r in pending_rects {
            found(r);
        }
    }
}

/// A reference resolved for a cell: `(sheet, row, column)` or
/// `(sheet, row1, column1, row2, column2)`.
#[derive(Clone, Copy, Debug)]
enum Resolved {
    Cell(u32, i32, i32),
    Rect(u32, i32, i32, i32, i32),
}

#[derive(Default, Debug)]
struct Column {
    /// `(row, dependent)`, sorted by row.
    points: Vec<(i32, CellKey)>,
    /// Recently added points, unsorted.
    tail: Vec<(i32, CellKey)>,
    /// `(row1, row2, dependent)` of narrow rectangles covering this column.
    rects: Vec<(i32, i32, CellKey)>,
}

#[derive(Clone, Copy, Debug)]
struct WideRect {
    sheet: u32,
    row1: i32,
    column1: i32,
    row2: i32,
    column2: i32,
    dependent: CellKey,
}

/// The reverse-dependency index. See the module documentation.
#[derive(Default)]
pub(crate) struct DependencyIndex {
    /// Every formula cell the index knows, with the template it was indexed
    /// with (needed to remove it again), as an index into `templates`.
    forward: HashMap<CellKey, u32, KeyBuild>,
    templates: Vec<Arc<FormulaTemplate>>,
    template_ids: HashMap<usize, u32>,
    columns: HashMap<(u32, i32), Column, KeyBuild>,
    wide: Vec<WideRect>,
    /// Formula cells recalculated on every evaluation.
    pub(crate) volatile: HashSet<CellKey, KeyBuild>,
}

fn clamp_columns(c1: i32, c2: i32) -> (i32, i32) {
    (c1.max(1), c2.min(LAST_COLUMN))
}

impl DependencyIndex {
    /// Number of formula cells indexed.
    pub(crate) fn formula_count(&self) -> usize {
        self.forward.len()
    }

    pub(crate) fn contains_formula(&self, key: &CellKey) -> bool {
        self.forward.contains_key(key)
    }

    /// Adds a formula cell. `bulk` skips keeping the points sorted: call
    /// `finish_bulk` afterwards.
    pub(crate) fn add(&mut self, key: CellKey, template: Arc<FormulaTemplate>, bulk: bool) {
        if self.forward.contains_key(&key) {
            self.remove(key);
        }
        if template.volatile {
            self.volatile.insert(key);
        }
        let address = Arc::as_ptr(&template) as usize;
        let template_id = match self.template_ids.get(&address) {
            Some(id) => *id,
            None => {
                let id = self.templates.len() as u32;
                self.templates.push(template.clone());
                self.template_ids.insert(address, id);
                id
            }
        };
        let (_, row, column) = key;
        let columns = &mut self.columns;
        let wide = &mut self.wide;
        template.resolve(row, column, |resolved| match resolved {
            Resolved::Cell(sheet, r, c) => {
                if !(1..=LAST_ROW).contains(&r) || !(1..=LAST_COLUMN).contains(&c) {
                    return;
                }
                let bucket = columns.entry((sheet, c)).or_default();
                if bulk {
                    bucket.points.push((r, key));
                } else {
                    bucket.tail.push((r, key));
                    if bucket.tail.len() > TAIL_LIMIT {
                        let tail = std::mem::take(&mut bucket.tail);
                        bucket.points.extend(tail);
                        bucket.points.sort_unstable_by_key(|(r, _)| *r);
                    }
                }
            }
            Resolved::Rect(sheet, r1, c1, r2, c2) => {
                let (c1, c2) = clamp_columns(c1, c2);
                if c1 > c2 || r2 < 1 || r1 > LAST_ROW {
                    return;
                }
                if c2 - c1 < NARROW_COLUMNS {
                    for c in c1..=c2 {
                        columns.entry((sheet, c)).or_default().rects.push((r1, r2, key));
                    }
                } else {
                    wide.push(WideRect {
                        sheet,
                        row1: r1,
                        column1: c1,
                        row2: r2,
                        column2: c2,
                        dependent: key,
                    });
                }
            }
        });
        self.forward.insert(key, template_id);
    }

    /// An empty index with room for `formulas` formula cells.
    pub(crate) fn with_capacity(formulas: usize) -> Self {
        DependencyIndex {
            forward: HashMap::with_capacity_and_hasher(formulas, KeyBuild::default()),
            ..Default::default()
        }
    }

    /// Sorts what `add(.., bulk = true)` left unsorted.
    pub(crate) fn finish_bulk(&mut self) {
        for bucket in self.columns.values_mut() {
            bucket.points.sort_unstable_by_key(|(r, _)| *r);
            bucket.points.shrink_to_fit();
            bucket.rects.shrink_to_fit();
        }
        self.wide.shrink_to_fit();
    }

    /// Removes a formula cell, if it is indexed.
    pub(crate) fn remove(&mut self, key: CellKey) {
        let Some(template_id) = self.forward.remove(&key) else {
            return;
        };
        let template = self.templates[template_id as usize].clone();
        self.volatile.remove(&key);
        let (_, row, column) = key;
        let columns = &mut self.columns;
        let mut wide_touched = false;
        template.resolve(row, column, |resolved| match resolved {
            Resolved::Cell(sheet, r, c) => {
                if let Some(bucket) = columns.get_mut(&(sheet, c)) {
                    // All entries with this row are adjacent in `points`.
                    let start = bucket.points.partition_point(|(pr, _)| *pr < r);
                    let mut end = start;
                    while end < bucket.points.len() && bucket.points[end].0 == r {
                        end += 1;
                    }
                    if let Some(offset) = bucket.points[start..end]
                        .iter()
                        .position(|(_, d)| *d == key)
                    {
                        bucket.points.remove(start + offset);
                    } else if let Some(i) = bucket.tail.iter().position(|e| *e == (r, key)) {
                        bucket.tail.swap_remove(i);
                    }
                }
            }
            Resolved::Rect(sheet, r1, c1, r2, c2) => {
                let (c1, c2) = clamp_columns(c1, c2);
                if c1 > c2 {
                    return;
                }
                if c2 - c1 < NARROW_COLUMNS {
                    for c in c1..=c2 {
                        if let Some(bucket) = columns.get_mut(&(sheet, c)) {
                            if let Some(i) =
                                bucket.rects.iter().position(|e| *e == (r1, r2, key))
                            {
                                bucket.rects.swap_remove(i);
                            }
                        }
                    }
                } else {
                    wide_touched = true;
                }
            }
        });
        if wide_touched {
            self.wide.retain(|w| w.dependent != key);
        }
    }

    /// Calls `found` with every formula cell that may read `(sheet, row, column)`.
    /// Returns the number of index entries examined (a measure of the work).
    pub(crate) fn dependents_of(
        &self,
        (sheet, row, column): CellKey,
        mut found: impl FnMut(CellKey),
    ) -> usize {
        let mut work = self.wide.len();
        if let Some(bucket) = self.columns.get(&(sheet, column)) {
            let start = bucket.points.partition_point(|(r, _)| *r < row);
            for (r, dependent) in &bucket.points[start..] {
                if *r != row {
                    break;
                }
                work += 1;
                found(*dependent);
            }
            work += bucket.tail.len() + bucket.rects.len() + 1;
            for (r, dependent) in &bucket.tail {
                if *r == row {
                    found(*dependent);
                }
            }
            for (r1, r2, dependent) in &bucket.rects {
                if *r1 <= row && row <= *r2 {
                    found(*dependent);
                }
            }
        }
        for w in &self.wide {
            if w.sheet == sheet
                && w.row1 <= row
                && row <= w.row2
                && w.column1 <= column
                && column <= w.column2
            {
                found(w.dependent);
            }
        }
        work
    }
}
