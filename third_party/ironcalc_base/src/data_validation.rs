//! Foglio fork: data validation (Excel's "Data Validation" / "Convalida dati")
//! and cell comments (notes).
//!
//! Both are sheet metadata keyed by cell positions:
//! * comments live in [`Worksheet::comments`](crate::types::Worksheet) (one per
//!   cell, `cell_ref` like `"B2"`),
//! * data validation rules in `Worksheet::data_validations`, each applying to
//!   an `sqref` (space separated A1 ranges, `"A1:A10 C3"`) like in xlsx.
//!
//! Formulas of a rule (`formula1`, `formula2`) are stored the way xlsx stores
//! them: English function names, `,` separators, `.` decimals, no leading `=`,
//! relative references relative to the top-left cell of the first range of
//! `sqref`. Inline lists are a quoted string (`"\"a,b,c\""`), dates are serial
//! numbers, times fractions of a day.
//!
//! Rows/columns inserted, deleted or moved displace both (see
//! [`Model::displace_annotations`]); the undo history keeps a snapshot (see
//! `user_model/annotations.rs`).

use bitcode::{Decode, Encode};
use serde::{Deserialize, Serialize};

use crate::{
    calc_result::CalcResult,
    expressions::{
        parser::{
            stringify::{rename_sheet_in_node, to_english_string, to_string_displaced, DisplaceData},
            ArrayNode, Node,
        },
        types::{CellReferenceIndex, CellReferenceRC},
        utils::{number_to_column, parse_reference_a1},
    },
    formatter::format::{format_number, parse_formatted_number},
    functions::date_and_time::parse_time_of_day,
    language::get_default_language,
    locale::get_default_locale,
    types::Comment,
    Model,
};

/// Maximum number of items returned for a list validation.
const MAX_LIST_ITEMS: usize = 10_000;

/// What a rule accepts (xlsx `type`).
#[derive(Serialize, Deserialize, Encode, Decode, Debug, PartialEq, Eq, Clone, Copy, Default)]
pub enum DataValidationKind {
    /// Any value (xlsx `none`): only the input message is shown.
    #[default]
    #[serde(rename = "none")]
    Any,
    /// A whole number
    #[serde(rename = "whole")]
    Whole,
    /// A decimal number
    #[serde(rename = "decimal")]
    Decimal,
    /// One of a list of values: inline items or the cells of a range
    #[serde(rename = "list")]
    List,
    /// A date (a serial number)
    #[serde(rename = "date")]
    Date,
    /// A time of the day (a fraction of a day)
    #[serde(rename = "time")]
    Time,
    /// A text whose length satisfies the operator
    #[serde(rename = "textLength")]
    TextLength,
    /// A formula that must be TRUE (or a non-zero number)
    #[serde(rename = "custom")]
    Custom,
}

impl DataValidationKind {
    /// The xlsx name of the type
    pub fn xlsx_name(&self) -> &'static str {
        match self {
            DataValidationKind::Any => "none",
            DataValidationKind::Whole => "whole",
            DataValidationKind::Decimal => "decimal",
            DataValidationKind::List => "list",
            DataValidationKind::Date => "date",
            DataValidationKind::Time => "time",
            DataValidationKind::TextLength => "textLength",
            DataValidationKind::Custom => "custom",
        }
    }
    /// Reads the xlsx name of the type (unknown names are `Any`)
    pub fn from_xlsx_name(s: &str) -> DataValidationKind {
        match s {
            "whole" => DataValidationKind::Whole,
            "decimal" => DataValidationKind::Decimal,
            "list" => DataValidationKind::List,
            "date" => DataValidationKind::Date,
            "time" => DataValidationKind::Time,
            "textLength" => DataValidationKind::TextLength,
            "custom" => DataValidationKind::Custom,
            _ => DataValidationKind::Any,
        }
    }
    /// Whether the rule compares a value with `formula1` (and `formula2`) using an operator
    pub fn uses_operator(&self) -> bool {
        matches!(
            self,
            DataValidationKind::Whole
                | DataValidationKind::Decimal
                | DataValidationKind::Date
                | DataValidationKind::Time
                | DataValidationKind::TextLength
        )
    }
}

/// Comparison of the rule (xlsx `operator`, default `between`).
#[derive(Serialize, Deserialize, Encode, Decode, Debug, PartialEq, Eq, Clone, Copy, Default)]
#[serde(rename_all = "camelCase")]
#[allow(missing_docs)]
pub enum DataValidationOperator {
    #[default]
    Between,
    NotBetween,
    Equal,
    NotEqual,
    LessThan,
    LessThanOrEqual,
    GreaterThan,
    GreaterThanOrEqual,
}

impl DataValidationOperator {
    /// The xlsx name of the operator
    pub fn xlsx_name(&self) -> &'static str {
        match self {
            DataValidationOperator::Between => "between",
            DataValidationOperator::NotBetween => "notBetween",
            DataValidationOperator::Equal => "equal",
            DataValidationOperator::NotEqual => "notEqual",
            DataValidationOperator::LessThan => "lessThan",
            DataValidationOperator::LessThanOrEqual => "lessThanOrEqual",
            DataValidationOperator::GreaterThan => "greaterThan",
            DataValidationOperator::GreaterThanOrEqual => "greaterThanOrEqual",
        }
    }
    /// Reads the xlsx name of the operator (unknown names are `Between`)
    pub fn from_xlsx_name(s: &str) -> DataValidationOperator {
        match s {
            "notBetween" => DataValidationOperator::NotBetween,
            "equal" => DataValidationOperator::Equal,
            "notEqual" => DataValidationOperator::NotEqual,
            "lessThan" => DataValidationOperator::LessThan,
            "lessThanOrEqual" => DataValidationOperator::LessThanOrEqual,
            "greaterThan" => DataValidationOperator::GreaterThan,
            "greaterThanOrEqual" => DataValidationOperator::GreaterThanOrEqual,
            _ => DataValidationOperator::Between,
        }
    }
    /// Whether the operator needs `formula2`
    pub fn is_range(&self) -> bool {
        matches!(
            self,
            DataValidationOperator::Between | DataValidationOperator::NotBetween
        )
    }
    fn holds(&self, v: f64, a: f64, b: f64) -> bool {
        match self {
            DataValidationOperator::Between => v >= a.min(b) && v <= a.max(b),
            DataValidationOperator::NotBetween => !(v >= a.min(b) && v <= a.max(b)),
            DataValidationOperator::Equal => v == a,
            DataValidationOperator::NotEqual => v != a,
            DataValidationOperator::LessThan => v < a,
            DataValidationOperator::LessThanOrEqual => v <= a,
            DataValidationOperator::GreaterThan => v > a,
            DataValidationOperator::GreaterThanOrEqual => v >= a,
        }
    }
}

