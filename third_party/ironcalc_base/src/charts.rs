//! Foglio fork: charts.
//!
//! Every worksheet keeps a list of [`Chart`]s (`Worksheet::charts`), the model
//! of an Excel chart placed on the sheet with a two-cell anchor
//! (`xdr:twoCellAnchor`). Series refer to cells with sheet-qualified absolute
//! references (`Sheet1!$B$2:$B$10`), exactly like `<c:f>` in a chart part.
//!
//! * Changes made through [`UserModel`] (add, update, delete) are one undo step
//!   each (`Diff::SetCharts`).
//! * Inserting or deleting rows and columns moves the charts on that sheet and
//!   shifts the references of every series that points into it; renaming a
//!   sheet renames it in the references ([`Model`] hooks below).
//! * [`Model::get_chart_data`] evaluates the references for drawing (and for
//!   the caches written in the xlsx chart part).

use bitcode::{Decode, Encode};
use serde::{Deserialize, Serialize};

use crate::{
    cell::CellValue,
    expressions::utils::{column_to_number, number_to_column},
    types::Worksheet,
    user_model::history::Diff,
    Model, UserModel,
};

/// The chart types Foglio draws (and writes). Unknown chart types read from a
/// file are mapped to the closest one.
#[derive(Serialize, Deserialize, Encode, Decode, Debug, PartialEq, Eq, Clone, Copy, Default)]
#[serde(rename_all = "snake_case")]
pub enum ChartKind {
    /// Clustered column (vertical bars)
    #[default]
    Column,
    /// Stacked column
    ColumnStacked,
    /// Clustered bar (horizontal bars)
    Bar,
    /// Stacked bar
    BarStacked,
    /// Line
    Line,
    /// Line with markers
    LineMarkers,
    /// Pie
    Pie,
    /// Doughnut
    Doughnut,
    /// Area
    Area,
    /// Stacked area
    AreaStacked,
    /// Scatter (XY) with markers only
    Scatter,
}

impl ChartKind {
    /// Pie and doughnut charts have no axes.
    pub fn has_axes(self) -> bool {
        !matches!(self, ChartKind::Pie | ChartKind::Doughnut)
    }
    /// The name used in the C ABI / JSON ("column", "line_markers", ...).
    pub fn name(self) -> &'static str {
        match self {
            ChartKind::Column => "column",
            ChartKind::ColumnStacked => "column_stacked",
            ChartKind::Bar => "bar",
            ChartKind::BarStacked => "bar_stacked",
            ChartKind::Line => "line",
            ChartKind::LineMarkers => "line_markers",
            ChartKind::Pie => "pie",
            ChartKind::Doughnut => "doughnut",
            ChartKind::Area => "area",
            ChartKind::AreaStacked => "area_stacked",
            ChartKind::Scatter => "scatter",
        }
    }
    /// Inverse of [`ChartKind::name`].
    pub fn from_name(name: &str) -> Option<ChartKind> {
        Some(match name {
            "column" => ChartKind::Column,
            "column_stacked" => ChartKind::ColumnStacked,
            "bar" => ChartKind::Bar,
            "bar_stacked" => ChartKind::BarStacked,
            "line" => ChartKind::Line,
            "line_markers" => ChartKind::LineMarkers,
            "pie" => ChartKind::Pie,
            "doughnut" => ChartKind::Doughnut,
            "area" => ChartKind::Area,
            "area_stacked" => ChartKind::AreaStacked,
            "scatter" => ChartKind::Scatter,
            _ => return None,
        })
    }
}

/// Where the legend goes (`c:legendPos`), or no legend.
#[derive(Serialize, Deserialize, Encode, Decode, Debug, PartialEq, Eq, Clone, Copy, Default)]
#[serde(rename_all = "snake_case")]
pub enum LegendPosition {
    /// No legend
    None,
    /// Right of the plot area
    Right,
    /// Above the plot area
    Top,
    /// Below the plot area (Excel's default for new charts)
    #[default]
    Bottom,
    /// Left of the plot area
    Left,
}

