//! Foglio fork: incremental recalculation.
//!
//! `UserModel` reports every edit as "the content at these positions changed"
//! (`Recalc::note_changed`) or as "something else changed" (`Recalc::mark_full`).
//! `Model::evaluate_pending` then runs only the formulas that may be affected:
//!
//! 1. The dependency index (`dependencies.rs`) is brought up to date for the
//!    changed positions, or built if there is none.
//! 2. The dirty set is everything reachable from the changed positions through
//!    the index, plus the volatile formulas and what depends on them, plus the
//!    changed positions that hold formulas.
//! 3. A pass runs the dirty formulas only. A formula that is not dirty is
//!    read as the value it holds (`evaluate_formula_cell`).
//!
//! Whenever the incremental pass cannot be shown to give the same result as a
//! full evaluation it is not attempted, and a full evaluation runs instead:
//! * the edit touches a dynamic or CSE array (anchor or spill area), or a
//!   dynamic array is currently blocked (`#SPILL!`), or a dirty formula is an
//!   array anchor: spills move and the restart machinery of `evaluation.rs`
//!   assumes a full pass;
//! * the dirty set is more than half of the formulas;
//! * the pass asked for a restart;
//! * the workbook has circular references (the last full evaluation found
//!   one, or the incremental pass does): on which cells IronCalc reports a
//!   cycle, and so some values next to it, depends on where the recursion
//!   entered the cycle. Without cycles every formula's value is a function of
//!   the values it reads, whatever the order, and the incremental pass runs
//!   the dirty formulas in the order a full pass would.
//!
//! With `IRONCALC_CHECK_INCREMENTAL=1` (or `Model::set_check_incremental`)
//! every incremental evaluation is followed by a full one and the two results
//! are compared cell by cell; a difference panics.

use std::collections::HashSet;
use std::sync::Arc;

use crate::calc_result::CalcResult;
use crate::dependencies::{DependencyIndex, FormulaTemplate};
use crate::expressions::token::Error;
use crate::expressions::types::CellReferenceIndex;
use crate::model::Model;
use crate::types::{ArrayKind, Cell};

use super::{CellKey, FormulaCell, KeyBuild, Restart};

/// Work budget for the dirty-set search, in index entries examined, as a
/// multiple of the number of formulas (plus a constant). Beyond it a full
/// evaluation is cheaper.
const WORK_PER_FORMULA: usize = 8;
const WORK_CONSTANT: usize = 1_000_000;

impl<'a> Model<'a> {
    /// Foglio fork: turns on/off the verification of every incremental
    /// evaluation against a full one (slow; for tests and debugging).
    pub fn set_check_incremental(&mut self, check: bool) {
        self.evaluation.recalc.check = check;
    }

    /// Foglio fork: `Some(n)` if the last evaluation was incremental and ran
    /// `n` formulas, `None` if it was a full evaluation.
    pub fn last_evaluation_incremental(&self) -> Option<usize> {
        self.evaluation.recalc.last_incremental
    }

