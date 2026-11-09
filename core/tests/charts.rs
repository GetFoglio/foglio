//! Charts through the C ABI: add/update/delete, undo, and xlsx round trips
//! (our own files and a file written by openpyxl).

use std::ffi::{c_char, CStr, CString};
use std::path::{Path, PathBuf};
use std::ptr;

use foglio_core::charts::{
    foglio_chart_add, foglio_chart_count, foglio_chart_data_json, foglio_chart_delete, foglio_chart_set_anchor,
    foglio_chart_set_range, foglio_chart_update, foglio_charts_json,
};
use foglio_core::io::foglio_open_any;
use foglio_core::{foglio_free, foglio_new, foglio_save_xlsx, foglio_set_input, foglio_string_free, foglio_undo, foglio_redo, FoglioBook};
use serde_json::Value;

struct Book(*mut FoglioBook);
impl Drop for Book {
    fn drop(&mut self) {
        unsafe { foglio_free(self.0) };
    }
}

fn c(s: &str) -> CString {
    CString::new(s).unwrap()
}

fn take(s: *mut c_char) -> String {
    assert!(!s.is_null());
    let out = unsafe { CStr::from_ptr(s) }.to_str().unwrap().to_string();
    unsafe { foglio_string_free(s) };
    out
}

fn tmp(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("foglio-chart-tests-{}", std::process::id()));
    std::fs::create_dir_all(&d).unwrap();
    d.join(name)
}

fn fixture(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures").join(name)
}

impl Book {
    fn new() -> Book {
        Book(foglio_new())
    }
    fn open(p: &Path) -> Book {
        let mut err: *mut c_char = ptr::null_mut();
        let b = unsafe { foglio_open_any(c(p.to_str().unwrap()).as_ptr(), &mut err) };
        assert!(!b.is_null(), "open failed: {}", if err.is_null() { String::new() } else { take(err) });
        Book(b)
    }
    fn save(&self, p: &Path) {
        let _ = std::fs::remove_file(p);
        let mut err: *mut c_char = ptr::null_mut();
        let rc = unsafe { foglio_save_xlsx(self.0, c(p.to_str().unwrap()).as_ptr(), &mut err) };
        assert_eq!(rc, 0, "save failed: {}", if err.is_null() { String::new() } else { take(err) });
    }
    fn set(&self, sheet: u32, row: i32, col: i32, v: &str) {
        assert_eq!(unsafe { foglio_set_input(self.0, sheet, row, col, c(v).as_ptr()) }, 0);
    }
    fn charts(&self, sheet: u32) -> Vec<Value> {
        let v: Value = serde_json::from_str(&take(foglio_charts_json(self.0, sheet))).unwrap();
        v.as_array().unwrap().clone()
    }
    fn data(&self, sheet: u32, i: u32) -> Vec<Value> {
        let v: Value = serde_json::from_str(&take(foglio_chart_data_json(self.0, sheet, i))).unwrap();
        v.as_array().unwrap().clone()
    }
    fn add(&self, kind: &str, r0: i32, c0: i32, r1: i32, c1: i32) -> i32 {
        unsafe { foglio_chart_add(self.0, 0, c(kind).as_ptr(), r0, c0, r1, c1, 0, 0) }
    }
}

fn sales_book() -> Book {
    let b = Book::new();
    let rows = [["Month", "Sales", "Costs"], ["Jan", "10", "7"], ["Feb", "14", "9"], ["Mar", "9", "8"], ["Apr", "17", "10"]];
    for (r, row) in rows.iter().enumerate() {
        for (col, v) in row.iter().enumerate() {
            b.set(0, r as i32 + 1, col as i32 + 1, v);
        }
    }
    b
}

/// The parts of a chart that must survive a save.
fn essence(v: &Value) -> Value {
    let mut v = v.clone();
    let m = v.as_object_mut().unwrap();
    m.remove("index");
    // Series names read back come with their cached text.
    if let Some(Value::Array(series)) = m.get_mut("series") {
        for s in series {
            s.as_object_mut().unwrap().remove("name");
        }
    }
    v
}

const KINDS: [&str; 11] = [
    "column", "column_stacked", "bar", "bar_stacked", "line", "line_markers", "pie", "doughnut", "area", "area_stacked", "scatter",
];