/// One corner of the anchor: a cell (1-based, like the rest of the model) and
/// an offset inside it in EMU (914400 per inch, 9525 per pixel at 96 dpi).
#[derive(Serialize, Deserialize, Encode, Decode, Debug, PartialEq, Eq, Clone, Copy, Default)]
pub struct AnchorPoint {
    /// 1-based row
    pub row: i32,
    /// 1-based column
    pub column: i32,
    /// Offset from the top of the row, in EMU
    pub row_offset: i64,
    /// Offset from the left of the column, in EMU
    pub column_offset: i64,
}

/// `xdr:twoCellAnchor`: the chart moves and resizes with the cells.
#[derive(Serialize, Deserialize, Encode, Decode, Debug, PartialEq, Eq, Clone, Copy, Default)]
pub struct ChartAnchor {
    /// Top left corner
    pub from: AnchorPoint,
    /// Bottom right corner
    pub to: AnchorPoint,
}

/// A data series (`c:ser`).
#[derive(Serialize, Deserialize, Encode, Decode, Debug, PartialEq, Eq, Clone, Default)]
pub struct ChartSeries {
    /// Reference of the series name (`c:tx/c:strRef/c:f`), without '='
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name_ref: Option<String>,
    /// Literal series name (`c:tx/c:v`), used when there is no reference
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    /// Categories (`c:cat`), or X values for scatter charts (`c:xVal`)
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub categories_ref: Option<String>,
    /// Values (`c:val`), or Y values for scatter charts (`c:yVal`)
    pub values_ref: String,
    /// Fill (line for line and scatter charts) colour, "RRGGBB"
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub color: Option<String>,
}

/// A chart placed on a worksheet.
#[derive(Serialize, Deserialize, Encode, Decode, Debug, PartialEq, Eq, Clone, Default)]
pub struct Chart {
    /// Name of the drawing object ("Chart 1")
    pub name: String,
    /// Chart type
    pub kind: ChartKind,
    /// Title; `None` means no title
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    /// The series, in plotting order
    pub series: Vec<ChartSeries>,
    /// Legend position
    pub legend: LegendPosition,
    /// Title of the category axis (X axis of scatter charts)
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub category_axis_title: Option<String>,
    /// Title of the value axis (Y axis of scatter charts)
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub value_axis_title: Option<String>,
    /// Placement on the sheet
    pub anchor: ChartAnchor,
    /// Foglio fork (pictures): stacking order among the drawing objects of the
    /// sheet, shared with pictures (see pictures.rs); higher is in front
    #[serde(default)]
    pub z: i32,
}

// ---------------------------------------------------------------------------
// References
// ---------------------------------------------------------------------------

/// A sheet-qualified rectangular reference (1-based, inclusive).
#[derive(Debug, PartialEq, Eq, Clone)]
pub struct ChartRef {
    /// Sheet name (unquoted)
    pub sheet: String,
    /// First row
    pub row1: i32,
    /// First column
    pub column1: i32,
    /// Last row
    pub row2: i32,
    /// Last column
    pub column2: i32,
}

const MAX_ROW: i32 = 1_048_576;
const MAX_COLUMN: i32 = 16_384;

fn parse_cell_part(s: &str) -> Option<(Option<i32>, Option<i32>)> {
    // "$B$2", "B2", "$B" (whole column), "$2" (whole row)
    let s = s.replace('$', "");
    let letters: String = s.chars().take_while(|c| c.is_ascii_alphabetic()).collect();
    let digits = &s[letters.len()..];
    if letters.is_empty() && digits.is_empty() {
        return None;
    }
    let column = if letters.is_empty() {
        None
    } else {
        Some(column_to_number(&letters.to_uppercase()).ok()?)
    };
    let row = if digits.is_empty() {
        None
    } else {
        if !digits.chars().all(|c| c.is_ascii_digit()) {
            return None;
        }
        Some(digits.parse::<i32>().ok()?)
    };
    Some((row, column))
}