/// The alert shown when the input is not valid (xlsx `errorStyle`, default `stop`).
#[derive(Serialize, Deserialize, Encode, Decode, Debug, PartialEq, Eq, Clone, Copy, Default)]
#[serde(rename_all = "camelCase")]
pub enum DataValidationErrorStyle {
    /// The value is rejected
    #[default]
    Stop,
    /// The user may accept the value anyway (default answer: no)
    Warning,
    /// The user is informed, the value is accepted
    Information,
}

impl DataValidationErrorStyle {
    /// The xlsx name of the style
    pub fn xlsx_name(&self) -> &'static str {
        match self {
            DataValidationErrorStyle::Stop => "stop",
            DataValidationErrorStyle::Warning => "warning",
            DataValidationErrorStyle::Information => "information",
        }
    }
    /// Reads the xlsx name (unknown names are `Stop`)
    pub fn from_xlsx_name(s: &str) -> DataValidationErrorStyle {
        match s {
            "warning" => DataValidationErrorStyle::Warning,
            "information" => DataValidationErrorStyle::Information,
            _ => DataValidationErrorStyle::Stop,
        }
    }
}

/// A data validation rule (ECMA-376-1:2016 section 18.3.1.32). In JSON the
/// fields are camelCase (`allowBlank`, `inCellDropdown`, …) and the kind is `type`.
#[derive(Serialize, Deserialize, Encode, Decode, Debug, PartialEq, Clone)]
#[serde(rename_all = "camelCase")]
pub struct DataValidation {
    /// Cells the rule applies to: space separated A1 ranges ("A1:A10 C3")
    #[serde(default)]
    pub sqref: String,
    /// What is accepted
    #[serde(rename = "type", default)]
    pub kind: DataValidationKind,
    /// Comparison, for whole/decimal/date/time/textLength
    #[serde(default)]
    pub operator: DataValidationOperator,
    /// First formula (see the module documentation for the format)
    #[serde(default)]
    pub formula1: Option<String>,
    /// Second formula (between / notBetween)
    #[serde(default)]
    pub formula2: Option<String>,
    /// Blank cells are valid ("Ignore blank")
    #[serde(default = "default_true")]
    pub allow_blank: bool,
    /// A list shows an in-cell dropdown arrow. NB: this is the *opposite* of
    /// xlsx's `showDropDown` attribute, which hides the arrow when set.
    #[serde(default = "default_true")]
    pub in_cell_dropdown: bool,
    /// Show the input message when the cell is selected
    #[serde(default = "default_true")]
    pub show_input_message: bool,
    /// Show the error alert for invalid data (otherwise anything is accepted)
    #[serde(default = "default_true")]
    pub show_error_message: bool,
    /// Kind of alert
    #[serde(default)]
    pub error_style: DataValidationErrorStyle,
    /// Title of the error alert
    #[serde(default)]
    pub error_title: Option<String>,
    /// Message of the error alert
    #[serde(default)]
    pub error: Option<String>,
    /// Title of the input message
    #[serde(default)]
    pub prompt_title: Option<String>,
    /// Input message
    #[serde(default)]
    pub prompt: Option<String>,
}

fn default_true() -> bool {
    true
}

impl Default for DataValidation {
    fn default() -> Self {
        DataValidation {
            sqref: String::new(),
            kind: DataValidationKind::Any,
            operator: DataValidationOperator::Between,
            formula1: None,
            formula2: None,
            allow_blank: true,
            in_cell_dropdown: true,
            show_input_message: true,
            show_error_message: true,
            error_style: DataValidationErrorStyle::Stop,
            error_title: None,
            error: None,
            prompt_title: None,
            prompt: None,
        }
    }
}

/// Outcome of [`Model::validate_input`].
#[derive(Serialize, Deserialize, Debug, PartialEq, Eq, Clone)]
#[serde(rename_all = "camelCase")]
pub struct DataValidationResult {
    /// `None` if the input is valid (or the cell has no rule, or the rule does not
    /// show error alerts); otherwise the alert to show.
    pub error_style: Option<DataValidationErrorStyle>,
    /// Title of the alert as set in the rule (may be empty: the UI uses its default)
    pub title: String,
    /// Message of the alert as set in the rule (may be empty: the UI uses its default)
    pub message: String,
}

impl DataValidationResult {
    fn ok() -> Self {
        DataValidationResult {
            error_style: None,
            title: String::new(),
            message: String::new(),
        }
    }
}

/// A rectangle (first row, first column, last row, last column).
pub(crate) type Rect = (i32, i32, i32, i32);