#[test]
fn add_detects_series_and_places_right_of_data() {
    let b = sales_book();
    assert_eq!(b.add("column", 1, 1, 5, 3), 0);
    let charts = b.charts(0);
    assert_eq!(charts.len(), 1);
    let ch = &charts[0];
    assert_eq!(ch["kind"], "column");
    assert_eq!(ch["name"], "Chart 1");
    assert_eq!(ch["legend"], "bottom");
    assert_eq!(ch["data_range"], "A1:C5");
    assert_eq!(ch["series"][0]["name_ref"], "Sheet1!$B$1");
    assert_eq!(ch["series"][0]["categories_ref"], "Sheet1!$A$2:$A$5");
    assert_eq!(ch["series"][1]["values_ref"], "Sheet1!$C$2:$C$5");
    // Right of the data: column E (one empty column), first data row.
    assert_eq!(ch["anchor"]["from"]["col"], 5);
    assert_eq!(ch["anchor"]["from"]["row"], 1);
    let data = b.data(0, 0);
    assert_eq!(data[0]["name"], "Sales");
    assert_eq!(data[0]["categories"], serde_json::json!(["Jan", "Feb", "Mar", "Apr"]));
    assert_eq!(data[1]["values"], serde_json::json!([7.0, 9.0, 8.0, 10.0]));
    // A single series gets its name as title and no legend.
    assert_eq!(b.add("pie", 1, 1, 5, 2), 1);
    let pie = &b.charts(0)[1];
    assert_eq!(pie["title"], "Sales");
    assert_eq!(pie["legend"], "bottom");
    // Nothing to plot.
    assert_eq!(b.add("column", 20, 20, 22, 22), -1);
}