/// "A1", "XFD10", "R1C1", "R", "C" would be read as references.
fn looks_like_reference(name: &str) -> bool {
    let upper = name.to_ascii_uppercase();
    let letters: String = upper.chars().take_while(|c| c.is_ascii_alphabetic()).collect();
    let digits = &upper[letters.len()..];
    let a1 = !letters.is_empty()
        && letters.len() <= 3
        && !digits.is_empty()
        && digits.chars().all(|c| c.is_ascii_digit())
        && column_to_number(&letters).is_ok();
    let r1c1 = upper.starts_with('R') && {
        let rest = upper[1..].trim_start_matches(|c: char| c.is_ascii_digit());
        rest.is_empty() || (rest.starts_with('C') && rest[1..].chars().all(|c| c.is_ascii_digit()))
    };
    a1 || r1c1 || upper == "C" || (upper.starts_with('C') && upper[1..].chars().all(|c| c.is_ascii_digit()))
}

impl ChartRef {
    /// Parses `Sheet1!$A$1:$B$2`, `'My sheet'!A1`, `Sheet1!$B:$B`, with or
    /// without a leading '='. Returns `None` for anything else (defined
    /// names, unions, #REF!).
    pub fn parse(formula: &str) -> Option<ChartRef> {
        let f = formula.trim().trim_start_matches('=');
        let bang = f.rfind('!')?;
        let (sheet, range) = (&f[..bang], &f[bang + 1..]);
        let sheet = if let Some(q) = sheet.strip_prefix('\'') {
            q.strip_suffix('\'')?.replace("''", "'")
        } else {
            sheet.to_string()
        };
        if sheet.is_empty() {
            return None;
        }
        let mut parts = range.split(':');
        let a = parse_cell_part(parts.next()?)?;
        let b = match parts.next() {
            Some(p) => parse_cell_part(p)?,
            None => a,
        };
        if parts.next().is_some() {
            return None;
        }
        let (row1, column1, row2, column2) = match (a, b) {
            ((Some(r1), Some(c1)), (Some(r2), Some(c2))) => (r1, c1, r2, c2),
            ((None, Some(c1)), (None, Some(c2))) => (1, c1, MAX_ROW, c2),
            ((Some(r1), None), (Some(r2), None)) => (r1, 1, r2, MAX_COLUMN),
            _ => return None,
        };
        if row1 < 1 || column1 < 1 || row2 > MAX_ROW || column2 > MAX_COLUMN {
            return None;
        }
        Some(ChartRef {
            sheet,
            row1: row1.min(row2),
            column1: column1.min(column2),
            row2: row1.max(row2),
            column2: column1.max(column2),
        })
    }

    /// The sheet name as it appears in a formula (quoted when needed).
    pub fn quoted_sheet(sheet: &str) -> String {
        let plain = !sheet.is_empty()
            && sheet.chars().all(|c| c.is_alphanumeric() || c == '_' || c == '.')
            && !sheet.chars().next().is_some_and(|c| c.is_ascii_digit())
            && !looks_like_reference(sheet);
        if plain {
            sheet.to_string()
        } else {
            format!("'{}'", sheet.replace('\'', "''"))
        }
    }

    /// `Sheet1!$A$1:$A$5` (a single cell is written `Sheet1!$A$1`).
    pub fn to_formula(&self) -> String {
        let cell = |r: i32, c: i32| format!("${}${}", number_to_column(c).unwrap_or_default(), r);
        let sheet = ChartRef::quoted_sheet(&self.sheet);
        if self.row1 == self.row2 && self.column1 == self.column2 {
            format!("{sheet}!{}", cell(self.row1, self.column1))
        } else {
            format!("{sheet}!{}:{}", cell(self.row1, self.column1), cell(self.row2, self.column2))
        }
    }

    /// Number of cells.
    pub fn len(&self) -> usize {
        ((self.row2 - self.row1 + 1) as usize) * ((self.column2 - self.column1 + 1) as usize)
    }

