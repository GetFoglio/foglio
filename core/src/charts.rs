//! Charts: C ABI over `ironcalc_base::charts` (see include/foglio_charts.h).
//!
//! Small payloads travel as JSON. Anchors are exchanged as a 1-based cell plus
//! a fraction (0..1) of that cell's width/height, so the UI never deals with
//! EMU; the engine stores EMU offsets (what the xlsx drawing part holds).

use std::ffi::c_char;
use std::ptr;

use ironcalc::base::cell::CellValue;
use ironcalc::base::charts::{
    advance_anchor, column_width_emu, row_height_emu, AnchorPoint, Chart, ChartAnchor, ChartKind, ChartRef, ChartSeries,
    LegendPosition,
};
use ironcalc::base::types::Worksheet;
use ironcalc::base::Model;
use serde_json::{json, Value};

use crate::{book, book_ref, cstr, guard, to_c, FoglioBook};

// ---------- anchor <-> fractions ----------

fn point_json(ws: &Worksheet, p: &AnchorPoint) -> Value {
    let w = column_width_emu(ws, p.column);
    let h = row_height_emu(ws, p.row);
    let fx = if w > 0 { (p.column_offset as f64 / w as f64).clamp(0.0, 1.0) } else { 0.0 };
    let fy = if h > 0 { (p.row_offset as f64 / h as f64).clamp(0.0, 1.0) } else { 0.0 };
    json!({ "row": p.row, "col": p.column, "fy": fy, "fx": fx })
}

fn point_from(ws: &Worksheet, row: i32, col: i32, fy: f64, fx: f64) -> AnchorPoint {
    let row = row.clamp(1, 1_048_576);
    let column = col.clamp(1, 16_384);
    let fy = if fy.is_finite() { fy.clamp(0.0, 1.0) } else { 0.0 };
    let fx = if fx.is_finite() { fx.clamp(0.0, 1.0) } else { 0.0 };
    AnchorPoint {
        row,
        column,
        row_offset: (row_height_emu(ws, row) as f64 * fy).round() as i64,
        column_offset: (column_width_emu(ws, column) as f64 * fx).round() as i64,
    }
}

// ---------- data range of a chart ----------

/// The rectangle covering every reference of the chart, if they all point to one sheet.
fn data_range(chart: &Chart) -> Option<ChartRef> {
    let mut out: Option<ChartRef> = None;
    let refs = chart.series.iter().flat_map(|s| {
        [Some(&s.values_ref), s.categories_ref.as_ref(), s.name_ref.as_ref()].into_iter().flatten()
    });
    for f in refs {
        let r = ChartRef::parse(f)?;
        out = Some(match out {
            None => r,
            Some(o) if o.sheet == r.sheet => ChartRef {
                sheet: o.sheet,
                row1: o.row1.min(r.row1),
                column1: o.column1.min(r.column1),
                row2: o.row2.max(r.row2),
                column2: o.column2.max(r.column2),
            },
            Some(_) => return None,
        });
    }
    out
}

/// "A1:C5" on the chart's own sheet, "Other!A1:C5" otherwise (no '$').
fn range_text(r: &ChartRef, own_sheet: &str) -> String {
    let f = r.to_formula().replace('$', "");
    if r.sheet == own_sheet {
        f.split_once('!').map(|(_, a)| a.to_string()).unwrap_or(f)
    } else {
        f
    }
}

fn chart_json(ws: &Worksheet, index: usize, c: &Chart) -> Value {
    let mut v = serde_json::to_value(c).unwrap_or(Value::Null);
    if let Value::Object(m) = &mut v {
        m.insert("index".into(), json!(index));
        m.insert(
            "anchor".into(),
            json!({ "from": point_json(ws, &c.anchor.from), "to": point_json(ws, &c.anchor.to) }),
        );
        m.insert("data_range".into(), json!(data_range(c).map(|r| range_text(&r, &ws.name))));
    }
    v
}

// ---------- series detection (like Excel's Insert ▸ Chart) ----------

struct Grid<'m, 'a> {
    model: &'m Model<'a>,
    sheet: u32,
}