#[test]
fn update_anchor_range_delete_and_undo() {
    let b = sales_book();
    b.add("column", 1, 1, 5, 3);
    let patch = c(r#"{"kind":"line_markers","title":"Budget","legend":"right","value_axis_title":"EUR"}"#);
    assert_eq!(unsafe { foglio_chart_update(b.0, 0, 0, patch.as_ptr()) }, 0);
    let ch = &b.charts(0)[0];
    assert_eq!((ch["kind"].as_str(), ch["title"].as_str(), ch["legend"].as_str()), (Some("line_markers"), Some("Budget"), Some("right")));
    assert_eq!(ch["value_axis_title"], "EUR");
    // Remove the title.
    assert_eq!(unsafe { foglio_chart_update(b.0, 0, 0, c(r#"{"title":null}"#).as_ptr()) }, 0);
    assert!(b.charts(0)[0].get("title").is_none());
    // Move: corners with fractions.
    assert_eq!(foglio_chart_set_anchor(b.0, 0, 0, 3, 2, 0.5, 0.25, 12, 7, 0.0, 0.5), 0);
    let a = &b.charts(0)[0]["anchor"];
    assert_eq!((a["from"]["row"].as_i64(), a["from"]["col"].as_i64()), (Some(3), Some(2)));
    assert!((a["from"]["fy"].as_f64().unwrap() - 0.5).abs() < 1e-3);
    assert!((a["to"]["fx"].as_f64().unwrap() - 0.5).abs() < 1e-3);
    // New data range: one series only.
    assert_eq!(unsafe { foglio_chart_set_range(b.0, 0, 0, c("A1:B5").as_ptr()) }, 0);
    assert_eq!(b.charts(0)[0]["series"].as_array().unwrap().len(), 1);
    assert_eq!(unsafe { foglio_chart_set_range(b.0, 0, 0, c("nonsense").as_ptr()) }, -1);
    // Undo the range change, then the anchor.
    assert_eq!(foglio_undo(b.0), 0);
    assert_eq!(b.charts(0)[0]["series"].as_array().unwrap().len(), 2);
    // Delete + undo + redo.
    assert_eq!(foglio_chart_delete(b.0, 0, 0), 0);
    assert_eq!(foglio_chart_count(b.0, 0), 0);
    assert_eq!(foglio_undo(b.0), 0);
    assert_eq!(foglio_chart_count(b.0, 0), 1);
    assert_eq!(foglio_redo(b.0), 0);
    assert_eq!(foglio_chart_count(b.0, 0), 0);
}

#[test]
fn every_kind_round_trips_through_xlsx() {
    let b = sales_book();
    for (i, kind) in KINDS.iter().enumerate() {
        assert_eq!(b.add(kind, 1, 1, 5, 3), i as i32, "{kind}");
    }
    // Titles, axis titles, legend positions, colours, a sheet name that needs quoting.
    let patch = r#"{"title":"Q1 & Q2 <sales>","category_axis_title":"Month","value_axis_title":"EUR","legend":"top"}"#;
    assert_eq!(unsafe { foglio_chart_update(b.0, 0, 0, c(patch).as_ptr()) }, 0);
    let mut series = b.charts(0)[4]["series"].clone();
    series[0]["color"] = "C00000".into();
    let patch = serde_json::json!({ "series": series, "legend": "none" }).to_string();
    assert_eq!(unsafe { foglio_chart_update(b.0, 0, 4, c(&patch).as_ptr()) }, 0);
    let before = b.charts(0);

    let path = tmp("kinds.xlsx");
    b.save(&path);
    let back = Book::open(&path);
    let after = back.charts(0);
    assert_eq!(after.len(), KINDS.len());
    for (x, y) in before.iter().zip(&after) {
        assert_eq!(essence(x), essence(y));
    }
    assert_eq!(back.data(0, 0)[1]["values"], serde_json::json!([7.0, 9.0, 8.0, 10.0]));

    // Save again: identical charts (stable writer).
    let path2 = tmp("kinds2.xlsx");
    back.save(&path2);
    let again = Book::open(&path2).charts(0);
    for (x, y) in after.iter().zip(&again) {
        assert_eq!(essence(x), essence(y));
    }
}

#[test]
fn opens_openpyxl_charts() {
    let b = Book::open(&fixture("openpyxl_charts.xlsx"));
    let charts = b.charts(0);
    let kinds: Vec<&str> = charts.iter().map(|c| c["kind"].as_str().unwrap()).collect();
    // column, line, pie, scatter, stacked area, doughnut, stacked bar, radar (as line),
    // 3D column (as column), bubble (as scatter)
    assert_eq!(
        kinds,
        ["column", "line", "pie", "scatter", "area_stacked", "doughnut", "bar_stacked", "line", "column", "scatter"]
    );
    let col = &charts[0];
    assert_eq!(col["title"], "Sales");
    assert_eq!(col["category_axis_title"], "Month");
    assert_eq!(col["value_axis_title"], "EUR");
    assert_eq!(col["legend"], "right");
    assert_eq!(col["series"][1]["values_ref"], "'Data'!$C$2:$C$5");
    // oneCellAnchor at E2, 15 x 7.5 cm
    assert_eq!((col["anchor"]["from"]["row"].as_i64(), col["anchor"]["from"]["col"].as_i64()), (Some(2), Some(5)));
    assert!(col["anchor"]["to"]["col"].as_i64().unwrap() > 9);
    let data = b.data(0, 0);
    assert_eq!(data[0]["name"], "Sales");
    assert_eq!(data[0]["values"], serde_json::json!([10.0, 14.0, 9.0, 17.0]));
    // Scatter: X from column B.
    let sc = b.data(0, 3);
    assert_eq!(sc[0]["category_numbers"], serde_json::json!([10.0, 14.0, 9.0, 17.0]));
    assert!(b.charts(1).is_empty());

    // And it survives our own save.
    let path = tmp("openpyxl_resaved.xlsx");
    b.save(&path);
    let back = Book::open(&path).charts(0);
    assert_eq!(back.len(), charts.len());
    for (x, y) in charts.iter().zip(&back) {
        assert_eq!(x["kind"], y["kind"]);
        assert_eq!(essence(x)["series"], essence(y)["series"]);
    }
}

#[allow(improper_ctypes)] // FoglioBook is opaque, used through pointers only
extern "C" {
    fn foglio_comment_set(b: *mut FoglioBook, sheet: u32, row: i32, col: i32, text: *const c_char, author: *const c_char) -> i32;
    fn foglio_comment_get(b: *const FoglioBook, sheet: u32, row: i32, col: i32) -> *mut c_char;
}

/// Charts (xl/drawings/drawingN.xml, <drawing>) and notes (VML in xl/drawings, <legacyDrawing>)
/// share the drawings folder and the sheet rels: both must survive together.
#[test]
fn charts_and_comments_coexist() {
    let b = sales_book();
    b.add("column", 1, 1, 5, 3);
    assert_eq!(unsafe { foglio_comment_set(b.0, 0, 2, 2, c("Best month").as_ptr(), c("Ann").as_ptr()) }, 0);
    let path = tmp("charts_comments.xlsx");
    b.save(&path);
    let back = Book::open(&path);
    assert_eq!(back.charts(0).len(), 1);
    assert_eq!(take(unsafe { foglio_comment_get(back.0, 0, 2, 2) }), "Best month");
}