/// Parses one part of an sqref ("A1", "A1:B5", "$A$1:$B$5"). Whole columns or rows
/// ("A:A", "1:1") are expanded to the full sheet.
pub(crate) fn parse_rect(part: &str) -> Option<Rect> {
    use crate::constants::{LAST_COLUMN, LAST_ROW};
    let upper = part.trim().to_uppercase().replace('$', "");
    let (a, b) = match upper.split_once(':') {
        Some((a, b)) => (a.to_string(), b.to_string()),
        None => (upper.clone(), upper.clone()),
    };
    let corner = |s: &str, first: bool| -> Option<(i32, i32)> {
        if let Some(r) = parse_reference_a1(s) {
            return Some((r.row, r.column));
        }
        if !s.is_empty() && s.chars().all(|c| c.is_ascii_digit()) {
            let row = s.parse::<i32>().ok()?;
            return Some((row, if first { 1 } else { LAST_COLUMN }));
        }
        if !s.is_empty() && s.chars().all(|c| c.is_ascii_uppercase()) {
            let column = crate::expressions::utils::column_to_number(s).ok()?;
            return Some((if first { 1 } else { LAST_ROW }, column));
        }
        None
    };
    let (r1, c1) = corner(&a, true)?;
    let (r2, c2) = corner(&b, false)?;
    if r1 < 1 || c1 < 1 || r2 > LAST_ROW || c2 > LAST_COLUMN {
        return None;
    }
    Some((r1.min(r2), c1.min(c2), r1.max(r2), c1.max(c2)))
}

/// All the rectangles of an sqref.
pub fn parse_sqref_rects(sqref: &str) -> Vec<(i32, i32, i32, i32)> {
    sqref.split_whitespace().filter_map(parse_rect).collect()
}

fn rect_to_string(rect: Rect) -> String {
    let (r1, c1, r2, c2) = rect;
    let a = format!("{}{}", number_to_column(c1).unwrap_or_default(), r1);
    if r1 == r2 && c1 == c2 {
        a
    } else {
        format!("{a}:{}{}", number_to_column(c2).unwrap_or_default(), r2)
    }
}

/// Writes a list of rectangles as an sqref.
pub fn rects_to_sqref(rects: &[(i32, i32, i32, i32)]) -> String {
    rects
        .iter()
        .map(|r| rect_to_string(*r))
        .collect::<Vec<_>>()
        .join(" ")
}

fn rect_contains(rect: &Rect, row: i32, column: i32) -> bool {
    row >= rect.0 && row <= rect.2 && column >= rect.1 && column <= rect.3
}

/// `a` minus `b`: up to four rectangles.
fn rect_subtract(a: Rect, b: Rect) -> Vec<Rect> {
    let (ar1, ac1, ar2, ac2) = a;
    let (br1, bc1, br2, bc2) = b;
    if br1 > ar2 || br2 < ar1 || bc1 > ac2 || bc2 < ac1 {
        return vec![a];
    }
    let mut out = Vec::new();
    // band above and below
    if br1 > ar1 {
        out.push((ar1, ac1, br1 - 1, ac2));
    }
    if br2 < ar2 {
        out.push((br2 + 1, ac1, ar2, ac2));
    }
    let (mr1, mr2) = (ar1.max(br1), ar2.min(br2));
    // left and right of the overlap
    if bc1 > ac1 {
        out.push((mr1, ac1, mr2, bc1 - 1));
    }
    if bc2 < ac2 {
        out.push((mr1, bc2 + 1, mr2, ac2));
    }
    out
}

/// New position of a row, `None` if deleted.
fn displace_row(row: i32, data: &DisplaceData, sheet: u32) -> Option<i32> {
    match data {
        DisplaceData::Row {
            sheet: s,
            row: dr,
            delta,
        } if *s == sheet => {
            if row < *dr {
                Some(row)
            } else if *delta < 0 && row < *dr - *delta {
                None
            } else {
                Some(row + *delta)
            }
        }
        DisplaceData::RowMove {
            sheet: s,
            row: mr,
            delta,
        } if *s == sheet => Some(displace_moved(row, *mr, *delta)),
        _ => Some(row),
    }
}

/// New position of a column, `None` if deleted.
fn displace_column(column: i32, data: &DisplaceData, sheet: u32) -> Option<i32> {
    match data {
        DisplaceData::Column {
            sheet: s,
            column: dc,
            delta,
        } if *s == sheet => {
            if column < *dc {
                Some(column)
            } else if *delta < 0 && column < *dc - *delta {
                None
            } else {
                Some(column + *delta)
            }
        }
        DisplaceData::ColumnMove {
            sheet: s,
            column: mc,
            delta,
        } if *s == sheet => Some(displace_moved(column, *mc, *delta)),
        _ => Some(column),
    }
}

fn displace_moved(i: i32, moved: i32, delta: i32) -> i32 {
    if i == moved {
        i + delta
    } else if delta > 0 && i > moved && i <= moved + delta {
        i - 1
    } else if delta < 0 && i < moved && i >= moved + delta {
        i + 1
    } else {
        i
    }
}

/// Displaces the interval [first, last] of rows (or columns): deleted rows are
/// clipped away, `None` if all of them are deleted.
fn displace_interval(
    first: i32,
    last: i32,
    f: &dyn Fn(i32) -> Option<i32>,
    deleted: Option<(i32, i32)>,
) -> Option<(i32, i32)> {
    let (mut a, mut b) = (first, last);
    if let Some((d1, d2)) = deleted {
        // clip the deleted part at the edges
        if a >= d1 && a <= d2 {
            a = d2 + 1;
        }
        if b >= d1 && b <= d2 {
            b = d1 - 1;
        }
        if a > b {
            return None;
        }
    }
    let (na, nb) = (f(a)?, f(b)?);
    Some((na.min(nb), na.max(nb)))
}

/// The cell (row, column) a comment is attached to.
pub fn comment_position(comment: &Comment) -> Option<(i32, i32)> {
    comment_cell(comment)
}

/// The cell a comment is attached to.
pub(crate) fn comment_cell(comment: &Comment) -> Option<(i32, i32)> {
    let r = parse_reference_a1(&comment.cell_ref.to_uppercase().replace('$', ""))?;
    Some((r.row, r.column))
}

fn cell_name(row: i32, column: i32) -> String {
    format!("{}{}", number_to_column(column).unwrap_or_default(), row)
}

/// The value the user typed, read the way [`Model::set_user_input`] reads it.
enum Candidate {
    Number(f64),
    Text(String),
    Boolean(bool),
}