impl Grid<'_, '_> {
    fn value(&self, r: i32, c: i32) -> CellValue {
        self.model.get_cell_value_by_index(self.sheet, r, c).unwrap_or(CellValue::None)
    }
    fn is_num(&self, r: i32, c: i32) -> bool {
        matches!(self.value(r, c), CellValue::Number(_))
    }
    fn is_empty(&self, r: i32, c: i32) -> bool {
        match self.value(r, c) {
            CellValue::None => true,
            CellValue::String(s) => s.is_empty(),
            _ => false,
        }
    }
    fn is_date(&self, r: i32, c: i32) -> bool {
        self.is_num(r, c)
            && self
                .model
                .get_style_for_cell(self.sheet, r, c)
                .map(|s| {
                    let f = s.num_fmt.to_lowercase();
                    !f.contains("general") && (f.contains('d') || f.contains('y') || f.contains("mmm"))
                })
                .unwrap_or(false)
    }
}

/// Series for the data in rows r0..=r1, columns c0..=c1 (1-based), Excel style:
/// a first row without numbers holds the series names, a first column without
/// numbers (or with dates) the categories; series run along the longer side.
pub(crate) fn detect_series(model: &Model, sheet: u32, kind: ChartKind, r0: i32, c0: i32, r1: i32, c1: i32) -> Vec<ChartSeries> {
    let g = Grid { model, sheet };
    let Ok(ws) = model.workbook.worksheet(sheet) else { return vec![] };
    let sheet_name = ws.name.clone();
    let (r0, r1) = (r0.min(r1), r0.max(r1));
    let (c0, c1) = (c0.min(c1), c0.max(c1));
    // Trim empty trailing rows/columns of whole-row/column selections.
    let dim = ws.dimension();
    let (r1, c1) = (r1.min(dim.max_row.max(r0)), c1.min(dim.max_column.max(c0)));
    let (rows, cols) = (r1 - r0 + 1, c1 - c0 + 1);
    if (rows as i64) * (cols as i64) > 1_000_000 || !(r0..=r1).any(|r| (c0..=c1).any(|c| g.is_num(r, c))) {
        return vec![];
    }
    let corner_empty = g.is_empty(r0, c0);
    let header_row = rows > 1 && (c0..=c1).all(|c| !g.is_num(r0, c) || (c == c0 && g.is_date(r0, c)))
        && (c0..=c1).any(|c| !g.is_empty(r0, c));
    let first_data_row = if header_row { r0 + 1 } else { r0 };
    let header_col = cols > 1
        && ((corner_empty && header_row)
            || (first_data_row..=r1).all(|r| !g.is_num(r, c0) || g.is_date(r, c0)))
        && (first_data_row..=r1).any(|r| !g.is_empty(r, c0));
    let (dr0, dc0) = (if header_row { r0 + 1 } else { r0 }, if header_col { c0 + 1 } else { c0 });
    if dr0 > r1 || dc0 > c1 {
        return vec![];
    }
    let rf = |ra: i32, ca: i32, rb: i32, cb: i32| {
        ChartRef { sheet: sheet_name.clone(), row1: ra, column1: ca, row2: rb, column2: cb }.to_formula()
    };
    let (data_rows, data_cols) = (r1 - dr0 + 1, c1 - dc0 + 1);
    let by_columns = data_rows >= data_cols;
    let mut out = Vec::new();
    if kind == ChartKind::Scatter {
        // X values: the header column if any, else the first data column/row.
        if by_columns {
            let (x, first_y) = if header_col { (Some(rf(dr0, c0, r1, c0)), dc0) } else if data_cols > 1 { (Some(rf(dr0, dc0, r1, dc0)), dc0 + 1) } else { (None, dc0) };
            for c in first_y..=c1 {
                out.push(ChartSeries {
                    name_ref: header_row.then(|| rf(r0, c, r0, c)),
                    categories_ref: x.clone(),
                    values_ref: rf(dr0, c, r1, c),
                    ..Default::default()
                });
            }
        } else {
            let (x, first_y) = if header_row { (Some(rf(r0, dc0, r0, c1)), dr0) } else if data_rows > 1 { (Some(rf(dr0, dc0, dr0, c1)), dr0 + 1) } else { (None, dr0) };
            for r in first_y..=r1 {
                out.push(ChartSeries {
                    name_ref: header_col.then(|| rf(r, c0, r, c0)),
                    categories_ref: x.clone(),
                    values_ref: rf(r, dc0, r, c1),
                    ..Default::default()
                });
            }
        }
        return out;
    }
    if by_columns {
        for c in dc0..=c1 {
            out.push(ChartSeries {
                name_ref: header_row.then(|| rf(r0, c, r0, c)),
                categories_ref: header_col.then(|| rf(dr0, c0, r1, c0)),
                values_ref: rf(dr0, c, r1, c),
                ..Default::default()
            });
        }
    } else {
        for r in dr0..=r1 {
            out.push(ChartSeries {
                name_ref: header_col.then(|| rf(r, c0, r, c0)),
                categories_ref: header_row.then(|| rf(r0, dc0, r0, c1)),
                values_ref: rf(r, dc0, r, c1),
                ..Default::default()
            });
        }
    }
    if kind == ChartKind::Pie {
        out.truncate(1);
    }
    out
}