    /// True for an empty reference (never: kept for clippy).
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Cells in reading order (row by row).
    pub fn cells(&self) -> impl Iterator<Item = (i32, i32)> + '_ {
        (self.row1..=self.row2).flat_map(move |r| (self.column1..=self.column2).map(move |c| (r, c)))
    }
}

// ---------------------------------------------------------------------------
// Structural changes: insert/delete rows and columns, rename sheets
// ---------------------------------------------------------------------------

/// Moves the index range [a, b] for `count` lines inserted (count > 0) or
/// deleted (count < 0) at `at`. `None` if the whole range was deleted.
fn shift_span(a: i32, b: i32, at: i32, count: i32) -> Option<(i32, i32)> {
    if count >= 0 {
        let a = if a >= at { a + count } else { a };
        let b = if b >= at { b + count } else { b };
        Some((a, b))
    } else {
        let n = -count;
        let end = at + n - 1;
        let map_start = |x: i32| if x < at { x } else if x > end { x - n } else { at };
        let map_end = |x: i32| if x < at { x } else if x > end { x - n } else { at - 1 };
        let (a2, b2) = (map_start(a), map_end(b));
        if a2 > b2 {
            None
        } else {
            Some((a2, b2))
        }
    }
}

fn shift_formula(formula: &str, sheet_name: &str, rows: bool, at: i32, count: i32) -> String {
    let Some(mut r) = ChartRef::parse(formula) else {
        return formula.to_string();
    };
    if r.sheet != sheet_name {
        return formula.to_string();
    }
    // Whole rows / columns are not shifted along their full dimension.
    let shifted = if rows {
        if r.row1 == 1 && r.row2 == MAX_ROW {
            return formula.to_string();
        }
        shift_span(r.row1, r.row2, at, count).map(|(a, b)| {
            r.row1 = a;
            r.row2 = b.min(MAX_ROW);
        })
    } else {
        if r.column1 == 1 && r.column2 == MAX_COLUMN {
            return formula.to_string();
        }
        shift_span(r.column1, r.column2, at, count).map(|(a, b)| {
            r.column1 = a;
            r.column2 = b.min(MAX_COLUMN);
        })
    };
    match shifted {
        Some(()) => r.to_formula(),
        None => format!("{}!#REF!", ChartRef::quoted_sheet(sheet_name)),
    }
}

fn shift_point(row: &mut i32, offset: &mut i64, at: i32, count: i32) {
    if count >= 0 {
        if *row >= at {
            *row += count;
        }
    } else {
        let n = -count;
        let end = at + n - 1;
        if *row > end {
            *row -= n;
        } else if *row >= at {
            *row = at;
            *offset = 0;
        }
    }
}

/// Insert (count > 0) or delete (count < 0) of rows (`rows`) or columns at `at`
/// in sheet `sheet`: moves the charts on that sheet and shifts every reference
/// into it.
pub(crate) fn displace_charts(model: &mut Model, sheet: u32, rows: bool, at: i32, count: i32) {
    let Some(sheet_name) = model.workbook.worksheets.get(sheet as usize).map(|w| w.name.clone()) else {
        return;
    };
    for (index, worksheet) in model.workbook.worksheets.iter_mut().enumerate() {
        for chart in &mut worksheet.charts {
            for s in &mut chart.series {
                if let Some(f) = &s.name_ref {
                    s.name_ref = Some(shift_formula(f, &sheet_name, rows, at, count));
                }
                if let Some(f) = &s.categories_ref {
                    s.categories_ref = Some(shift_formula(f, &sheet_name, rows, at, count));
                }
                s.values_ref = shift_formula(&s.values_ref, &sheet_name, rows, at, count);
            }
            if index as u32 == sheet {
                let a = &mut chart.anchor;
                if rows {
                    shift_point(&mut a.from.row, &mut a.from.row_offset, at, count);
                    shift_point(&mut a.to.row, &mut a.to.row_offset, at, count);
                } else {
                    shift_point(&mut a.from.column, &mut a.from.column_offset, at, count);
                    shift_point(&mut a.to.column, &mut a.to.column_offset, at, count);
                }
                // A chart whose rows were all deleted keeps a minimal size.
                if (a.to.row, a.to.row_offset) <= (a.from.row, a.from.row_offset) {
                    a.to.row = a.from.row + 1;
                    a.to.row_offset = 0;
                }
                if (a.to.column, a.to.column_offset) <= (a.from.column, a.from.column_offset) {
                    a.to.column = a.from.column + 1;
                    a.to.column_offset = 0;
                }
            }
        }
    }
    // Pictures move with the cells too (see pictures.rs).
    if let Some(ws) = model.workbook.worksheets.get_mut(sheet as usize) {
        crate::pictures::displace_pictures(ws, rows, at, count);
    }
}