    /// Foglio fork: why the last evaluation was a full one (diagnostics).
    pub fn last_full_evaluation_reason(&self) -> &'static str {
        self.evaluation.recalc.full_reason
    }

    /// The template of formula `f` of `sheet`.
    fn formula_template(&mut self, sheet: u32, f: i32) -> Option<Arc<FormulaTemplate>> {
        let node = self.parsed_formulas.get(sheet as usize)?.get(f as usize)?.0.clone();
        let address = Arc::as_ptr(&node) as usize;
        let templates = &mut self.evaluation.recalc.templates;
        if let Some((_, template)) = templates.get(&address) {
            return Some(template.clone());
        }
        let template = Arc::new(FormulaTemplate::of(&node));
        templates.insert(address, (node, template.clone()));
        Some(template)
    }

    /// The formula at a position, if any: `(sheet, f)`.
    fn formula_at(&self, (sheet, row, column): CellKey) -> Option<i32> {
        let worksheet = self.workbook.worksheets.get(sheet as usize)?;
        let cell = worksheet.sheet_data.cell(row, column)?;
        FormulaCell::of(&cell).map(|c| c.f)
    }

    fn build_index(&mut self) {
        let mut cells: Vec<(CellKey, i32)> = Vec::new();
        for (sheet, worksheet) in self.sheets_with_formulas() {
            for (row, column, cell) in worksheet.sheet_data.cells() {
                if let Some(formula_cell) = FormulaCell::of(&cell) {
                    cells.push(((sheet, row, column), formula_cell.f));
                }
            }
        }
        let mut index = DependencyIndex::with_capacity(cells.len());
        for (key, f) in cells {
            if let Some(template) = self.formula_template(key.0, f) {
                index.add(key, template, true);
            }
        }
        index.finish_bulk();
        self.evaluation.recalc.index = Some(index);
    }

    /// Applies the reported changes to the index (see `Recalc`). If the
    /// bookkeeping is not valid the index is dropped.
    pub(super) fn apply_changes_to_index(&mut self) {
        if !self.evaluation.recalc.valid {
            self.evaluation.recalc.mark_full();
            return;
        }
        let Some(mut index) = self.evaluation.recalc.index.take() else {
            return;
        };
        let changed = std::mem::take(&mut self.evaluation.recalc.changed);
        for key in &changed {
            index.remove(*key);
            if let Some(f) = self.formula_at(*key) {
                if let Some(template) = self.formula_template(key.0, f) {
                    index.add(*key, template, false);
                }
            }
        }
        self.evaluation.recalc.changed = changed;
        self.evaluation.recalc.index = Some(index);
    }

    /// Records, after a full evaluation, where the array formulas are: the
    /// incremental passes that follow never run one, so this stays true until
    /// the next full evaluation. (An edit can change an anchor or its spill
    /// cells directly, which is why the areas are recorded beforehand.)
    pub(super) fn record_array_areas(&mut self) {
        let mut areas: Vec<(u32, i32, i32, i32, i32)> = Vec::new();
        let mut blocked = false;
        for anchor in &self.evaluation.anchor_order {
            let Some(cell) = self.fetch_cell(*anchor) else {
                blocked = true;
                continue;
            };
            let (width, height) = match &*cell {
                Cell::ArrayFormula { r, .. } => *r,
                _ => {
                    blocked = true;
                    continue;
                }
            };
            if let CalcResult::Error {
                error: Error::SPILL | Error::CIRC,
                ..
            } = self.get_cell_value(&cell, *anchor)
            {
                // Blocked, or on a cycle through its own area: any edit may
                // change that, and which of two contending arrays wins depends
                // on the order a full evaluation finds them in.
                blocked = true;
            }
            areas.push((
                anchor.sheet,
                anchor.row,
                anchor.column,
                anchor.row + height - 1,
                anchor.column + width - 1,
            ));
        }
        for ((sheet, row, column), (width, height)) in &self.evaluation.cse_anchors {
            areas.push((*sheet, *row, *column, row + height - 1, column + width - 1));
        }
        self.evaluation.recalc.array_areas = areas;
        self.evaluation.recalc.spill_blocked = blocked;
    }

    /// True if an edit at one of `changed` may move, block or unblock a spill:
    /// then only a full evaluation is known to be right.
    fn arrays_block_incremental(&self, changed: &[CellKey]) -> bool {
        let recalc = &self.evaluation.recalc;
        if recalc.spill_blocked {
            return true;
        }
        let areas = &recalc.array_areas;
        for key @ (sheet, row, column) in changed {
            // A dynamic anchor that holds a single value (INDEX/MATCH,
            // INDIRECT, LET, … are parsed as dynamic arrays) has no spill
            // cells: editing it is like editing any formula. If its new
            // formula spills, the pass is abandoned (`run_top`).
            if areas.iter().any(|(s, r1, c1, r2, c2)| {
                s == sheet
                    && r1 <= row
                    && row <= r2
                    && c1 <= column
                    && column <= c2
                    && !(r1 == r2 && c1 == c2 && !self.is_cse_anchor((*s, *r1, *c1)))
            }) {
                return true;
            }
            if self.workbook.worksheets.get(*sheet as usize).is_none() {
                return true;
            }
            let reference = CellReferenceIndex {
                sheet: key.0,
                row: key.1,
                column: key.2,
            };
            match self.fetch_cell(reference).as_deref() {
                Some(Cell::SpillCell { .. }) => return true,
                Some(Cell::ArrayFormula { kind, r, .. }) => {
                    if *kind != ArrayKind::Dynamic || *r != (1, 1) {
                        return true;
                    }
                }
                _ => {}
            }
        }
        false
    }

    /// What `sync_anchor_order` would do, knowing that only the changed
    /// positions can have become or stopped being dynamic anchors: drop the
    /// ones that are gone, append the new ones in natural order.
    fn sync_anchor_order_for(&mut self, changed: &[CellKey]) {
        let is_dynamic_anchor = |model: &Self, (sheet, row, column): CellKey| {
            matches!(
                model.fetch_cell(CellReferenceIndex { sheet, row, column }).as_deref(),
                Some(Cell::ArrayFormula {
                    kind: ArrayKind::Dynamic,
                    ..
                })
            )
        };
        let changed_set: HashSet<CellKey, KeyBuild> = changed.iter().copied().collect();
        let gone: Vec<bool> = self
            .evaluation
            .anchor_order
            .iter()
            .map(|a| {
                let k = (a.sheet, a.row, a.column);
                changed_set.contains(&k) && !is_dynamic_anchor(self, k)
            })
            .collect();
        let mut i = 0;
        self.evaluation.anchor_order.retain(|_| {
            i += 1;
            !gone[i - 1]
        });
        let known: HashSet<CellKey, KeyBuild> = self
            .evaluation
            .anchor_order
            .iter()
            .map(|a| (a.sheet, a.row, a.column))
            .collect();
        // `changed` is sorted: natural order.
        let new: Vec<CellReferenceIndex> = changed
            .iter()
            .filter(|k| !known.contains(k) && is_dynamic_anchor(self, **k))
            .map(|(sheet, row, column)| CellReferenceIndex {
                sheet: *sheet,
                row: *row,
                column: *column,
            })
            .collect();
        self.evaluation.anchor_order.extend(new);
    }

    fn is_cse_anchor(&self, key: CellKey) -> bool {
        self.evaluation.cse_anchors.iter().any(|(k, _)| *k == key)
    }

    /// Foglio fork: evaluates what the reported edits may have changed (see
    /// the module documentation), or everything if that cannot be done safely.
    pub(crate) fn evaluate_pending(&mut self) {
        if !self.evaluation.recalc.tracking || !self.evaluation.recalc.valid {
            self.evaluation.recalc.full_reason = "not tracked or not valid";
            self.evaluate();
            return;
        }
        if self.evaluation.recalc.cycles {
            self.evaluation.recalc.full_reason = "circular references";
            self.evaluate();
            return;
        }
        let mut changed = std::mem::take(&mut self.evaluation.recalc.changed);
        changed.sort_unstable();
        changed.dedup();
        if self.arrays_block_incremental(&changed) {
            self.evaluation.recalc.changed = changed;
            self.evaluation.recalc.full_reason = "edit touches an array";
            self.evaluate();
            return;
        }
        // Bring the index up to date (or build it from the current content).
        self.evaluation.recalc.changed = changed;
        if self.evaluation.recalc.index.is_some() {
            self.apply_changes_to_index();
        } else {
            self.build_index();
        }
        let changed = std::mem::take(&mut self.evaluation.recalc.changed);
        // Links of cells that are no longer HYPERLINK formulas.
        if !self.links.is_empty() {
            for key in &changed {
                self.links.remove(key);
            }
        }

        self.sync_anchor_order_for(&changed);
        let Some(dirty) = self.dirty_closure(&changed) else {
            self.evaluation.recalc.full_reason = "dirty set too large";
            self.evaluate();
            return;
        };
        // The same order as a full pass (`run_pass`), restricted to the dirty
        // formulas: the dynamic anchors in their order, then every formula in
        // natural order. A formula that is not dirty cannot reach a dirty one,
        // so the recursion inside the dirty formulas, and with it what a cycle
        // is reported on, is the one a full pass would make.
        let mut order: Vec<CellKey> = self
            .evaluation
            .anchor_order
            .iter()
            .map(|a| (a.sheet, a.row, a.column))
            .filter(|k| dirty.contains(k))
            .collect();
        let first: HashSet<CellKey, KeyBuild> = order.iter().copied().collect();
        let mut rest: Vec<CellKey> = dirty.iter().copied().filter(|k| !first.contains(k)).collect();
        rest.sort_unstable();
        order.extend(rest);
        let count = order.len();
        let restart = self.run_incremental_pass(order, dirty);
        if restart.is_none() && !self.evaluation.circular.is_empty() {
            // A cycle: what it is reported on depends on where the recursion
            // entered it, which only a full evaluation decides.
            self.evaluation.recalc.full_reason = "circular references";
            self.evaluate();
            return;
        }
        if let Some(_restart) = restart {
            // Not expected (no array runs); start over with a full evaluation.
            self.evaluation.recalc.full_reason = "restart";
            self.evaluate();
            return;
        }
        self.evaluate_conditional_formatting();
        self.evaluation.recalc.last_incremental = Some(count);
        if self.evaluation.recalc.check {
            self.check_against_full_evaluation();
        }
    }

    /// The formulas to run: see the module documentation. `None` if that is
    /// too much work or too many formulas for an incremental pass to pay.
    fn dirty_closure(&self, changed: &[CellKey]) -> Option<HashSet<CellKey, KeyBuild>> {
        let index = self.evaluation.recalc.index.as_ref()?;
        let formula_count = index.formula_count();
        let budget = formula_count * WORK_PER_FORMULA + WORK_CONSTANT;
        let mut work = 0usize;
        let mut dirty: HashSet<CellKey, KeyBuild> = HashSet::default();
        let mut queue: Vec<CellKey> = Vec::new();
        for key in changed {
            if index.contains_formula(key) && dirty.insert(*key) {
                queue.push(*key);
            }
        }
        for key in &index.volatile {
            if dirty.insert(*key) {
                queue.push(*key);
            }
        }
        // The spill cells of an array anchor change with it.
        let areas: std::collections::HashMap<CellKey, (i32, i32, i32, i32), KeyBuild> = self
            .evaluation
            .recalc
            .array_areas
            .iter()
            .filter(|(_, r1, c1, r2, c2)| r1 != r2 || c1 != c2)
            .map(|(s, r1, c1, r2, c2)| ((*s, *r1, *c1), (*r1, *c1, *r2, *c2)))
            .collect();
        // Positions whose value changed: the edited ones, then every dirty formula.
        let mut sources: Vec<CellKey> = changed.to_vec();
        loop {
            while let Some(position) = sources.pop() {
                if let Some((r1, c1, r2, c2)) = areas.get(&position) {
                    for r in *r1..=*r2 {
                        for c in *c1..=*c2 {
                            if (r, c) != (position.1, position.2) {
                                work += index.dependents_of((position.0, r, c), |dependent| {
                                    if dirty.insert(dependent) {
                                        queue.push(dependent);
                                    }
                                });
                            }
                        }
                    }
                }
                work += index.dependents_of(position, |dependent| {
                    if dirty.insert(dependent) {
                        queue.push(dependent);
                    }
                });
                if work > budget {
                    return None;
                }
            }
            if queue.is_empty() {
                break;
            }
            sources.append(&mut queue);
        }
        if formula_count > 1000 && dirty.len() * 2 > formula_count {
            return None;
        }
        Some(dirty)
    }

    /// Runs the dirty formulas only. Like `run_pass`, but HYPERLINK links of
    /// the formulas that do not run are kept.
    fn run_incremental_pass(
        &mut self,
        order: Vec<CellKey>,
        dirty: HashSet<CellKey, KeyBuild>,
    ) -> Option<Restart> {
        let state = &mut self.evaluation;
        state.cells.clear();
        state.stack.clear();
        state.seen.clear();
        state.seen_ranges.clear();
        state.restart = None;
        state.depth = 0;
        state.unwinding = false;
        state.circular.clear();
        state.in_pass = true;
        state.dirty = Some(dirty);
        state.lookup_cache.reset(true);
        self.clear_variable_stack();
        self.clear_lambdas();
        let mut restart = None;
        for (sheet, row, column) in order {
            let cell = CellReferenceIndex { sheet, row, column };
            self.evaluation.root = Some(cell);
            self.evaluate_cell(cell);
            if self.evaluation.restart.is_some() {
                restart = self.evaluation.restart.take();
                break;
            }
        }
        self.evaluation.in_pass = false;
        self.evaluation.root = None;
        self.evaluation.dirty = None;
        self.evaluation.lookup_cache.reset(false);
        restart
    }

    /// Runs a full evaluation and panics if any cell differs from what the
    /// incremental evaluation left.
    fn check_against_full_evaluation(&mut self) {
        let incremental: Vec<_> = self
            .workbook
            .worksheets
            .iter()
            .map(|w| w.sheet_data.clone())
            .collect();
        let incremental_links = self.links.clone();
        let ran = self.evaluation.recalc.last_incremental;
        let dump: Vec<String> = if std::env::var("IRONCALC_CHECK_DUMP").is_ok() {
            let mut lines = Vec::new();
            for (sheet, worksheet) in self.workbook.worksheets.iter().enumerate() {
                for (row, column, cell) in worksheet.sheet_data.cells() {
                    let content = self
                        .get_localized_cell_content(sheet as u32, row, column)
                        .unwrap_or_default();
                    lines.push(format!("  {sheet}!R{row}C{column} {content}  => {cell:?}"));
                }
            }
            lines
        } else {
            Vec::new()
        };
        self.evaluate();
        self.evaluation.recalc.last_incremental = ran;
        for (sheet, (worksheet, before)) in self
            .workbook
            .worksheets
            .iter()
            .zip(incremental.iter())
            .enumerate()
        {
            if worksheet.sheet_data == *before {
                continue;
            }
            let mut message = format!(
                "incremental evaluation differs from a full one on sheet {sheet} ('{}')",
                worksheet.name
            );
            let after: Vec<_> = worksheet.sheet_data.cells().collect();
            let earlier: Vec<_> = before.cells().collect();
            let mut shown = 0;
            for (row, column, cell) in &after {
                let old = before.cell(*row, *column);
                if old.as_deref() != Some(&**cell) && shown < 10 {
                    message.push_str(&format!(
                        "\n  R{row}C{column}: incremental {old:?}, full {cell:?}"
                    ));
                    shown += 1;
                }
            }
            for (row, column, cell) in &earlier {
                if worksheet.sheet_data.cell(*row, *column).is_none() && shown < 10 {
                    message.push_str(&format!(
                        "\n  R{row}C{column}: incremental {cell:?}, full (none)"
                    ));
                    shown += 1;
                }
            }
            if !dump.is_empty() {
                message.push_str("\nworkbook after the incremental evaluation:\n");
                message.push_str(&dump.join("\n"));
            }
            panic!("{message}");
        }
        assert!(
            incremental_links == self.links,
            "incremental evaluation left different HYPERLINK links than a full one"
        );
    }
}