/// Excel's default chart size: 5 x 3 inches.
const DEFAULT_CX: i64 = 4_572_000;
const DEFAULT_CY: i64 = 2_743_200;

fn parse_range_text(text: &str, sheet_name: &str) -> Option<ChartRef> {
    let t = text.trim().trim_start_matches('=');
    if t.contains('!') {
        ChartRef::parse(t)
    } else {
        ChartRef::parse(&format!("{}!{t}", ChartRef::quoted_sheet(sheet_name)))
    }
}

// ---------- C ABI ----------

/// JSON array of the charts of `sheet` (see foglio_charts.h).
#[no_mangle]
pub extern "C" fn foglio_charts_json(b: *const FoglioBook, sheet: u32) -> *mut c_char {
    let Some(b) = book_ref(b) else { return ptr::null_mut() };
    guard(ptr::null_mut(), || {
        let model = b.model.get_model();
        let Ok(ws) = model.workbook.worksheet(sheet) else { return ptr::null_mut() };
        let list: Vec<Value> = ws.charts.iter().enumerate().map(|(i, c)| chart_json(ws, i, c)).collect();
        to_c(Value::Array(list).to_string())
    })
}

/// Number of charts on `sheet`.
#[no_mangle]
pub extern "C" fn foglio_chart_count(b: *const FoglioBook, sheet: u32) -> i32 {
    let Some(b) = book_ref(b) else { return -1 };
    guard(-1, || b.model.get_charts(sheet).map(|c| c.len() as i32).unwrap_or(-1))
}

/// Adds a chart of type `kind` for the data in r0..r1 x c0..c1 (1-based). It is
/// placed with its top-left corner at (at_row, at_col) or, if at_row <= 0, one
/// column right of the data, aligned with its first row. Returns the index or -1.
#[no_mangle]
pub unsafe extern "C" fn foglio_chart_add(
    b: *mut FoglioBook, sheet: u32, kind: *const c_char, r0: i32, c0: i32, r1: i32, c1: i32, at_row: i32, at_col: i32,
) -> i32 {
    let Some(b) = book(b) else { return -1 };
    let kind = cstr(kind).and_then(ChartKind::from_name).unwrap_or_default();
    guard(-1, || {
        let model = b.model.get_model();
        let series = detect_series(model, sheet, kind, r0, c0, r1, c1);
        if series.is_empty() {
            return -1;
        }
        let Ok(ws) = model.workbook.worksheet(sheet) else { return -1 };
        let from = if at_row > 0 && at_col > 0 {
            point_from(ws, at_row, at_col, 0.0, 0.0)
        } else {
            point_from(ws, r0.min(r1), c0.max(c1) + 2, 0.0, 0.0)
        };
        let to = advance_anchor(ws, from, DEFAULT_CX, DEFAULT_CY);
        let title = if series.len() == 1 { Some(model.chart_series_name(&series[0], 0)) } else { None };
        let legend = if series.len() == 1 && !matches!(kind, ChartKind::Pie | ChartKind::Doughnut) {
            LegendPosition::None
        } else {
            LegendPosition::Bottom
        };
        let chart = Chart { name: String::new(), kind, title, series, legend, anchor: ChartAnchor { from, to }, ..Default::default() };
        b.model.add_chart(sheet, chart).map(|i| i as i32).unwrap_or(-1)
    })
}