/// Sheet `old_name` was renamed to `new_name`: rename it in every reference.
pub(crate) fn rename_sheet_in_charts(model: &mut Model, old_name: &str, new_name: &str) {
    let rename = |f: &str| -> String {
        match ChartRef::parse(f) {
            Some(mut r) if r.sheet == old_name => {
                r.sheet = new_name.to_string();
                r.to_formula()
            }
            _ => f.to_string(),
        }
    };
    for worksheet in &mut model.workbook.worksheets {
        for chart in &mut worksheet.charts {
            for s in &mut chart.series {
                s.name_ref = s.name_ref.as_deref().map(rename);
                s.categories_ref = s.categories_ref.as_deref().map(rename);
                s.values_ref = rename(&s.values_ref);
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Anchor geometry: EMU <-> fractions of a cell
// ---------------------------------------------------------------------------

/// EMU per pixel at 96 dpi
pub const EMU_PER_PIXEL: i64 = 9525;
/// EMU per point
pub const EMU_PER_POINT: i64 = 12700;

/// Width of a column in EMU, as Excel computes it from the stored width (in
/// characters of the default font, 7 px each, 64 px for a default column).
pub fn column_width_emu(worksheet: &Worksheet, column: i32) -> i64 {
    for col in &worksheet.cols {
        if column >= col.min && column <= col.max {
            if col.hidden {
                return 0;
            }
            return ((col.width * 7.0 + 0.5).floor() as i64).max(0) * EMU_PER_PIXEL;
        }
    }
    64 * EMU_PER_PIXEL
}

/// Height of a row in EMU (15 pt for a default row).
pub fn row_height_emu(worksheet: &Worksheet, row: i32) -> i64 {
    for r in &worksheet.rows {
        if r.r == row {
            if r.hidden {
                return 0;
            }
            return (r.height * EMU_PER_POINT as f64).round() as i64;
        }
    }
    15 * EMU_PER_POINT
}

/// The point `cx` x `cy` EMU right of and below `from` (walking the column
/// widths and row heights of `worksheet`).
pub fn advance_anchor(worksheet: &Worksheet, from: AnchorPoint, cx: i64, cy: i64) -> AnchorPoint {
    let mut p = from;
    let mut left = cx + p.column_offset;
    while p.column < MAX_COLUMN {
        let w = column_width_emu(worksheet, p.column);
        if left < w || (w == 0 && left == 0) {
            break;
        }
        left -= w;
        p.column += 1;
    }
    p.column_offset = left.max(0);
    let mut left = cy + p.row_offset;
    while p.row < MAX_ROW {
        let h = row_height_emu(worksheet, p.row);
        if left < h || (h == 0 && left == 0) {
            break;
        }
        left -= h;
        p.row += 1;
    }
    p.row_offset = left.max(0);
    p
}

// ---------------------------------------------------------------------------
// Evaluated data
// ---------------------------------------------------------------------------

/// The evaluated values of one series, ready to draw.
#[derive(Serialize, Debug, PartialEq, Clone, Default)]
pub struct ChartSeriesData {
    /// Series name (evaluated reference, literal or "Series N")
    pub name: String,
    /// Colour "RRGGBB" if set in the chart
    #[serde(skip_serializing_if = "Option::is_none")]
    pub color: Option<String>,
    /// Category labels as formatted text (empty: use 1, 2, 3...)
    pub categories: Vec<String>,
    /// Numeric categories (X values of scatter charts); `None` where not a number
    pub category_numbers: Vec<Option<f64>>,
    /// Values, `None` for empty cells
    pub values: Vec<Option<f64>>,
    /// Number format of the first value cell
    pub format: String,
}

impl Model<'_> {
    /// The charts of a sheet.
    pub fn get_charts(&self, sheet: u32) -> Result<&[Chart], String> {
        Ok(&self.workbook.worksheet(sheet)?.charts)
    }

    fn ref_cells(&self, formula: &str, skip_hidden: bool) -> Option<(u32, Vec<(i32, i32)>)> {
        let r = ChartRef::parse(formula)?;
        let sheet = self.get_sheet_index_by_name(&r.sheet)?;
        let ws = self.workbook.worksheet(sheet).ok()?;
        // Whole columns/rows: stop at the used range.
        let dim = ws.dimension();
        let r = ChartRef {
            row2: r.row2.min(dim.max_row.max(r.row1)),
            column2: r.column2.min(dim.max_column.max(r.column1)),
            ..r
        };
        if r.len() > 100_000 {
            return None;
        }
        let cells = r
            .cells()
            .filter(|(row, column)| {
                !skip_hidden
                    || !(ws.is_row_hidden(*row).unwrap_or(false)
                        || ws.is_column_hidden(*column).unwrap_or(false))
            })
            .collect();
        Some((sheet, cells))
    }

    fn ref_numbers(&self, formula: &str) -> Vec<Option<f64>> {
        let Some((sheet, cells)) = self.ref_cells(formula, true) else {
            return vec![];
        };
        cells
            .into_iter()
            .map(|(row, column)| match self.get_cell_value_by_index(sheet, row, column) {
                Ok(CellValue::Number(n)) => Some(n),
                // Like Excel: text is plotted as zero, empty cells are gaps
                Ok(CellValue::String(_)) => Some(0.0),
                Ok(CellValue::Boolean(b)) => Some(if b { 1.0 } else { 0.0 }),
                _ => None,
            })
            .collect()
    }

    fn ref_texts(&self, formula: &str) -> Vec<String> {
        let Some((sheet, cells)) = self.ref_cells(formula, true) else {
            return vec![];
        };
        cells
            .into_iter()
            .map(|(row, column)| self.get_formatted_cell_value(sheet, row, column).unwrap_or_default())
            .collect()
    }

    fn ref_first_text(&self, formula: &str) -> Option<String> {
        let (sheet, cells) = self.ref_cells(formula, false)?;
        let texts: Vec<String> = cells
            .into_iter()
            .map(|(row, column)| self.get_formatted_cell_value(sheet, row, column).unwrap_or_default())
            .filter(|t| !t.is_empty())
            .collect();
        Some(texts.join(" "))
    }

    fn ref_format(&self, formula: &str) -> String {
        self.ref_cells(formula, false)
            .and_then(|(sheet, cells)| {
                let (row, column) = *cells.first()?;
                self.get_style_for_cell(sheet, row, column).ok().map(|s| s.num_fmt)
            })
            .unwrap_or_else(|| "general".to_string())
    }

    /// The name of a series as displayed (legend, tooltips).
    pub fn chart_series_name(&self, series: &ChartSeries, index: usize) -> String {
        if let Some(f) = &series.name_ref {
            if let Some(t) = self.ref_first_text(f) {
                if !t.is_empty() {
                    return t;
                }
            }
        }
        match &series.name {
            Some(n) if !n.is_empty() => n.clone(),
            _ => format!("Series{}", index + 1),
        }
    }

    /// Evaluates the series of chart `index` of `sheet`. Hidden rows and
    /// columns are left out, like Excel's default ("show data in hidden rows
    /// and columns" off).
    pub fn get_chart_data(&self, sheet: u32, index: usize) -> Result<Vec<ChartSeriesData>, String> {
        let chart = self
            .get_charts(sheet)?
            .get(index)
            .ok_or_else(|| format!("No chart {index} in sheet {sheet}"))?;
        Ok(self.chart_data(chart))
    }

    /// Evaluates the series of `chart`.
    pub fn chart_data(&self, chart: &Chart) -> Vec<ChartSeriesData> {
        chart
            .series
            .iter()
            .enumerate()
            .map(|(i, s)| {
                let (categories, category_numbers) = match &s.categories_ref {
                    Some(f) => (self.ref_texts(f), self.ref_numbers(f)),
                    None => (vec![], vec![]),
                };
                ChartSeriesData {
                    name: self.chart_series_name(s, i),
                    color: s.color.clone(),
                    categories,
                    category_numbers,
                    values: self.ref_numbers(&s.values_ref),
                    format: self.ref_format(&s.values_ref),
                }
            })
            .collect()
    }
}

// ---------------------------------------------------------------------------
// Undoable edits
// ---------------------------------------------------------------------------

impl UserModel<'_> {
    /// The charts of a sheet.
    pub fn get_charts(&self, sheet: u32) -> Result<&[Chart], String> {
        self.model.get_charts(sheet)
    }

    /// Evaluated series of a chart (see [`Model::get_chart_data`]).
    pub fn get_chart_data(&self, sheet: u32, index: usize) -> Result<Vec<ChartSeriesData>, String> {
        self.model.get_chart_data(sheet, index)
    }

    fn set_charts(&mut self, sheet: u32, new_value: Vec<Chart>) -> Result<(), String> {
        let worksheet = self.model.workbook.worksheet_mut(sheet)?;
        if worksheet.charts == new_value {
            return Ok(());
        }
        let old_value = std::mem::replace(&mut worksheet.charts, new_value.clone());
        self.push_diff_list(vec![Diff::SetCharts {
            sheet,
            old_value,
            new_value,
        }]);
        Ok(())
    }

    /// Adds a chart to the sheet and returns its index. One undo step.
    pub fn add_chart(&mut self, sheet: u32, mut chart: Chart) -> Result<usize, String> {
        let mut charts = self.model.get_charts(sheet)?.to_vec();
        if chart.name.is_empty() {
            let n = self
                .model
                .workbook
                .worksheets
                .iter()
                .map(|w| w.charts.len())
                .sum::<usize>();
            chart.name = format!("Chart {}", n + 1);
        }
        // In front of the other charts and pictures (see pictures.rs).
        chart.z = crate::pictures::next_z(self.model.workbook.worksheet(sheet)?);
        charts.push(chart);
        let index = charts.len() - 1;
        self.set_charts(sheet, charts)?;
        Ok(index)
    }

    /// Replaces chart `index`. One undo step (nothing if unchanged).
    pub fn update_chart(&mut self, sheet: u32, index: usize, chart: Chart) -> Result<(), String> {
        let mut charts = self.model.get_charts(sheet)?.to_vec();
        let slot = charts.get_mut(index).ok_or_else(|| format!("No chart {index}"))?;
        *slot = chart;
        self.set_charts(sheet, charts)
    }

    /// Deletes chart `index`. One undo step.
    pub fn delete_chart(&mut self, sheet: u32, index: usize) -> Result<(), String> {
        let mut charts = self.model.get_charts(sheet)?.to_vec();
        if index >= charts.len() {
            return Err(format!("No chart {index}"));
        }
        charts.remove(index);
        self.set_charts(sheet, charts)
    }

    /// Undo/redo of `Diff::SetCharts`.
    pub(crate) fn apply_charts_diff(&mut self, sheet: u32, value: &[Chart]) -> Result<(), String> {
        self.model.workbook.worksheet_mut(sheet)?.charts = value.to_vec();
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;

    #[test]
    fn parse_refs() {
        let r = ChartRef::parse("Sheet1!$B$2:$B$10").unwrap();
        assert_eq!((r.row1, r.column1, r.row2, r.column2), (2, 2, 10, 2));
        assert_eq!(r.to_formula(), "Sheet1!$B$2:$B$10");
        let r = ChartRef::parse("='My ''s'!A1").unwrap();
        assert_eq!(r.sheet, "My 's");
        assert_eq!(r.to_formula(), "'My ''s'!$A$1");
        assert!(ChartRef::parse("Sheet1!#REF!").is_none());
        assert!(ChartRef::parse("MyName").is_none());
        let r = ChartRef::parse("Data!$C:$C").unwrap();
        assert_eq!((r.row1, r.row2), (1, MAX_ROW));
        assert_eq!(ChartRef::quoted_sheet("A1"), "'A1'");
        assert_eq!(ChartRef::quoted_sheet("Foglio1"), "Foglio1");
    }

    #[test]
    fn shifting() {
        assert_eq!(shift_formula("S!$B$2:$B$10", "S", true, 5, 2), "S!$B$2:$B$12");
        assert_eq!(shift_formula("S!$B$2:$B$10", "S", true, 1, 1), "S!$B$3:$B$11");
        assert_eq!(shift_formula("S!$B$2:$B$10", "S", true, 4, -2), "S!$B$2:$B$8");
        assert_eq!(shift_formula("S!$B$2:$B$10", "S", true, 1, -20), "S!#REF!");
        assert_eq!(shift_formula("S!$B$2:$B$10", "T", true, 1, 3), "S!$B$2:$B$10");
        assert_eq!(shift_formula("S!$B$2:$D$10", "S", false, 3, -1), "S!$B$2:$C$10");
    }

    #[test]
    fn undo_redo_and_structure() {
        let mut model = UserModel::new_empty("model", "en", "UTC", "en").unwrap();
        for (i, v) in ["a", "b", "c"].iter().enumerate() {
            model.set_user_input(0, i as i32 + 2, 1, v).unwrap();
            model.set_user_input(0, i as i32 + 2, 2, &format!("{}", i + 1)).unwrap();
        }
        model.set_user_input(0, 1, 2, "Sales").unwrap();
        let chart = Chart {
            kind: ChartKind::Column,
            series: vec![ChartSeries {
                name_ref: Some("Sheet1!$B$1".into()),
                categories_ref: Some("Sheet1!$A$2:$A$4".into()),
                values_ref: "Sheet1!$B$2:$B$4".into(),
                ..Default::default()
            }],
            anchor: ChartAnchor {
                from: AnchorPoint { row: 2, column: 4, ..Default::default() },
                to: AnchorPoint { row: 16, column: 10, ..Default::default() },
            },
            ..Default::default()
        };
        model.add_chart(0, chart).unwrap();
        let data = model.get_chart_data(0, 0).unwrap();
        assert_eq!(data[0].name, "Sales");
        assert_eq!(data[0].categories, vec!["a", "b", "c"]);
        assert_eq!(data[0].values, vec![Some(1.0), Some(2.0), Some(3.0)]);
        assert_eq!(model.get_charts(0).unwrap()[0].name, "Chart 1");

        model.insert_rows(0, 1, 2).unwrap();
        let c = &model.get_charts(0).unwrap()[0];
        assert_eq!(c.series[0].values_ref, "Sheet1!$B$4:$B$6");
        assert_eq!(c.anchor.from.row, 4);
        assert_eq!(model.get_chart_data(0, 0).unwrap()[0].values, vec![Some(1.0), Some(2.0), Some(3.0)]);
        model.undo().unwrap();
        assert_eq!(model.get_charts(0).unwrap()[0].series[0].values_ref, "Sheet1!$B$2:$B$4");

        model.rename_sheet(0, "Data sheet").unwrap();
        assert_eq!(model.get_charts(0).unwrap()[0].series[0].values_ref, "'Data sheet'!$B$2:$B$4");
        model.undo().unwrap();

        model.delete_chart(0, 0).unwrap();
        assert!(model.get_charts(0).unwrap().is_empty());
        model.undo().unwrap();
        assert_eq!(model.get_charts(0).unwrap().len(), 1);
        model.redo().unwrap();
        assert!(model.get_charts(0).unwrap().is_empty());
    }
}
