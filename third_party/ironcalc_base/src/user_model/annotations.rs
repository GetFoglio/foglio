//! Foglio fork: comments and data validation in the user model (with undo),
//! and history groups (several operations undone as one step).

use bitcode::{Decode, Encode};

use crate::{
    data_validation::{rects_to_sqref, DataValidation, DataValidationResult},
    expressions::types::Area,
    types::Comment,
};

use super::{common::UserModel, history::Diff};

/// What a `Diff::SetSheetAnnotations` installs: the comments and data
/// validation rules of a sheet.
#[derive(Clone, Encode, Decode, PartialEq, Debug, Default)]
pub(crate) struct SheetAnnotations {
    pub(crate) comments: Vec<Comment>,
    pub(crate) data_validations: Vec<DataValidation>,
}

fn area_rect(area: &Area) -> (i32, i32, i32, i32) {
    (
        area.row,
        area.column,
        area.row + area.height - 1,
        area.column + area.width - 1,
    )
}

impl UserModel<'_> {
    fn annotations(&self, sheet: u32) -> Result<SheetAnnotations, String> {
        let ws = self.model.workbook.worksheet(sheet)?;
        Ok(SheetAnnotations {
            comments: ws.comments.clone(),
            data_validations: ws.data_validations.clone(),
        })
    }

    pub(super) fn install_annotations(
        &mut self,
        sheet: u32,
        value: &SheetAnnotations,
    ) -> Result<(), String> {
        let ws = self.model.workbook.worksheet_mut(sheet)?;
        ws.comments = value.comments.clone();
        ws.data_validations = value.data_validations.clone();
        Ok(())
    }

    /// The annotations of every sheet, before a structural action.
    pub(super) fn annotations_snapshot(&self) -> Vec<SheetAnnotations> {
        (0..self.model.workbook.worksheets.len() as u32)
            .map(|s| self.annotations(s).unwrap_or_default())
            .collect()
    }

    /// After a structural action: a no-op diff holding the previous annotations
    /// of every sheet they changed in, so that undo restores them exactly.
    pub(super) fn annotations_snapshot_diffs(&self, old: Vec<SheetAnnotations>) -> Vec<Diff> {
        old.into_iter()
            .enumerate()
            .filter(|(s, a)| self.annotations(*s as u32).ok().as_ref() != Some(a))
            .map(|(s, a)| Diff::SetSheetAnnotations {
                sheet: s as u32,
                old_value: Box::new(a.clone()),
                new_value: Box::new(a),
            })
            .collect()
    }

    /// Runs `f` on the model and records the change of the annotations of
    /// `sheet` as one undo step.
    fn change_annotations<F>(&mut self, sheet: u32, f: F) -> Result<(), String>
    where
        F: FnOnce(&mut crate::Model) -> Result<(), String>,
    {
        let old_value = self.annotations(sheet)?;
        if let Err(e) = f(&mut self.model) {
            self.install_annotations(sheet, &old_value)?;
            return Err(e);
        }
        let new_value = self.annotations(sheet)?;
        if new_value != old_value {
            self.push_diff_list(vec![Diff::SetSheetAnnotations {
                sheet,
                old_value: Box::new(old_value),
                new_value: Box::new(new_value),
            }]);
        }
        Ok(())
    }

    // ---------------------------------------------------------------- comments

    /// Returns the comment (note) of cell (`row`, `column`), if any.
    pub fn get_comment(&self, sheet: u32, row: i32, column: i32) -> Result<Option<Comment>, String> {
        self.model.get_comment(sheet, row, column)
    }

    /// All the comments of the sheet.
    pub fn get_comments(&self, sheet: u32) -> Result<&[Comment], String> {
        Ok(&self.model.workbook.worksheet(sheet)?.comments)
    }

    /// Cells with a comment in the area, sorted by (row, column).
    pub fn get_comment_cells(&self, area: &Area) -> Result<Vec<(i32, i32)>, String> {
        self.model.get_comment_cells(area.sheet, area_rect(area))
    }

    /// Sets the comment of cell (`row`, `column`); an empty text deletes it.
    pub fn set_comment(
        &mut self,
        sheet: u32,
        row: i32,
        column: i32,
        text: &str,
        author: &str,
    ) -> Result<(), String> {
        if text.is_empty() {
            return self.delete_comment(sheet, row, column);
        }
        self.change_annotations(sheet, |m| m.set_comment(sheet, row, column, text, author))
    }

    /// Removes the comment of cell (`row`, `column`). Not an error if there is none.
    pub fn delete_comment(&mut self, sheet: u32, row: i32, column: i32) -> Result<(), String> {
        self.change_annotations(sheet, |m| m.delete_comment(sheet, row, column))
    }

    // ---------------------------------------------------------- data validation

    /// The rule that applies to cell (`row`, `column`), if any (formulas in the
    /// stored form, see [`crate::data_validation`]).
    pub fn get_data_validation(
        &self,
        sheet: u32,
        row: i32,
        column: i32,
    ) -> Result<Option<DataValidation>, String> {
        Ok(self.model.get_data_validation(sheet, row, column)?.cloned())
    }

    /// All the rules of the sheet.
    pub fn get_data_validations(&self, sheet: u32) -> Result<&[DataValidation], String> {
        self.model.get_data_validations(sheet)
    }

    /// Applies `rule` (formulas in the stored form) to `area`, replacing the
    /// rules the cells had. `rule.sqref` is ignored.
    pub fn set_data_validation(&mut self, area: &Area, rule: DataValidation) -> Result<(), String> {
        let mut rule = rule;
        rule.sqref = rects_to_sqref(&[area_rect(area)]);
        // Check the formulas parse
        let sheet = area.sheet;
        for f in [&rule.formula1, &rule.formula2].into_iter().flatten() {
            if crate::data_validation::inline_list_items(f).is_none()
                && self
                    .model
                    .data_validation_formula_from_user(
                        sheet,
                        (area.row, area.column),
                        crate::data_validation::DataValidationKind::Custom,
                        f,
                    )
                    .is_err()
            {
                return Err(format!("Invalid formula: '{f}'"));
            }
        }
        self.change_annotations(sheet, |m| m.add_data_validation(sheet, rule))
    }

    /// Removes data validation from the cells of `area`.
    pub fn clear_data_validation(&mut self, area: &Area) -> Result<(), String> {
        let sheet = area.sheet;
        let rect = area_rect(area);
        self.change_annotations(sheet, |m| m.remove_data_validation_area(sheet, rect))
    }

    /// See [`crate::Model::get_data_validation_list`].
    pub fn get_data_validation_list(
        &mut self,
        sheet: u32,
        row: i32,
        column: i32,
    ) -> Result<Option<Vec<String>>, String> {
        self.model.get_data_validation_list(sheet, row, column)
    }

    /// See [`crate::Model::validate_input`].
    pub fn validate_input(
        &mut self,
        sheet: u32,
        row: i32,
        column: i32,
        input: &str,
    ) -> Result<DataValidationResult, String> {
        self.model.validate_input(sheet, row, column, input)
    }

    /// `rule` with `formula1`/`formula2` converted from what the user typed (in
    /// the workbook language and locale) to the stored form. `anchor` is the
    /// first cell of the range the rule is for.
    /// See [`crate::Model::data_validation_formula_from_user`].
    pub fn data_validation_from_user(
        &mut self,
        sheet: u32,
        anchor: (i32, i32),
        rule: DataValidation,
    ) -> Result<DataValidation, String> {
        let mut rule = rule;
        let convert = |m: &mut crate::Model, f: Option<String>| -> Result<Option<String>, String> {
            match f {
                Some(f) if !f.trim().is_empty() => Ok(Some(
                    m.data_validation_formula_from_user(sheet, anchor, rule.kind, &f)?,
                )),
                _ => Ok(None),
            }
        };
        let kind = rule.kind;
        rule.formula1 = convert(&mut self.model, rule.formula1.take())?;
        rule.formula2 = if kind.uses_operator() && rule.operator.is_range() {
            convert(&mut self.model, rule.formula2.take())?
        } else {
            None
        };
        // Excel needs the formulas of a rule
        if kind != crate::data_validation::DataValidationKind::Any && rule.formula1.is_none() {
            return Err("The rule needs a value (formula1)".to_string());
        }
        if kind.uses_operator() && rule.operator.is_range() && rule.formula2.is_none() {
            return Err("The rule needs a second value (formula2)".to_string());
        }
        Ok(rule)
    }

    /// `rule` with its formulas as the user would type them.
    /// See [`crate::Model::data_validation_formula_to_user`].
    pub fn data_validation_to_user(&self, sheet: u32, rule: &DataValidation) -> DataValidation {
        let mut out = rule.clone();
        let anchor = crate::data_validation::parse_sqref_rects(&rule.sqref)
            .first()
            .map(|r| (r.0, r.1))
            .unwrap_or((1, 1));
        let to_user = |f: &Option<String>| {
            f.as_ref().map(|f| {
                self.model
                    .data_validation_formula_to_user(sheet, anchor, rule.kind, f)
            })
        };
        out.formula1 = to_user(&rule.formula1);
        out.formula2 = to_user(&rule.formula2);
        out
    }

    /// See [`crate::Model::english_formula_to_user`].
    pub fn english_formula_to_user(&self, sheet: u32, row: i32, column: i32, formula: &str) -> String {
        self.model.english_formula_to_user(sheet, row, column, formula)
    }

    // ----------------------------------------------------------- history groups

    /// Starts a history group: everything pushed to the history until the
    /// matching [`UserModel::end_history_group`] is undone and redone as one
    /// step. Groups nest.
    pub fn begin_history_group(&mut self) {
        match self.history.group.as_mut() {
            Some((depth, _)) => *depth += 1,
            None => self.history.group = Some((1, vec![])),
        }
    }

    /// Closes a history group (see [`UserModel::begin_history_group`]).
    pub fn end_history_group(&mut self) {
        let Some((depth, _)) = self.history.group.as_mut() else {
            return;
        };
        if *depth > 1 {
            *depth -= 1;
            return;
        }
        if let Some((_, list)) = self.history.group.take() {
            if !list.is_empty() {
                self.history.push(list);
            }
        }
    }
}