/// Updates chart `index` from a JSON object with any of: "kind", "title" (null
/// removes it), "legend", "category_axis_title", "value_axis_title", "name",
/// "series" (full list). Other fields are ignored. One undo step.
#[no_mangle]
pub unsafe extern "C" fn foglio_chart_update(b: *mut FoglioBook, sheet: u32, index: u32, patch: *const c_char) -> i32 {
    let (Some(b), Some(patch)) = (book(b), cstr(patch)) else { return -1 };
    guard(-1, || {
        let Ok(Value::Object(patch)) = serde_json::from_str::<Value>(patch) else { return -1 };
        let Some(chart) = b.model.get_charts(sheet).ok().and_then(|c| c.get(index as usize)).cloned() else { return -1 };
        let mut v = serde_json::to_value(&chart).unwrap_or(Value::Null);
        let Value::Object(m) = &mut v else { return -1 };
        for key in ["kind", "title", "legend", "category_axis_title", "value_axis_title", "name", "series"] {
            if let Some(val) = patch.get(key) {
                if val.is_null() || val.as_str() == Some("") && key != "name" {
                    m.remove(key);
                } else {
                    m.insert(key.to_string(), val.clone());
                }
            }
        }
        let Ok(mut updated) = serde_json::from_value::<Chart>(v) else { return -1 };
        if updated.name.is_empty() {
            updated.name = chart.name.clone();
        }
        // A pie shows one series.
        if updated.kind == ChartKind::Pie && updated.series.len() > 1 && patch.contains_key("kind") {
            updated.series.truncate(1);
        }
        if b.model.update_chart(sheet, index as usize, updated).is_ok() { 0 } else { -1 }
    })
}

/// Moves/resizes chart `index`: corners as 1-based cells plus fractions (0..1) of
/// the cell height (fy) and width (fx). One undo step.
#[no_mangle]
pub extern "C" fn foglio_chart_set_anchor(
    b: *mut FoglioBook, sheet: u32, index: u32, row0: i32, col0: i32, fy0: f64, fx0: f64, row1: i32, col1: i32, fy1: f64,
    fx1: f64,
) -> i32 {
    let Some(b) = book(b) else { return -1 };
    guard(-1, || {
        let model = b.model.get_model();
        let Ok(ws) = model.workbook.worksheet(sheet) else { return -1 };
        let Some(mut chart) = ws.charts.get(index as usize).cloned() else { return -1 };
        let from = point_from(ws, row0, col0, fy0, fx0);
        let mut to = point_from(ws, row1, col1, fy1, fx1);
        if (to.row, to.row_offset) <= (from.row, from.row_offset) {
            to = AnchorPoint { row: from.row + 1, row_offset: 0, ..to };
        }
        if (to.column, to.column_offset) <= (from.column, from.column_offset) {
            to = AnchorPoint { column: from.column + 1, column_offset: 0, ..to };
        }
        chart.anchor = ChartAnchor { from, to };
        if b.model.update_chart(sheet, index as usize, chart).is_ok() { 0 } else { -1 }
    })
}

/// Replaces the series of chart `index` with those detected in `range`
/// ("A1:C10" on this sheet, or "Sheet2!A1:C10"). Returns 0, or -1 if the range
/// is invalid or holds no data. One undo step.
#[no_mangle]
pub unsafe extern "C" fn foglio_chart_set_range(b: *mut FoglioBook, sheet: u32, index: u32, range: *const c_char) -> i32 {
    let (Some(b), Some(range)) = (book(b), cstr(range)) else { return -1 };
    guard(-1, || {
        let model = b.model.get_model();
        let Ok(ws) = model.workbook.worksheet(sheet) else { return -1 };
        let Some(mut chart) = ws.charts.get(index as usize).cloned() else { return -1 };
        let Some(r) = parse_range_text(range, &ws.name) else { return -1 };
        let Some(data_sheet) = model.workbook.worksheets.iter().position(|w| w.name == r.sheet) else { return -1 };
        let series = detect_series(model, data_sheet as u32, chart.kind, r.row1, r.column1, r.row2, r.column2);
        if series.is_empty() {
            return -1;
        }
        // Keep the colours the user chose, series by series.
        let colors: Vec<Option<String>> = chart.series.iter().map(|s| s.color.clone()).collect();
        chart.series = series
            .into_iter()
            .enumerate()
            .map(|(i, s)| ChartSeries { color: colors.get(i).cloned().flatten(), ..s })
            .collect();
        if b.model.update_chart(sheet, index as usize, chart).is_ok() { 0 } else { -1 }
    })
}