impl Model<'_> {
    // ---------------------------------------------------------------- comments

    /// Returns the comment of cell (`row`, `column`), if any.
    pub fn get_comment(&self, sheet: u32, row: i32, column: i32) -> Result<Option<Comment>, String> {
        Ok(self
            .workbook
            .worksheet(sheet)?
            .comments
            .iter()
            .find(|c| comment_cell(c) == Some((row, column)))
            .cloned())
    }

    /// Sets the comment of cell (`row`, `column`), replacing an existing one.
    pub fn set_comment(
        &mut self,
        sheet: u32,
        row: i32,
        column: i32,
        text: &str,
        author: &str,
    ) -> Result<(), String> {
        if number_to_column(column).is_none() || !(1..=crate::constants::LAST_ROW).contains(&row) {
            return Err("Invalid cell".to_string());
        }
        let comments = &mut self.workbook.worksheet_mut(sheet)?.comments;
        let comment = Comment {
            text: text.to_string(),
            author_name: author.to_string(),
            author_id: None,
            cell_ref: cell_name(row, column),
        };
        match comments
            .iter_mut()
            .find(|c| comment_cell(c) == Some((row, column)))
        {
            Some(c) => *c = comment,
            None => comments.push(comment),
        }
        Ok(())
    }

    /// Removes the comment of cell (`row`, `column`). Not an error if there is none.
    pub fn delete_comment(&mut self, sheet: u32, row: i32, column: i32) -> Result<(), String> {
        self.workbook
            .worksheet_mut(sheet)?
            .comments
            .retain(|c| comment_cell(c) != Some((row, column)));
        Ok(())
    }

    /// Cells with a comment inside the rectangle, sorted by (row, column).
    pub fn get_comment_cells(
        &self,
        sheet: u32,
        rect: (i32, i32, i32, i32),
    ) -> Result<Vec<(i32, i32)>, String> {
        let mut cells: Vec<(i32, i32)> = self
            .workbook
            .worksheet(sheet)?
            .comments
            .iter()
            .filter_map(comment_cell)
            .filter(|(r, c)| rect_contains(&rect, *r, *c))
            .collect();
        cells.sort_unstable();
        cells.dedup();
        Ok(cells)
    }

    // ---------------------------------------------------------- data validation

    /// The data validation rules of the sheet.
    pub fn get_data_validations(&self, sheet: u32) -> Result<&[DataValidation], String> {
        Ok(&self.workbook.worksheet(sheet)?.data_validations)
    }

    /// The rule that applies to cell (`row`, `column`), if any.
    pub fn get_data_validation(
        &self,
        sheet: u32,
        row: i32,
        column: i32,
    ) -> Result<Option<&DataValidation>, String> {
        Ok(self
            .workbook
            .worksheet(sheet)?
            .data_validations
            .iter()
            .find(|dv| {
                parse_sqref_rects(&dv.sqref)
                    .iter()
                    .any(|r| rect_contains(r, row, column))
            }))
    }

    /// Removes the rectangle from every rule of the sheet (rules left without
    /// cells are deleted).
    pub fn remove_data_validation_area(
        &mut self,
        sheet: u32,
        rect: (i32, i32, i32, i32),
    ) -> Result<(), String> {
        let old = std::mem::take(&mut self.workbook.worksheet_mut(sheet)?.data_validations);
        let mut kept = Vec::new();
        for mut dv in old {
            let rects = parse_sqref_rects(&dv.sqref);
            let remaining: Vec<Rect> = rects
                .iter()
                .flat_map(|r| rect_subtract(*r, rect))
                .collect();
            if remaining == rects {
                kept.push(dv);
                continue;
            }
            if remaining.is_empty() {
                continue;
            }
            // The formulas are relative to the first cell of the rule: if it
            // changes they are rewritten for the new first cell.
            let old_anchor = Self::rule_anchor(&dv);
            dv.sqref = rects_to_sqref(&remaining);
            let new_anchor = Self::rule_anchor(&dv);
            if old_anchor != new_anchor {
                dv.formula1 = dv
                    .formula1
                    .take()
                    .map(|f| self.rebase_rule_formula(sheet, &f, old_anchor, new_anchor));
                dv.formula2 = dv
                    .formula2
                    .take()
                    .map(|f| self.rebase_rule_formula(sheet, &f, old_anchor, new_anchor));
            }
            kept.push(dv);
        }
        self.workbook.worksheet_mut(sheet)?.data_validations = kept;
        Ok(())
    }

    /// A stored formula anchored at `from`, written for the anchor `to`, so that
    /// every cell of the rule keeps reading the same cells.
    fn rebase_rule_formula(
        &mut self,
        sheet: u32,
        formula: &str,
        from: (i32, i32),
        to: (i32, i32),
    ) -> String {
        if inline_list_items(formula).is_some() {
            return formula.to_string();
        }
        let Some(node) = self.parse_rule_formula(sheet, formula, from) else {
            return formula.to_string();
        };
        // Relative references are stored as offsets: written in the context of
        // the new anchor they point to the cells the new anchor should read.
        let context = CellReferenceRC {
            sheet: self.workbook.worksheets[sheet as usize].get_name(),
            row: to.0,
            column: to.1,
        };
        to_english_string(&node, &context)
    }

    /// Adds a rule for `sqref` replacing whatever rule the cells had.
    pub fn add_data_validation(&mut self, sheet: u32, dv: DataValidation) -> Result<(), String> {
        let rects = parse_sqref_rects(&dv.sqref);
        if rects.is_empty() {
            return Err(format!("Invalid range: '{}'", dv.sqref));
        }
        for r in &rects {
            self.remove_data_validation_area(sheet, *r)?;
        }
        self.workbook
            .worksheet_mut(sheet)?
            .data_validations
            .push(dv);
        Ok(())
    }

    fn rule_anchor(dv: &DataValidation) -> (i32, i32) {
        parse_sqref_rects(&dv.sqref)
            .first()
            .map(|r| (r.0, r.1))
            .unwrap_or((1, 1))
    }

    /// Parses a stored (English) formula of a rule of `sheet` anchored at `anchor`.
    fn parse_rule_formula(&mut self, sheet: u32, formula: &str, anchor: (i32, i32)) -> Option<Node> {
        let body = formula.trim().strip_prefix('=').unwrap_or(formula.trim());
        if body.is_empty() {
            return None;
        }
        let context = CellReferenceRC {
            sheet: self.workbook.worksheet(sheet).ok()?.get_name(),
            row: anchor.0,
            column: anchor.1,
        };
        let node = self.parse_internal_formula(body, &context);
        if let Node::ParseErrorKind { .. } = node {
            return None;
        }
        Some(node)
    }

    /// Evaluates a stored formula of the rule for the cell (`row`, `column`).
    fn evaluate_rule_formula(
        &mut self,
        sheet: u32,
        dv: &DataValidation,
        formula: &str,
        row: i32,
        column: i32,
    ) -> CalcResult {
        let anchor = Self::rule_anchor(dv);
        let cell = CellReferenceIndex { sheet, row, column };
        match self.parse_rule_formula(sheet, formula, anchor) {
            // References in the node are relative to the anchor; evaluating in the
            // context of the cell shifts them to the cell.
            Some(node) => {
                // Outside a calculation pass a formula cell that is not known to
                // be evaluated would run again and store its result. Formulas are
                // read as they are instead: an empty dirty set says none needs to
                // run (see `evaluate_formula_cell`).
                let saved = self.evaluation.dirty.replace(Default::default());
                let result = self.evaluate_node_in_context(&node, cell);
                self.evaluation.dirty = saved;
                result
            }
            None => CalcResult::new_error(
                crate::expressions::token::Error::NAME,
                cell,
                "Invalid formula".to_string(),
            ),
        }
    }

    fn calc_result_number(&mut self, result: CalcResult) -> Option<f64> {
        match result {
            CalcResult::Number(n) => Some(n),
            CalcResult::Boolean(b) => Some(if b { 1.0 } else { 0.0 }),
            CalcResult::String(s) => self.cast_number(&s),
            CalcResult::Range { left, right } => {
                if left == right {
                    let saved = self.evaluation.dirty.replace(Default::default());
                    let v = self.evaluate_cell(left);
                    self.evaluation.dirty = saved;
                    self.calc_result_number(v)
                } else {
                    None
                }
            }
            _ => None,
        }
    }

    fn calc_result_texts(&mut self, result: CalcResult, out: &mut Vec<String>) {
        match result {
            CalcResult::Range { left, right } => {
                for row in left.row..=right.row {
                    for column in left.column..=right.column {
                        if out.len() >= MAX_LIST_ITEMS {
                            return;
                        }
                        // The values of the cells as they are displayed (formula
                        // cells hold their last computed value).
                        let text = self
                            .get_formatted_cell_value(left.sheet, row, column)
                            .unwrap_or_default();
                        if !text.is_empty() {
                            out.push(text);
                        }
                    }
                }
            }
            CalcResult::Array(rows) => {
                for row in rows {
                    for v in row {
                        if out.len() >= MAX_LIST_ITEMS {
                            return;
                        }
                        let text = match v {
                            ArrayNode::Number(n) => format_number(n, "general", self.locale).text,
                            ArrayNode::String(s) => s,
                            ArrayNode::Boolean(b) => {
                                if b { "TRUE" } else { "FALSE" }.to_string()
                            }
                            _ => String::new(),
                        };
                        if !text.is_empty() {
                            out.push(text);
                        }
                    }
                }
            }
            CalcResult::String(s) => {
                if !s.is_empty() {
                    out.push(s)
                }
            }
            CalcResult::Number(n) => out.push(format_number(n, "general", self.locale).text),
            CalcResult::Boolean(b) => out.push(if b { "TRUE" } else { "FALSE" }.to_string()),
            _ => {}
        }
    }

    /// The items of the list validation of cell (`row`, `column`): the inline
    /// items, or the displayed values of the non-empty cells of the referenced
    /// range. `None` if the cell has no list validation.
    pub fn get_data_validation_list(
        &mut self,
        sheet: u32,
        row: i32,
        column: i32,
    ) -> Result<Option<Vec<String>>, String> {
        let Some(dv) = self.get_data_validation(sheet, row, column)?.cloned() else {
            return Ok(None);
        };
        if dv.kind != DataValidationKind::List {
            return Ok(None);
        }
        let Some(formula) = dv.formula1.clone() else {
            return Ok(Some(vec![]));
        };
        if let Some(items) = inline_list_items(&formula) {
            return Ok(Some(items));
        }
        let result = self.evaluate_rule_formula(sheet, &dv, &formula, row, column);
        let mut out = Vec::new();
        self.calc_result_texts(result, &mut out);
        Ok(Some(out))
    }

    fn parse_candidate(&self, input: &str) -> Candidate {
        if let Some(text) = input.strip_prefix('\'') {
            return Candidate::Text(text.to_string());
        }
        let mut currencies = vec!["$", "€"];
        let currency = &self.locale.currency.symbol;
        if !currencies.iter().any(|e| e == currency) {
            currencies.push(currency);
        }
        if let Ok((v, _)) = parse_formatted_number(input, &currencies, self.locale) {
            return Candidate::Number(v);
        }
        if let Some(v) = parse_time_of_day(input) {
            return Candidate::Number(v);
        }
        if let Ok(b) = input.to_lowercase().parse::<bool>() {
            return Candidate::Boolean(b);
        }
        Candidate::Text(input.to_string())
    }

    /// Checks `input`, what the user is about to enter in cell (`row`, `column`),
    /// against the data validation rule of the cell.
    ///
    /// The input is read the way `set_user_input` reads it (numbers, dates and
    /// percentages in the workbook locale). Empty input and formulas are always
    /// accepted, as are values of a rule that does not show error alerts. A
    /// custom formula is evaluated with the input in the cell (other formulas are
    /// not recalculated for it).
    pub fn validate_input(
        &mut self,
        sheet: u32,
        row: i32,
        column: i32,
        input: &str,
    ) -> Result<DataValidationResult, String> {
        let Some(dv) = self.get_data_validation(sheet, row, column)?.cloned() else {
            return Ok(DataValidationResult::ok());
        };
        if !dv.show_error_message || input.is_empty() || input.starts_with('=') {
            return Ok(DataValidationResult::ok());
        }
        let valid = self.input_is_valid(sheet, row, column, &dv, input);
        if valid {
            return Ok(DataValidationResult::ok());
        }
        Ok(DataValidationResult {
            error_style: Some(dv.error_style),
            title: dv.error_title.clone().unwrap_or_default(),
            message: dv.error.clone().unwrap_or_default(),
        })
    }

    fn input_is_valid(
        &mut self,
        sheet: u32,
        row: i32,
        column: i32,
        dv: &DataValidation,
        input: &str,
    ) -> bool {
        let candidate = self.parse_candidate(input);
        let bounds = |model: &mut Self| -> Option<(f64, f64)> {
            let f1 = dv.formula1.clone()?;
            let r1 = model.evaluate_rule_formula(sheet, dv, &f1, row, column);
            let a = model.calc_result_number(r1)?;
            let b = if dv.operator.is_range() {
                let f2 = dv.formula2.clone()?;
                let r2 = model.evaluate_rule_formula(sheet, dv, &f2, row, column);
                model.calc_result_number(r2)?
            } else {
                a
            };
            Some((a, b))
        };
        match dv.kind {
            DataValidationKind::Any => true,
            DataValidationKind::Whole
            | DataValidationKind::Decimal
            | DataValidationKind::Date
            | DataValidationKind::Time => {
                let Candidate::Number(v) = candidate else {
                    return false;
                };
                if dv.kind == DataValidationKind::Whole && v.fract() != 0.0 {
                    return false;
                }
                match bounds(self) {
                    Some((a, b)) => dv.operator.holds(v, a, b),
                    None => false,
                }
            }
            DataValidationKind::TextLength => {
                let text = match candidate {
                    Candidate::Text(t) => t,
                    _ => input.to_string(),
                };
                let len = text.chars().count() as f64;
                match bounds(self) {
                    Some((a, b)) => dv.operator.holds(len, a, b),
                    None => false,
                }
            }
            DataValidationKind::List => {
                let items = self
                    .get_data_validation_list(sheet, row, column)
                    .ok()
                    .flatten()
                    .unwrap_or_default();
                let needle = match &candidate {
                    Candidate::Text(t) => t.clone(),
                    _ => input.trim().to_string(),
                };
                let needle_lower = needle.to_lowercase();
                let needle_number = match candidate {
                    Candidate::Number(v) => Some(v),
                    _ => None,
                };
                items.iter().any(|item| {
                    if item.to_lowercase() == needle_lower {
                        return true;
                    }
                    match (needle_number, self.cast_number(item)) {
                        (Some(a), Some(b)) => a == b,
                        _ => false,
                    }
                })
            }
            DataValidationKind::Custom => {
                let Some(f1) = dv.formula1.clone() else {
                    return true;
                };
                // Put the candidate in the cell, evaluate, put the cell back.
                let Ok(ws) = self.workbook.worksheet(sheet) else {
                    return true;
                };
                let old_cell = ws.cell(row, column).map(|c| c.into_owned());
                let style = old_cell.as_ref().map(|c| c.get_style()).unwrap_or(0);
                let strings_before = self.workbook.shared_strings.len();
                let set = match &candidate {
                    Candidate::Number(v) => self
                        .workbook
                        .worksheet_mut(sheet)
                        .and_then(|w| w.set_cell_with_number(row, column, *v, style)),
                    Candidate::Boolean(b) => self
                        .workbook
                        .worksheet_mut(sheet)
                        .and_then(|w| w.set_cell_with_boolean(row, column, *b, style)),
                    Candidate::Text(t) => self.set_cell_with_string(sheet, row, column, t, style),
                };
                let result = if set.is_ok() {
                    let r = self.evaluate_rule_formula(sheet, dv, &f1, row, column);
                    match r {
                        CalcResult::Boolean(b) => b,
                        CalcResult::Number(n) => n != 0.0,
                        _ => false,
                    }
                } else {
                    true
                };
                // restore
                if let Ok(ws) = self.workbook.worksheet_mut(sheet) {
                    match old_cell {
                        Some(cell) => {
                            ws.update_cell(row, column, cell).ok();
                        }
                        None => {
                            ws.remove_cell(row, column).ok();
                        }
                    }
                }
                while self.workbook.shared_strings.len() > strings_before {
                    if let Some(s) = self.workbook.shared_strings.pop() {
                        self.shared_strings.remove(&s);
                    }
                }
                result
            }
        }
    }

    // -------------------------------------------------- formulas in user form

    /// Converts what the user typed for `formula1`/`formula2` of a rule of kind
    /// `kind` (in the workbook language and locale, like Excel's dialog) into the
    /// stored form. `anchor` is the first cell of the rule.
    ///
    /// * list: `a,b,c` (items separated by the locale list separator, `;` when
    ///   the decimal separator is `,`) or a formula/reference `=$A$1:$A$5`
    /// * whole/decimal/textLength: a number (`1,5` in Italian) or `=formula`
    /// * date: a date (`31/12/2025`, `2025-12-31`) or `=formula`
    /// * time: a time (`13:30`) or `=formula`
    /// * custom: a formula, with or without `=`
    pub fn data_validation_formula_from_user(
        &mut self,
        sheet: u32,
        anchor: (i32, i32),
        kind: DataValidationKind,
        text: &str,
    ) -> Result<String, String> {
        let text = text.trim();
        let context = CellReferenceRC {
            sheet: self.workbook.worksheet(sheet)?.get_name(),
            row: anchor.0,
            column: anchor.1,
        };
        let formula = |model: &mut Self, f: &str| -> Result<String, String> {
            let english = model.user_formula_to_internal(f, &context)?;
            Ok(english.trim_start_matches('=').to_string())
        };
        if kind == DataValidationKind::Custom {
            return formula(self, text);
        }
        if text.starts_with('=') {
            return formula(self, text);
        }
        match kind {
            DataValidationKind::List => {
                let sep = self.list_separator();
                let items: Vec<String> = text
                    .split(sep)
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty())
                    .collect();
                let joined = items.join(",");
                if joined.chars().count() > 255 {
                    return Err("The list is longer than 255 characters".to_string());
                }
                Ok(format!("\"{}\"", joined.replace('"', "\"\"")))
            }
            DataValidationKind::Any => Ok(text.to_string()),
            _ => match self.parse_candidate(text) {
                Candidate::Number(v) => Ok(english_number(v)),
                _ => Err(format!("Invalid value: '{text}'")),
            },
        }
    }

    /// The opposite of [`Model::data_validation_formula_from_user`]: a stored
    /// formula as the user would type it.
    pub fn data_validation_formula_to_user(
        &self,
        sheet: u32,
        anchor: (i32, i32),
        kind: DataValidationKind,
        formula: &str,
    ) -> String {
        if kind == DataValidationKind::List {
            if let Some(items) = inline_list_items(formula) {
                return items.join(self.list_separator().to_string().as_str());
            }
        }
        let trimmed = formula.trim();
        if let Some(v) = crate::number_format::parse_finite_number(trimmed) {
            let format = match kind {
                DataValidationKind::Date => {
                    if self.locale.dates.date_formats.short.starts_with('d') {
                        "dd/mm/yyyy"
                    } else {
                        "mm/dd/yyyy"
                    }
                }
                DataValidationKind::Time => "hh:mm:ss",
                _ => "general",
            };
            return format_number(v, format, self.locale).text;
        }
        let context = CellReferenceRC {
            sheet: self
                .workbook
                .worksheet(sheet)
                .map(|w| w.get_name())
                .unwrap_or_default(),
            row: anchor.0,
            column: anchor.1,
        };
        self.internal_formula_to_display(&format!("={trimmed}"), &context)
    }

    /// Translates an English formula (as stored, with or without `=`) into the
    /// workbook language and locale, as the user would type it in cell
    /// (`row`, `column`) of `sheet`. Unparsable formulas are returned unchanged.
    pub fn english_formula_to_user(&self, sheet: u32, row: i32, column: i32, formula: &str) -> String {
        let context = CellReferenceRC {
            sheet: self
                .workbook
                .worksheet(sheet)
                .map(|w| w.get_name())
                .unwrap_or_default(),
            row,
            column,
        };
        self.internal_formula_to_display(formula, &context)
    }

    fn list_separator(&self) -> char {
        if self.locale.numbers.symbols.decimal == "," {
            ';'
        } else {
            ','
        }
    }

    // ------------------------------------------------------------ displacement

    /// Moves comments and data validation rules with their cells when rows or
    /// columns of `sheet` are inserted, deleted or moved; formulas of rules of
    /// every sheet that reference `sheet` are displaced too.
    pub(crate) fn displace_annotations(&mut self, sheet: u32, data: &DisplaceData) {
        let deleted_rows = match data {
            DisplaceData::Row {
                sheet: s,
                row,
                delta,
            } if *s == sheet && *delta < 0 => Some((*row, *row - *delta - 1)),
            _ => None,
        };
        let deleted_columns = match data {
            DisplaceData::Column {
                sheet: s,
                column,
                delta,
            } if *s == sheet && *delta < 0 => Some((*column, *column - *delta - 1)),
            _ => None,
        };
        // Formulas first: they are relative to the anchors before the change.
        let sheet_count = self.workbook.worksheets.len() as u32;
        for s in 0..sheet_count {
            let count = self.workbook.worksheets[s as usize].data_validations.len();
            for i in 0..count {
                let dv = self.workbook.worksheets[s as usize].data_validations[i].clone();
                if dv.formula1.is_none() && dv.formula2.is_none() {
                    continue;
                }
                let anchor = Self::rule_anchor(&dv);
                let f1 = dv
                    .formula1
                    .as_ref()
                    .map(|f| self.displace_rule_formula(s, f, anchor, data));
                let f2 = dv
                    .formula2
                    .as_ref()
                    .map(|f| self.displace_rule_formula(s, f, anchor, data));
                let target = &mut self.workbook.worksheets[s as usize].data_validations[i];
                target.formula1 = f1;
                target.formula2 = f2;
            }
        }
        let Some(ws) = self.workbook.worksheets.get_mut(sheet as usize) else {
            return;
        };
        let rows = |r: i32| displace_row(r, data, sheet);
        let columns = |c: i32| displace_column(c, data, sheet);
        let mut kept = Vec::new();
        for mut dv in std::mem::take(&mut ws.data_validations) {
            let rects: Vec<Rect> = parse_sqref_rects(&dv.sqref)
                .into_iter()
                .filter_map(|(r1, c1, r2, c2)| {
                    let (nr1, nr2) = displace_interval(r1, r2, &rows, deleted_rows)?;
                    let (nc1, nc2) = displace_interval(c1, c2, &columns, deleted_columns)?;
                    Some((nr1, nc1, nr2, nc2))
                })
                .collect();
            if !rects.is_empty() {
                dv.sqref = rects_to_sqref(&rects);
                kept.push(dv);
            }
        }
        ws.data_validations = kept;
        let mut comments = Vec::new();
        for mut comment in std::mem::take(&mut ws.comments) {
            let Some((r, c)) = comment_cell(&comment) else {
                comments.push(comment);
                continue;
            };
            if let (Some(nr), Some(nc)) = (rows(r), columns(c)) {
                comment.cell_ref = cell_name(nr, nc);
                comments.push(comment);
            }
        }
        ws.comments = comments;
    }

    /// Rewrites the references to sheet `sheet_index` in the formulas of every rule
    /// for its new name. Called while the sheet still has its old name.
    pub(crate) fn rename_sheet_in_data_validations(&mut self, sheet_index: u32, new_name: &str) {
        let sheet_count = self.workbook.worksheets.len() as u32;
        for s in 0..sheet_count {
            let count = self.workbook.worksheets[s as usize].data_validations.len();
            for i in 0..count {
                let dv = self.workbook.worksheets[s as usize].data_validations[i].clone();
                let anchor = Self::rule_anchor(&dv);
                let mut rename = |f: &Option<String>| -> Option<String> {
                    let f = f.as_ref()?;
                    if inline_list_items(f).is_some() {
                        return Some(f.clone());
                    }
                    let Some(mut node) = self.parse_rule_formula(s, f, anchor) else {
                        return Some(f.clone());
                    };
                    rename_sheet_in_node(&mut node, sheet_index, new_name);
                    let context = CellReferenceRC {
                        sheet: self.workbook.worksheets[s as usize].get_name(),
                        row: anchor.0,
                        column: anchor.1,
                    };
                    Some(to_english_string(&node, &context))
                };
                let f1 = rename(&dv.formula1);
                let f2 = rename(&dv.formula2);
                let target = &mut self.workbook.worksheets[s as usize].data_validations[i];
                target.formula1 = f1;
                target.formula2 = f2;
            }
        }
    }

    fn displace_rule_formula(
        &mut self,
        sheet: u32,
        formula: &str,
        anchor: (i32, i32),
        data: &DisplaceData,
    ) -> String {
        if inline_list_items(formula).is_some() {
            return formula.to_string();
        }
        let Some(node) = self.parse_rule_formula(sheet, formula, anchor) else {
            return formula.to_string();
        };
        let context = CellReferenceRC {
            sheet: self.workbook.worksheets[sheet as usize].get_name(),
            row: anchor.0,
            column: anchor.1,
        };
        to_string_displaced(
            &node,
            &context,
            data,
            get_default_locale(),
            get_default_language(),
        )
    }
}