/// Deletes chart `index`. One undo step.
#[no_mangle]
pub extern "C" fn foglio_chart_delete(b: *mut FoglioBook, sheet: u32, index: u32) -> i32 {
    let Some(b) = book(b) else { return -1 };
    guard(-1, || if b.model.delete_chart(sheet, index as usize).is_ok() { 0 } else { -1 })
}

/// Evaluated series of chart `index` as a JSON array of
/// {"name", "color"?, "categories": [text], "category_numbers": [number|null],
///  "values": [number|null], "format"}.
#[no_mangle]
pub extern "C" fn foglio_chart_data_json(b: *const FoglioBook, sheet: u32, index: u32) -> *mut c_char {
    let Some(b) = book_ref(b) else { return ptr::null_mut() };
    guard(ptr::null_mut(), || match b.model.get_chart_data(sheet, index as usize) {
        Ok(data) => to_c(serde_json::to_string(&data).unwrap_or_else(|_| "[]".into())),
        Err(_) => ptr::null_mut(),
    })
}


#[cfg(test)]
mod tests {
    use super::*;
    use ironcalc::base::UserModel;

    fn model_with(rows: &[&[&str]]) -> UserModel<'static> {
        let mut m = UserModel::new_empty("t", "en", "UTC", "en").unwrap();
        for (r, row) in rows.iter().enumerate() {
            for (c, v) in row.iter().enumerate() {
                if !v.is_empty() {
                    m.set_user_input(0, r as i32 + 1, c as i32 + 1, v).unwrap();
                }
            }
        }
        m
    }

    #[test]
    fn detects_headers_and_orientation() {
        let m = model_with(&[&["", "Sales", "Costs"], &["Jan", "1", "2"], &["Feb", "3", "4"], &["Mar", "5", "6"]]);
        let s = detect_series(m.get_model(), 0, ChartKind::Column, 1, 1, 4, 3);
        assert_eq!(s.len(), 2);
        assert_eq!(s[0].name_ref.as_deref(), Some("Sheet1!$B$1"));
        assert_eq!(s[0].categories_ref.as_deref(), Some("Sheet1!$A$2:$A$4"));
        assert_eq!(s[1].values_ref, "Sheet1!$C$2:$C$4");
        // Wide data: series in rows.
        let m = model_with(&[&["", "Q1", "Q2", "Q3", "Q4"], &["North", "1", "2", "3", "4"], &["South", "5", "6", "7", "8"]]);
        let s = detect_series(m.get_model(), 0, ChartKind::Line, 1, 1, 3, 5);
        assert_eq!(s.len(), 2);
        assert_eq!(s[1].name_ref.as_deref(), Some("Sheet1!$A$3"));
        assert_eq!(s[1].categories_ref.as_deref(), Some("Sheet1!$B$1:$E$1"));
        assert_eq!(s[1].values_ref, "Sheet1!$B$3:$E$3");
        // Numbers only: no headers.
        let m = model_with(&[&["1", "2"], &["3", "4"], &["5", "6"]]);
        let s = detect_series(m.get_model(), 0, ChartKind::Column, 1, 1, 3, 2);
        assert_eq!(s.len(), 2);
        assert!(s[0].name_ref.is_none() && s[0].categories_ref.is_none());
        // Scatter: first column is X.
        let s = detect_series(m.get_model(), 0, ChartKind::Scatter, 1, 1, 3, 2);
        assert_eq!(s.len(), 1);
        assert_eq!(s[0].categories_ref.as_deref(), Some("Sheet1!$A$1:$A$3"));
        assert_eq!(s[0].values_ref, "Sheet1!$B$1:$B$3");
    }
}