/// The items of an inline list (`"a,b,c"`, quoted), `None` if the formula is
/// not an inline list.
pub fn inline_list_items(formula: &str) -> Option<Vec<String>> {
    let f = formula.trim();
    let inner = f.strip_prefix('"')?.strip_suffix('"')?;
    // a single string literal: no unescaped quote inside
    if inner.replace("\"\"", "").contains('"') {
        return None;
    }
    Some(
        inner
            .replace("\"\"", "\"")
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect(),
    )
}

/// A number as written in a stored formula.
fn english_number(v: f64) -> String {
    if v.fract() == 0.0 && v.abs() < 1e15 {
        format!("{}", v as i64)
    } else {
        format!("{v}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::expressions::types::Area;
    use crate::UserModel;

    #[test]
    fn rects() {
        assert_eq!(parse_rect("$B$2:A1"), Some((1, 1, 2, 2)));
        assert_eq!(parse_rect("C:C"), Some((1, 3, crate::constants::LAST_ROW, 3)));
        assert_eq!(parse_rect("1A"), None);
        // the middle of a 3x3 block
        let parts = rect_subtract((1, 1, 3, 3), (2, 2, 2, 2));
        assert_eq!(rects_to_sqref(&parts), "A1:C1 A3:C3 A2 C2");
        assert_eq!(rect_subtract((1, 1, 3, 3), (5, 5, 6, 6)), vec![(1, 1, 3, 3)]);
        assert!(rect_subtract((2, 2, 3, 3), (1, 1, 9, 9)).is_empty());
        assert_eq!(
            inline_list_items("\"a, b,\"\"c\"\"\""),
            Some(vec!["a".to_string(), "b".to_string(), "\"c\"".to_string()])
        );
        assert_eq!(inline_list_items("$A$1:$A$3"), None);
    }

    fn area(row: i32, column: i32, height: i32, width: i32) -> Area {
        Area { sheet: 0, row, column, width, height }
    }

    #[test]
    fn rules_follow_columns_and_undo() {
        let mut model = UserModel::new_empty("model", "en", "UTC", "en").unwrap();
        let rule = DataValidation {
            kind: DataValidationKind::Custom,
            formula1: Some("B1>A1".to_string()),
            ..Default::default()
        };
        model.set_data_validation(&area(1, 2, 5, 2), rule).unwrap();
        model.set_comment(0, 3, 3, "note", "me").unwrap();
        // delete column B: the rule keeps column C (now B), its formula follows
        model.delete_columns(0, 2, 1).unwrap();
        let dv = model.get_data_validation(0, 1, 2).unwrap().unwrap();
        assert_eq!(dv.sqref, "B1:B5");
        assert_eq!(dv.formula1.as_deref(), Some("#REF!>A1"));
        assert_eq!(model.get_comment(0, 3, 2).unwrap().unwrap().text, "note");
        model.undo().unwrap();
        let dv = model.get_data_validation(0, 1, 2).unwrap().unwrap();
        assert_eq!(dv.sqref, "B1:C5");
        assert_eq!(dv.formula1.as_deref(), Some("B1>A1"));
        assert!(model.get_comment(0, 3, 3).unwrap().is_some());
        model.redo().unwrap();
        assert_eq!(model.get_data_validation(0, 1, 2).unwrap().unwrap().sqref, "B1:B5");
    }

    #[test]
    fn history_groups() {
        let mut model = UserModel::new_empty("model", "en", "UTC", "en").unwrap();
        model.set_user_input(0, 1, 1, "1").unwrap();
        model.begin_history_group();
        model.set_user_input(0, 1, 1, "2").unwrap();
        model.begin_history_group();
        model.set_comment(0, 1, 1, "c", "").unwrap();
        model.end_history_group();
        model.new_sheet().unwrap();
        model.end_history_group();
        model.undo().unwrap();
        assert_eq!(model.get_formatted_cell_value(0, 1, 1).unwrap(), "1");
        assert!(model.get_comment(0, 1, 1).unwrap().is_none());
        assert_eq!(model.get_worksheets_properties().len(), 1);
        model.redo().unwrap();
        assert_eq!(model.get_formatted_cell_value(0, 1, 1).unwrap(), "2");
        assert_eq!(model.get_worksheets_properties().len(), 2);
        // an empty group pushes nothing
        model.begin_history_group();
        model.end_history_group();
        model.undo().unwrap();
        assert_eq!(model.get_worksheets_properties().len(), 1);
    }
}
