//! Integration tests for the feature C ABI (src/features.rs, include/foglio_features.h):
//! comments, data validation, font name, tab colour, hyperlinks, summarize — including
//! xlsx round trips and a workbook made by openpyxl (tests/fixtures/features_openpyxl.xlsx,
//! see make_features_fixture.py).
#![allow(improper_ctypes)] // FoglioBook is opaque, used through pointers only

use std::ffi::{c_char, CStr, CString};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::ptr;
use std::sync::Mutex;

use foglio_core::io::foglio_open_any;
use foglio_core::{
    foglio_can_undo, foglio_free, foglio_get_formatted, foglio_get_input, foglio_new, foglio_redo, foglio_save_xlsx,
    foglio_set_input, foglio_set_locale, foglio_set_style, foglio_sheet_count, foglio_sheet_name, foglio_string_free,
    foglio_undo, FoglioBook,
};

// The feature functions are #[no_mangle] C functions (declared in foglio_features.h).
extern "C" {
    fn foglio_comment_get(b: *const FoglioBook, sheet: u32, row: i32, col: i32) -> *mut c_char;
    fn foglio_comment_author(b: *const FoglioBook, sheet: u32, row: i32, col: i32) -> *mut c_char;
    fn foglio_comment_set(b: *mut FoglioBook, sheet: u32, row: i32, col: i32, text: *const c_char, author: *const c_char) -> i32;
    fn foglio_comment_delete(b: *mut FoglioBook, sheet: u32, row: i32, col: i32) -> i32;
    fn foglio_comment_cells(b: *const FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32, out_n: *mut usize) -> *mut i32;
    fn foglio_comments_json(b: *const FoglioBook, sheet: u32) -> *mut c_char;
    fn foglio_validation_set(
        b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32, json: *const c_char, err_out: *mut *mut c_char,
    ) -> i32;
    fn foglio_validation_clear(b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32) -> i32;
    fn foglio_validation_get(b: *const FoglioBook, sheet: u32, row: i32, col: i32) -> *mut c_char;
    fn foglio_validation_list(b: *mut FoglioBook, sheet: u32, row: i32, col: i32) -> *mut c_char;
    fn foglio_validation_check(
        b: *mut FoglioBook, sheet: u32, row: i32, col: i32, input: *const c_char, title: *mut *mut c_char,
        message: *mut *mut c_char,
    ) -> i32;
    fn foglio_font_name_at(b: *mut FoglioBook, sheet: u32, row: i32, col: i32) -> *mut c_char;
    fn foglio_sheet_color(b: *const FoglioBook, sheet: u32) -> u32;
    fn foglio_set_sheet_color(b: *mut FoglioBook, sheet: u32, rgb: u32) -> i32;
    fn foglio_link_get(b: *const FoglioBook, sheet: u32, row: i32, col: i32) -> *mut c_char;
    fn foglio_link_set(
        b: *mut FoglioBook, sheet: u32, row: i32, col: i32, address: *const c_char, display: *const c_char,
        tooltip: *const c_char,
    ) -> i32;
    fn foglio_link_remove(b: *mut FoglioBook, sheet: u32, row: i32, col: i32) -> i32;
    fn foglio_summarize(
        b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32, group_col: i32, value_col: i32, agg: i32,
        name: *const c_char, err_out: *mut *mut c_char,
    ) -> i32;
    // foglio_ui.h
    fn foglio_structure(b: *mut FoglioBook, sheet: u32, op: i32, index: i32, count: i32) -> i32;
    fn foglio_ints_free(p: *mut i32, len: usize);
    fn foglio_sheet_op(b: *mut FoglioBook, sheet: u32, op: i32, arg: u32, name: *const c_char) -> i32;
}

const NO_COLOR: u32 = 0xFFFF_FFFF;

// ---------- helpers ----------

/// The locale is process-wide: books are created under this lock.
static LOCALE: Mutex<()> = Mutex::new(());

fn c(s: &str) -> CString {
    CString::new(s).unwrap()
}

fn take_opt(s: *mut c_char) -> Option<String> {
    if s.is_null() {
        return None;
    }
    let out = unsafe { CStr::from_ptr(s) }.to_str().unwrap().to_string();
    unsafe { foglio_string_free(s) };
    Some(out)
}

fn take(s: *mut c_char) -> String {
    take_opt(s).expect("unexpected NULL")
}

fn json(s: *mut c_char) -> serde_json::Value {
    serde_json::from_str(&take(s)).unwrap()
}

fn tmp(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("foglio-features-tests-{}", std::process::id()));
    std::fs::create_dir_all(&d).unwrap();
    d.join(name)
}

fn fixture(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures").join(name)
}

struct Book(*mut FoglioBook);

impl Drop for Book {
    fn drop(&mut self) {
        unsafe { foglio_free(self.0) };
    }
}

impl Book {
    fn new(locale: &str, language: &str) -> Book {
        let _g = LOCALE.lock().unwrap_or_else(|e| e.into_inner());
        unsafe { foglio_set_locale(c(locale).as_ptr(), c(language).as_ptr(), c("UTC").as_ptr()) };
        let b = foglio_new();
        unsafe { foglio_set_locale(c("en").as_ptr(), c("en").as_ptr(), c("UTC").as_ptr()) };
        assert!(!b.is_null());
        Book(b)
    }
    fn open(path: &Path, locale: &str, language: &str) -> Book {
        let _g = LOCALE.lock().unwrap_or_else(|e| e.into_inner());
        unsafe { foglio_set_locale(c(locale).as_ptr(), c(language).as_ptr(), c("UTC").as_ptr()) };
        let mut err = ptr::null_mut();
        let b = unsafe { foglio_open_any(c(path.to_str().unwrap()).as_ptr(), &mut err) };
        unsafe { foglio_set_locale(c("en").as_ptr(), c("en").as_ptr(), c("UTC").as_ptr()) };
        assert!(!b.is_null(), "open {}: {:?}", path.display(), take_opt(err));
        Book(b)
    }
    fn save(&self, name: &str) -> PathBuf {
        let path = tmp(name);
        let mut err = ptr::null_mut();
        let r = unsafe { foglio_save_xlsx(self.0, c(path.to_str().unwrap()).as_ptr(), &mut err) };
        assert_eq!(r, 0, "save: {:?}", take_opt(err));
        path
    }
    /// Save, then open the file again with the same locale
    fn round_trip(&self, name: &str, locale: &str, language: &str) -> Book {
        let path = self.save(name);
        Book::open(&path, locale, language)
    }
    fn set(&self, sheet: u32, row: i32, col: i32, v: &str) {
        assert_eq!(unsafe { foglio_set_input(self.0, sheet, row, col, c(v).as_ptr()) }, 0, "set {v}");
    }
    fn input(&self, sheet: u32, row: i32, col: i32) -> String {
        take(foglio_get_input(self.0, sheet, row, col))
    }
    fn shown(&self, sheet: u32, row: i32, col: i32) -> String {
        take(foglio_get_formatted(self.0, sheet, row, col))
    }
    fn comment(&self, sheet: u32, row: i32, col: i32) -> Option<String> {
        take_opt(unsafe { foglio_comment_get(self.0, sheet, row, col) })
    }
    fn author(&self, sheet: u32, row: i32, col: i32) -> Option<String> {
        take_opt(unsafe { foglio_comment_author(self.0, sheet, row, col) })
    }
    fn set_comment(&self, sheet: u32, row: i32, col: i32, text: &str, author: &str) {
        assert_eq!(unsafe { foglio_comment_set(self.0, sheet, row, col, c(text).as_ptr(), c(author).as_ptr()) }, 0);
    }
    fn comment_cells(&self, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32) -> Vec<(i32, i32)> {
        let mut n = 0usize;
        let p = unsafe { foglio_comment_cells(self.0, sheet, r0, c0, r1, c1, &mut n) };
        let v = unsafe { std::slice::from_raw_parts(p, 2 * n) }.chunks(2).map(|x| (x[0], x[1])).collect();
        unsafe { foglio_ints_free(p, 2 * n) };
        v
    }
    fn set_validation(&self, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32, rule: serde_json::Value) -> Result<(), String> {
        let mut err = ptr::null_mut();
        let r = unsafe { foglio_validation_set(self.0, sheet, r0, c0, r1, c1, c(&rule.to_string()).as_ptr(), &mut err) };
        if r == 0 {
            Ok(())
        } else {
            Err(take_opt(err).unwrap_or_default())
        }
    }
    fn validation(&self, sheet: u32, row: i32, col: i32) -> Option<serde_json::Value> {
        take_opt(unsafe { foglio_validation_get(self.0, sheet, row, col) }).map(|s| serde_json::from_str(&s).unwrap())
    }
    fn list(&self, sheet: u32, row: i32, col: i32) -> Option<Vec<String>> {
        take_opt(unsafe { foglio_validation_list(self.0, sheet, row, col) }).map(|s| serde_json::from_str(&s).unwrap())
    }
    /// (code, title, message)
    fn check(&self, sheet: u32, row: i32, col: i32, input: &str) -> (i32, String, String) {
        let (mut t, mut m) = (ptr::null_mut(), ptr::null_mut());
        let code = unsafe { foglio_validation_check(self.0, sheet, row, col, c(input).as_ptr(), &mut t, &mut m) };
        (code, take_opt(t).unwrap_or_default(), take_opt(m).unwrap_or_default())
    }
    fn link(&self, sheet: u32, row: i32, col: i32) -> Option<serde_json::Value> {
        take_opt(unsafe { foglio_link_get(self.0, sheet, row, col) }).map(|s| serde_json::from_str(&s).unwrap())
    }
    fn undo(&self) {
        assert_eq!(foglio_undo(self.0), 0);
    }
    fn redo(&self) {
        assert_eq!(foglio_redo(self.0), 0);
    }
}

/// A part of an xlsx file (via unzip), None if missing.
fn part(path: &Path, name: &str) -> Option<String> {
    // unzip reads the name as a pattern: escape '[' and ']'
    let name = name.replace('[', "\\[").replace(']', "\\]");
    let out = Command::new("unzip").arg("-p").arg(path).arg(name).output().ok()?;
    if !out.status.success() || out.stdout.is_empty() {
        return None;
    }
    Some(String::from_utf8(out.stdout).unwrap())
}

/// Runs a check with openpyxl if the venv exists (see the repository notes); returns its stdout.
fn openpyxl(script: &str, path: &Path) -> Option<String> {
    let python = Path::new("/private/tmp/foglio-venv/bin/python");
    if !python.exists() {
        eprintln!("openpyxl venv not found: skipping the openpyxl check");
        return None;
    }
    let out = Command::new(python).arg("-c").arg(script).arg(path).output().unwrap();
    assert!(out.status.success(), "openpyxl failed: {}", String::from_utf8_lossy(&out.stderr));
    Some(String::from_utf8(out.stdout).unwrap())
}

// ---------- comments ----------

#[test]
fn comments_set_get_undo() {
    let b = Book::new("en", "en");
    assert_eq!(b.comment(0, 2, 3), None);
    b.set_comment(0, 2, 3, "Check this\nsecond line", "Ada");
    b.set_comment(0, 5, 1, "Another", "");
    assert_eq!(b.comment(0, 2, 3).as_deref(), Some("Check this\nsecond line"));
    assert_eq!(b.author(0, 2, 3).as_deref(), Some("Ada"));
    assert_eq!(b.author(0, 5, 1).as_deref(), Some(""));
    assert_eq!(b.comment_cells(0, 1, 1, 10, 10), vec![(2, 3), (5, 1)]);
    assert_eq!(b.comment_cells(0, 3, 1, 10, 10), vec![(5, 1)]);
    let all = json(unsafe { foglio_comments_json(b.0, 0) });
    assert_eq!(all[0]["row"], 2);
    assert_eq!(all[0]["col"], 3);
    assert_eq!(all[1]["text"], "Another");

    // replace, undo, redo
    b.set_comment(0, 2, 3, "Replaced", "Bob");
    assert_eq!(b.comment(0, 2, 3).as_deref(), Some("Replaced"));
    b.undo();
    assert_eq!(b.comment(0, 2, 3).as_deref(), Some("Check this\nsecond line"));
    b.redo();
    assert_eq!(b.author(0, 2, 3).as_deref(), Some("Bob"));

    // delete (also via empty text)
    assert_eq!(unsafe { foglio_comment_delete(b.0, 0, 2, 3) }, 0);
    assert_eq!(b.comment(0, 2, 3), None);
    b.undo();
    assert_eq!(b.comment(0, 2, 3).as_deref(), Some("Replaced"));
    assert_eq!(unsafe { foglio_comment_set(b.0, 0, 5, 1, ptr::null(), ptr::null()) }, 0);
    assert_eq!(b.comment(0, 5, 1), None);
    // deleting nothing is fine
    assert_eq!(unsafe { foglio_comment_delete(b.0, 0, 9, 9) }, 0);
}

#[test]
fn comments_follow_rows_and_columns() {
    let b = Book::new("en", "en");
    b.set_comment(0, 3, 2, "B3", "");
    b.set_comment(0, 6, 4, "D6", "");
    // insert 2 rows at 2: B3 -> B5, D6 -> D8
    assert_eq!(unsafe { foglio_structure(b.0, 0, 0, 2, 2) }, 0);
    assert_eq!(b.comment_cells(0, 1, 1, 20, 20), vec![(5, 2), (8, 4)]);
    // insert a column at A: B5 -> C5, D8 -> E8
    assert_eq!(unsafe { foglio_structure(b.0, 0, 2, 1, 1) }, 0);
    assert_eq!(b.comment_cells(0, 1, 1, 20, 20), vec![(5, 3), (8, 5)]);
    // delete row 5: the comment of C5 is gone, E8 -> E7
    assert_eq!(unsafe { foglio_structure(b.0, 0, 1, 5, 1) }, 0);
    assert_eq!(b.comment_cells(0, 1, 1, 20, 20), vec![(7, 5)]);
    // undo brings it back exactly
    b.undo();
    assert_eq!(b.comment_cells(0, 1, 1, 20, 20), vec![(5, 3), (8, 5)]);
    assert_eq!(b.comment(0, 5, 3).as_deref(), Some("B3"));
    b.undo();
    b.undo();
    assert_eq!(b.comment_cells(0, 1, 1, 20, 20), vec![(3, 2), (6, 4)]);
    b.redo();
    assert_eq!(b.comment_cells(0, 1, 1, 20, 20), vec![(5, 2), (8, 4)]);
}

#[test]
fn comments_xlsx_round_trip() {
    let b = Book::new("en", "en");
    b.set(0, 1, 1, "x");
    b.set_comment(0, 1, 1, "First <note> & \"quotes\"\nline 2", "Ada Lovelace");
    b.set_comment(0, 10, 28, "AB10", "Bob");
    assert_eq!(unsafe { foglio_sheet_op(b.0, 0, 3, 0, ptr::null()) }, 0); // duplicate: Sheet1 (2)? -> sheet 1
    b.set_comment(1, 2, 2, "on the copy", "Ada Lovelace");
    let path = b.save("comments.xlsx");

    // the parts Excel expects
    let ct = part(&path, "[Content_Types].xml").unwrap();
    assert!(ct.contains(r#"<Default Extension="vml""#));
    assert!(ct.contains(r#"PartName="/xl/comments1.xml""#));
    assert!(ct.contains(r#"PartName="/xl/comments2.xml""#));
    let rels = part(&path, "xl/worksheets/_rels/sheet1.xml.rels").unwrap();
    assert!(rels.contains("relationships/comments") && rels.contains("../comments1.xml"));
    assert!(rels.contains("relationships/vmlDrawing") && rels.contains("../drawings/vmlDrawing1.vml"));
    let sheet = part(&path, "xl/worksheets/sheet1.xml").unwrap();
    assert!(sheet.contains("<legacyDrawing r:id="));
    let comments = part(&path, "xl/comments1.xml").unwrap();
    assert!(comments.contains("<author>Ada Lovelace</author>"));
    let vml = part(&path, "xl/drawings/vmlDrawing1.vml").unwrap();
    assert!(vml.contains(r#"ObjectType="Note""#) && vml.contains("<x:Row>9</x:Row>") && vml.contains("<x:Column>27</x:Column>"));
    assert!(part(&path, "xl/drawings/vmlDrawing2.vml").unwrap().contains(r#"data="2""#));

    let r = Book::open(&path, "en", "en");
    assert_eq!(r.comment(0, 1, 1).as_deref(), Some("First <note> & \"quotes\"\nline 2"));
    assert_eq!(r.author(0, 1, 1).as_deref(), Some("Ada Lovelace"));
    assert_eq!(r.comment(0, 10, 28).as_deref(), Some("AB10"));
    assert_eq!(r.author(0, 10, 28).as_deref(), Some("Bob"));
    assert_eq!(r.comment(1, 2, 2).as_deref(), Some("on the copy"));
    assert_eq!(r.comment(1, 1, 1).as_deref(), Some("First <note> & \"quotes\"\nline 2"));

    if let Some(out) = openpyxl(
        "import sys, openpyxl\nwb = openpyxl.load_workbook(sys.argv[1])\nfor ws in wb:\n  for row in ws.iter_rows():\n    for c in row:\n      if c.comment: print(ws.title, c.coordinate, repr(c.comment.text), c.comment.author)",
        &path,
    ) {
        assert!(out.contains("Sheet1 A1 'First <note> & \"quotes\"\\nline 2' Ada Lovelace"), "{out}");
        assert!(out.contains("Sheet1 AB10 'AB10' Bob"), "{out}");
    }
}

#[test]
fn excel_note_author_prefix_is_not_text() {
    // Excel writes "Author:" as a bold first run followed by a line break.
    let b = Book::new("en", "en");
    b.set_comment(0, 1, 1, "placeholder", "Ada");
    let path = b.save("excel_note.xlsx");
    // rewrite comments1.xml the way Excel does
    let dir = tmp("excel_note_parts");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(dir.join("xl")).unwrap();
    std::fs::write(
        dir.join("xl/comments1.xml"),
        r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<comments xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><authors><author>Ada</author></authors><commentList><comment ref="A1" authorId="0" shapeId="0"><text><r><rPr><b/><sz val="9"/><color indexed="81"/><rFont val="Tahoma"/><charset val="1"/></rPr><t>Ada:</t></r><r><rPr><sz val="9"/><color indexed="81"/><rFont val="Tahoma"/><charset val="1"/></rPr><t xml:space="preserve">
Real text</t></r></text></comment></commentList></comments>"#,
    )
    .unwrap();
    let st = Command::new("zip").current_dir(&dir).arg("-q").arg(&path).arg("xl/comments1.xml").status().unwrap();
    assert!(st.success());
    let r = Book::open(&path, "en", "en");
    assert_eq!(r.comment(0, 1, 1).as_deref(), Some("Real text"));
    assert_eq!(r.author(0, 1, 1).as_deref(), Some("Ada"));
}

// ---------- data validation ----------

#[test]
fn validation_list_inline_and_check() {
    let b = Book::new("en", "en");
    let rule = serde_json::json!({
        "type": "list", "formula1": "Yes, No ,Maybe",
        "errorStyle": "stop", "errorTitle": "Oops", "error": "Pick one",
        "promptTitle": "Answer", "prompt": "Yes or no"
    });
    b.set_validation(0, 2, 1, 10, 1, rule).unwrap();
    let v = b.validation(0, 5, 1).unwrap();
    assert_eq!(v["type"], "list");
    assert_eq!(v["formula1"], "Yes,No,Maybe");
    assert_eq!(v["sqref"], "A2:A10");
    assert_eq!(v["inCellDropdown"], true);
    assert_eq!(v["prompt"], "Yes or no");
    assert!(b.validation(0, 1, 1).is_none());
    assert!(b.validation(0, 11, 1).is_none());
    assert_eq!(b.list(0, 3, 1).unwrap(), vec!["Yes", "No", "Maybe"]);
    assert!(b.list(0, 3, 2).is_none());

    assert_eq!(b.check(0, 3, 1, "No").0, 0);
    assert_eq!(b.check(0, 3, 1, "maybe").0, 0, "case-insensitive");
    assert_eq!(b.check(0, 3, 1, "").0, 0);
    assert_eq!(b.check(0, 3, 1, "=A1").0, 0);
    assert_eq!(b.check(0, 3, 1, "Perhaps"), (1, "Oops".into(), "Pick one".into()));
    assert_eq!(b.check(0, 1, 1, "Perhaps").0, 0, "no rule");

    // undo / redo
    b.undo();
    assert!(b.validation(0, 5, 1).is_none());
    b.redo();
    assert!(b.validation(0, 5, 1).is_some());
}

#[test]
fn validation_italian_locale() {
    let b = Book::new("it", "it");
    // Italian list separator is ';'
    b.set_validation(0, 1, 1, 5, 1, serde_json::json!({"type": "list", "formula1": "uno;due;tre"})).unwrap();
    assert_eq!(b.list(0, 1, 1).unwrap(), vec!["uno", "due", "tre"]);
    assert_eq!(b.validation(0, 1, 1).unwrap()["formula1"], "uno;due;tre");
    // decimal comma
    b.set_validation(0, 1, 2, 5, 2, serde_json::json!({"type": "decimal", "operator": "between", "formula1": "1,5", "formula2": "2,5", "errorStyle": "warning"})).unwrap();
    let v = b.validation(0, 1, 2).unwrap();
    assert_eq!(v["formula1"], "1,5");
    assert_eq!(v["formula2"], "2,5");
    assert_eq!(b.check(0, 2, 2, "2").0, 0);
    assert_eq!(b.check(0, 2, 2, "2,4").0, 0);
    assert_eq!(b.check(0, 2, 2, "3").0, 2);
    assert_eq!(b.check(0, 2, 2, "abc").0, 2);
    // formulas in Italian
    b.set(0, 1, 5, "10");
    b.set_validation(0, 1, 3, 5, 3, serde_json::json!({"type": "whole", "operator": "lessThanOrEqual", "formula1": "=SOMMA($E$1;5)"})).unwrap();
    assert_eq!(b.validation(0, 1, 3).unwrap()["formula1"], "=SOMMA($E$1;5)");
    assert_eq!(b.check(0, 1, 3, "15").0, 0);
    assert_eq!(b.check(0, 1, 3, "16").0, 1);
    assert_eq!(b.check(0, 1, 3, "1,5").0, 1, "not a whole number");
    // dates
    b.set_validation(0, 1, 4, 5, 4, serde_json::json!({"type": "date", "operator": "greaterThanOrEqual", "formula1": "01/01/2025"})).unwrap();
    assert_eq!(b.validation(0, 1, 4).unwrap()["formula1"], "01/01/2025");
    assert_eq!(b.check(0, 1, 4, "15/03/2025").0, 0);
    assert_eq!(b.check(0, 1, 4, "31/12/2024").0, 1);
    // stored form in the file is English
    let path = b.save("validation_it.xlsx");
    let sheet = part(&path, "xl/worksheets/sheet1.xml").unwrap();
    assert!(sheet.contains("<formula1>&quot;uno,due,tre&quot;</formula1>"), "{sheet}");
    assert!(sheet.contains("<formula1>1.5</formula1><formula2>2.5</formula2>"), "{sheet}");
    assert!(sheet.contains("<formula1>SUM($E$1,5)</formula1>"), "{sheet}");
    assert!(sheet.contains("<formula1>45658</formula1>"), "{sheet}");
}

#[test]
fn validation_range_list_numbers_text_length_custom() {
    let b = Book::new("en", "en");
    assert_eq!(unsafe { foglio_sheet_op(b.0, 0, 3, 0, ptr::null()) }, 0); // a second sheet
    for (i, v) in ["red", "", "green", "1.5"].iter().enumerate() {
        b.set(1, i as i32 + 1, 1, v);
    }
    let name = take(foglio_sheet_name(b.0, 1));
    b.set_validation(0, 1, 1, 3, 1, serde_json::json!({"type": "list", "formula1": format!("='{name}'!$A$1:$A$4")})).unwrap();
    assert_eq!(b.list(0, 2, 1).unwrap(), vec!["red", "green", "1.5"]);
    assert_eq!(b.check(0, 2, 1, "GREEN").0, 0);
    assert_eq!(b.check(0, 2, 1, "1.50").0, 0, "numbers compare by value");
    assert_eq!(b.check(0, 2, 1, "blue").0, 1);
    // live: the list follows the cells
    b.set(1, 2, 1, "blue");
    assert_eq!(b.check(0, 2, 1, "blue").0, 0);
    // renaming the list sheet keeps the reference
    assert_eq!(unsafe { foglio_sheet_op(b.0, 1, 0, 0, c("My Lists").as_ptr()) }, 0);
    assert_eq!(b.validation(0, 1, 1).unwrap()["formula1"], "='My Lists'!$A$1:$A$4");
    assert_eq!(b.list(0, 2, 1).unwrap(), vec!["red", "blue", "green", "1.5"]);
    b.undo();
    assert_eq!(b.validation(0, 1, 1).unwrap()["formula1"], format!("='{name}'!$A$1:$A$4"));

    // relative list reference: each row reads its own row
    b.set(0, 1, 10, "a");
    b.set(0, 2, 10, "b");
    b.set_validation(0, 1, 2, 2, 2, serde_json::json!({"type": "list", "formula1": "=J1"})).unwrap();
    assert_eq!(b.list(0, 1, 2).unwrap(), vec!["a"]);
    assert_eq!(b.list(0, 2, 2).unwrap(), vec!["b"]);

    // text length
    b.set_validation(0, 1, 3, 9, 3, serde_json::json!({"type": "textLength", "operator": "lessThanOrEqual", "formula1": "3", "errorStyle": "information"})).unwrap();
    assert_eq!(b.check(0, 1, 3, "abc").0, 0);
    assert_eq!(b.check(0, 1, 3, "abcd").0, 3);

    // custom, relative to the top-left cell; evaluated with the candidate in the cell
    b.set_validation(0, 1, 4, 9, 4, serde_json::json!({"type": "custom", "formula1": "=AND(ISNUMBER(D1),MOD(D1,2)=0)"})).unwrap();
    assert_eq!(b.check(0, 5, 4, "4").0, 0);
    assert_eq!(b.check(0, 5, 4, "5").0, 1);
    assert_eq!(b.check(0, 5, 4, "x").0, 1);
    assert_eq!(b.input(0, 5, 4), "", "the cell is left alone");
    // a rule reading a formula that depends on the cell: the formula is read, not run
    // with the candidate (which would leave a wrong cached value behind)
    b.set(0, 1, 11, "1");
    b.set(0, 2, 11, "=K1*10");
    b.set(0, 1, 11, "2"); // incremental recalculation: K2 = 20
    b.set_validation(0, 1, 11, 1, 11, serde_json::json!({"type": "custom", "formula1": "=$K$2<100"})).unwrap();
    assert_eq!(b.check(0, 1, 11, "50").0, 0);
    assert_eq!(b.shown(0, 2, 11), "20");
    // a rule that does not show alerts accepts anything
    b.set_validation(0, 1, 5, 9, 5, serde_json::json!({"type": "whole", "operator": "equal", "formula1": "1", "showErrorMessage": false})).unwrap();
    assert_eq!(b.check(0, 3, 5, "7").0, 0);
    // invalid formula
    assert!(b.set_validation(0, 1, 6, 1, 6, serde_json::json!({"type": "custom", "formula1": "=SUM(("})).is_err());
    assert!(b.set_validation(0, 1, 6, 1, 6, serde_json::json!({"type": "whole", "formula1": "abc"})).is_err());
    assert!(b.set_validation(0, 1, 6, 1, 6, serde_json::json!({"type": "bogus"})).is_err());
    assert!(b.set_validation(0, 1, 6, 1, 6, serde_json::json!({"type": "list"})).is_err());
    assert!(b.set_validation(0, 1, 6, 1, 6, serde_json::json!({"type": "whole", "formula1": "1"})).is_err(), "between needs formula2");
    assert!(b.set_validation(0, 1, 6, 1, 6, serde_json::json!({"type": "none", "prompt": "hi"})).is_ok());
}

#[test]
fn validation_clear_split_and_structure() {
    let b = Book::new("en", "en");
    b.set_validation(0, 1, 1, 10, 3, serde_json::json!({"type": "whole", "operator": "greaterThan", "formula1": "=$E$1"})).unwrap();
    // clearing the middle splits the rule
    assert_eq!(unsafe { foglio_validation_clear(b.0, 0, 4, 2, 5, 2) }, 0);
    assert!(b.validation(0, 4, 2).is_none());
    assert!(b.validation(0, 4, 1).is_some());
    assert!(b.validation(0, 6, 2).is_some());
    assert!(b.validation(0, 3, 2).is_some());
    let sqref = b.validation(0, 1, 1).unwrap()["sqref"].as_str().unwrap().to_string();
    assert_eq!(sqref, "A1:C3 A6:C10 A4:A5 C4:C5");
    b.undo();
    assert_eq!(b.validation(0, 4, 2).unwrap()["sqref"], "A1:C10");

    // a new rule replaces the old one on its cells
    b.set_validation(0, 1, 1, 1, 1, serde_json::json!({"type": "list", "formula1": "x,y"})).unwrap();
    assert_eq!(b.validation(0, 1, 1).unwrap()["type"], "list");
    assert_eq!(b.validation(0, 2, 1).unwrap()["type"], "whole");

    // insert rows above: ranges and references move
    assert_eq!(unsafe { foglio_structure(b.0, 0, 0, 1, 2) }, 0);
    assert_eq!(b.validation(0, 3, 1).unwrap()["sqref"], "A3");
    let whole = b.validation(0, 4, 1).unwrap();
    assert_eq!(whole["formula1"], "=$E$3");
    assert_eq!(whole["sqref"], "A4:C12 B3:C3");
    // delete rows inside: clipped
    assert_eq!(unsafe { foglio_structure(b.0, 0, 1, 5, 20) }, 0);
    assert!(b.validation(0, 5, 2).is_none());
    assert!(b.validation(0, 4, 2).is_some());
    // undo restores exactly
    b.undo();
    b.undo();
    assert_eq!(b.validation(0, 2, 2).unwrap()["formula1"], "=$E$1");
    assert_eq!(b.validation(0, 1, 1).unwrap()["sqref"], "A1");
}

#[test]
fn validation_xlsx_round_trip() {
    let b = Book::new("en", "en");
    let rules = [
        ((1, 1, 20, 1), serde_json::json!({"type": "list", "formula1": "a,b,c", "inCellDropdown": false, "promptTitle": "T", "prompt": "P <&>", "errorTitle": "E", "error": "Msg"})),
        ((1, 2, 20, 2), serde_json::json!({"type": "whole", "operator": "notBetween", "formula1": "1", "formula2": "10", "errorStyle": "warning", "allowBlank": false})),
        ((1, 3, 20, 3), serde_json::json!({"type": "decimal", "operator": "greaterThan", "formula1": "=B1*2", "showInputMessage": false})),
        ((1, 4, 20, 4), serde_json::json!({"type": "date", "operator": "between", "formula1": "2025-01-01", "formula2": "2025-12-31", "errorStyle": "information"})),
        ((1, 5, 20, 5), serde_json::json!({"type": "time", "operator": "lessThan", "formula1": "12:30"})),
        ((1, 6, 20, 6), serde_json::json!({"type": "textLength", "operator": "equal", "formula1": "5"})),
        ((1, 7, 20, 7), serde_json::json!({"type": "custom", "formula1": "=ISODD(G1)"})),
        ((1, 8, 20, 8), serde_json::json!({"type": "none", "promptTitle": "Hint", "prompt": "anything"})),
    ];
    for ((r0, c0, r1, c1), rule) in &rules {
        b.set_validation(0, *r0, *c0, *r1, *c1, rule.clone()).unwrap();
    }
    let before: Vec<serde_json::Value> = (1..=8).map(|col| b.validation(0, 5, col).unwrap()).collect();
    let path = b.save("validation.xlsx");
    let r = Book::open(&path, "en", "en");
    let after: Vec<serde_json::Value> = (1..=8).map(|col| r.validation(0, 5, col).unwrap()).collect();
    assert_eq!(before, after);
    assert_eq!(after[0]["inCellDropdown"], false);
    assert_eq!(after[3]["formula1"], "01/01/2025", "{}", after[3]);
    assert_eq!(after[4]["formula1"], "12:30:00");

    if let Some(out) = openpyxl(
        "import sys, openpyxl\nwb = openpyxl.load_workbook(sys.argv[1])\nfor dv in wb.active.data_validations.dataValidation:\n  print(dv.sqref, dv.type, dv.operator, dv.formula1, dv.formula2, dv.showDropDown, dv.errorStyle, dv.allow_blank)",
        &path,
    ) {
        assert!(out.contains("A1:A20 list None \"a,b,c\" None True None True"), "{out}");
        assert!(out.contains("B1:B20 whole notBetween 1 10 False warning False"), "{out}");
        assert!(out.contains("D1:D20 date None 45658 46022 False information True"), "{out}");
        assert!(out.contains("G1:G20 custom None ISODD(G1)"), "{out}");
    }
}

// ---------- openpyxl workbook ----------

#[test]
fn openpyxl_workbook() {
    let b = Book::open(&fixture("features_openpyxl.xlsx"), "en", "en");
    // comments (absolute part names, authors)
    assert_eq!(b.comment(0, 1, 1).as_deref(), Some("Pick a fruit\nfrom the list"));
    assert_eq!(b.author(0, 1, 1).as_deref(), Some("Ada"));
    assert_eq!(b.comment(0, 3, 3).as_deref(), Some("second note"));
    assert_eq!(b.author(0, 3, 3).as_deref(), Some("Bob"));
    // validation
    assert_eq!(b.list(0, 2, 1).unwrap(), vec!["apple", "pear", "plum"]);
    assert_eq!(b.check(0, 2, 1, "kiwi"), (1, "Wrong fruit".into(), "Choose from the list".into()));
    assert_eq!(b.validation(0, 2, 1).unwrap()["prompt"], "Which fruit?");
    assert_eq!(b.check(0, 2, 2, "11").0, 2);
    assert_eq!(b.check(0, 2, 2, "10").0, 0);
    let f = b.validation(0, 2, 6).unwrap();
    assert_eq!(f["sqref"], "F2:F5 H2");
    assert_eq!(f["inCellDropdown"], false);
    assert_eq!(b.list(0, 2, 8).unwrap(), vec!["red", "green", "blue"]);
    assert_eq!(b.check(0, 3, 7, "4").0, 0);
    assert_eq!(b.check(0, 3, 7, "3").0, 1);
    // links
    assert_eq!(b.link(0, 12, 1).unwrap()["address"], "https://www.ironcalc.com/");
    assert_eq!(b.link(0, 13, 1).unwrap()["address"], "#Lists!A1");
    // tab colours, fonts
    assert_eq!(unsafe { foglio_sheet_color(b.0, 0) }, 0xFF0000);
    assert_eq!(unsafe { foglio_sheet_color(b.0, 1) }, 0x00B050);
    assert_eq!(take(unsafe { foglio_font_name_at(b.0, 0, 1, 4) }), "Arial");
    assert_eq!(take(unsafe { foglio_font_name_at(b.0, 0, 1, 5) }), "Courier New");

    // and through our own export again
    let r = b.round_trip("openpyxl_again.xlsx", "en", "en");
    assert_eq!(r.comment(0, 1, 1).as_deref(), Some("Pick a fruit\nfrom the list"));
    assert_eq!(r.list(0, 2, 8).unwrap(), vec!["red", "green", "blue"]);
    assert_eq!(r.validation(0, 2, 6).unwrap()["sqref"], "F2:F5 H2");
    assert_eq!(unsafe { foglio_sheet_color(r.0, 1) }, 0x00B050);
    assert_eq!(take(unsafe { foglio_font_name_at(r.0, 0, 1, 4) }), "Arial");
    assert_eq!(r.link(0, 12, 1).unwrap()["address"], "https://www.ironcalc.com/");
}

// ---------- font name ----------

#[test]
fn font_name() {
    let b = Book::new("en", "en");
    b.set(0, 1, 1, "hello");
    let default = take(unsafe { foglio_font_name_at(b.0, 0, 1, 1) });
    assert!(!default.is_empty());
    let set = |name: &str| unsafe { foglio_set_style(b.0, 0, 1, 1, 2, 2, c("font.name").as_ptr(), c(name).as_ptr()) };
    assert_eq!(set("Georgia"), 0);
    assert_eq!(take(unsafe { foglio_font_name_at(b.0, 0, 1, 1) }), "Georgia");
    assert_eq!(take(unsafe { foglio_font_name_at(b.0, 0, 2, 2) }), "Georgia");
    assert_eq!(set(""), -1);
    b.undo();
    assert_eq!(take(unsafe { foglio_font_name_at(b.0, 0, 1, 1) }), default);
    b.redo();
    let path = b.save("font.xlsx");
    let styles = part(&path, "xl/styles.xml").unwrap();
    assert!(styles.contains(r#"<name val="Georgia"/>"#));
    let r = Book::open(&path, "en", "en");
    assert_eq!(take(unsafe { foglio_font_name_at(r.0, 0, 1, 1) }), "Georgia");
    if let Some(out) = openpyxl("import sys, openpyxl\nprint(openpyxl.load_workbook(sys.argv[1]).active['A1'].font.name)", &path) {
        assert_eq!(out.trim(), "Georgia");
    }
}

// ---------- tab colour ----------

#[test]
fn sheet_tab_color() {
    let b = Book::new("en", "en");
    assert_eq!(unsafe { foglio_sheet_color(b.0, 0) }, NO_COLOR);
    assert_eq!(unsafe { foglio_set_sheet_color(b.0, 0, 0x4472C4) }, 0);
    assert_eq!(unsafe { foglio_sheet_color(b.0, 0) }, 0x4472C4);
    b.undo();
    assert_eq!(unsafe { foglio_sheet_color(b.0, 0) }, NO_COLOR);
    b.redo();
    assert_eq!(unsafe { foglio_sheet_op(b.0, 0, 3, 0, ptr::null()) }, 0);
    assert_eq!(unsafe { foglio_set_sheet_color(b.0, 1, 0xFF0000) }, 0);
    assert_eq!(unsafe { foglio_set_sheet_color(b.0, 1, NO_COLOR) }, 0);
    let path = b.save("tabs.xlsx");
    let sheet = part(&path, "xl/worksheets/sheet1.xml").unwrap();
    assert!(sheet.contains(r#"<sheetPr><tabColor rgb="FF4472C4"/></sheetPr>"#), "{sheet}");
    assert!(!part(&path, "xl/worksheets/sheet2.xml").unwrap().contains("sheetPr"));
    let r = Book::open(&path, "en", "en");
    assert_eq!(unsafe { foglio_sheet_color(r.0, 0) }, 0x4472C4);
    assert_eq!(unsafe { foglio_sheet_color(r.0, 1) }, NO_COLOR);
    if let Some(out) = openpyxl("import sys, openpyxl\nprint(openpyxl.load_workbook(sys.argv[1]).worksheets[0].sheet_properties.tabColor.rgb)", &path) {
        assert_eq!(out.trim(), "FF4472C4");
    }
}

// ---------- hyperlinks ----------

#[test]
fn hyperlinks() {
    let b = Book::new("en", "en");
    assert!(b.link(0, 1, 1).is_none());
    let set = |row, addr: &str, display: Option<&str>, tip: Option<&str>| {
        let d = display.map(c);
        let t = tip.map(c);
        unsafe {
            foglio_link_set(
                b.0, 0, row, 1, c(addr).as_ptr(),
                d.as_ref().map_or(ptr::null(), |x| x.as_ptr()),
                t.as_ref().map_or(ptr::null(), |x| x.as_ptr()),
            )
        }
    };
    assert_eq!(set(1, "https://example.com/a?b=1&c=2", Some("Example"), Some("Go")), 0);
    assert_eq!(b.shown(0, 1, 1), "Example");
    let l = b.link(0, 1, 1).unwrap();
    assert_eq!(l["address"], "https://example.com/a?b=1&c=2");
    assert_eq!(l["tooltip"], "Go");
    assert_eq!(l["dynamic"], false);
    // undo removes the link and the label in one step
    b.undo();
    assert!(b.link(0, 1, 1).is_none());
    assert_eq!(b.shown(0, 1, 1), "");
    b.redo();
    assert_eq!(set(2, "#Sheet1!C5", None, None), 0);
    assert_eq!(b.link(0, 2, 1).unwrap()["address"], "#Sheet1!C5");
    assert_eq!(set(3, "mailto:ada@example.com", Some("mail"), None), 0);
    assert_eq!(set(4, "", None, None), -1);
    b.set(0, 5, 1, "=HYPERLINK(\"https://ironcalc.com\",\"IC\")");
    let d = b.link(0, 5, 1).unwrap();
    assert_eq!(d["dynamic"], true);
    assert_eq!(d["address"], "https://ironcalc.com");
    // remove
    assert_eq!(unsafe { foglio_link_remove(b.0, 0, 3, 1) }, 0);
    assert!(b.link(0, 3, 1).is_none());
    assert_eq!(b.shown(0, 3, 1), "mail");

    let r = b.round_trip("links.xlsx", "en", "en");
    assert_eq!(r.link(0, 1, 1).unwrap()["address"], "https://example.com/a?b=1&c=2");
    assert_eq!(r.link(0, 1, 1).unwrap()["tooltip"], "Go");
    assert_eq!(r.link(0, 2, 1).unwrap()["address"], "#Sheet1!C5");
    assert!(r.link(0, 3, 1).is_none());
}

// ---------- summarize ----------

fn sales(b: &Book) {
    let rows = [
        ("Region", "Amount"),
        ("North", "10"),
        ("South", "5"),
        ("north", "7"),
        ("East", "3"),
        ("", "100"),
        ("South", "1"),
        ("a*b", "2"),
        ("a+b", "4"),
    ];
    for (i, (k, v)) in rows.iter().enumerate() {
        if !k.is_empty() {
            b.set(0, i as i32 + 1, 1, k);
        }
        b.set(0, i as i32 + 1, 2, v);
    }
}

fn summarize(b: &Book, agg: i32, name: Option<&str>) -> Result<u32, String> {
    let n = name.map(c);
    let mut err = ptr::null_mut();
    let r = unsafe {
        foglio_summarize(b.0, 0, 1, 1, 9, 2, 1, 2, agg, n.as_ref().map_or(ptr::null(), |x| x.as_ptr()), &mut err)
    };
    if r < 0 {
        Err(take_opt(err).unwrap_or_default())
    } else {
        Ok(r as u32)
    }
}

#[test]
fn summarize_english() {
    let b = Book::new("en", "en");
    sales(&b);
    let s = summarize(&b, 0, None).unwrap();
    assert_eq!(s, 1);
    assert_eq!(take(foglio_sheet_name(b.0, s)), "Summary");
    let table: Vec<(String, String)> = (1..=7).map(|r| (b.shown(s, r, 1), b.shown(s, r, 2))).collect();
    assert_eq!(
        table,
        vec![
            ("Region".into(), "Sum of Amount".into()),
            ("a*b".into(), "2".into()),
            ("a+b".into(), "4".into()),
            ("East".into(), "3".into()),
            ("North".into(), "17".into()),
            ("South".into(), "6".into()),
            ("Total".into(), "32".into()),
        ]
    );
    assert_eq!(b.input(s, 2, 2), "=SUMIFS(Sheet1!$B$2:$B$9,Sheet1!$A$2:$A$9,\"=a~*b\")");
    assert_eq!(b.input(s, 5, 2), "=SUMIFS(Sheet1!$B$2:$B$9,Sheet1!$A$2:$A$9,$A5)");
    // live
    b.set(0, 2, 2, "20");
    assert_eq!(b.shown(s, 5, 2), "27");
    assert_eq!(b.shown(s, 7, 2), "42");
    // one undo step removes the sheet
    b.set(0, 2, 2, "10");
    b.undo(); // the edit
    b.undo(); // the edit
    assert_eq!(foglio_sheet_count(b.0), 2);
    b.undo(); // the summary
    assert_eq!(foglio_sheet_count(b.0), 1);
    assert!(foglio_can_undo(b.0));
    b.redo();
    assert_eq!(foglio_sheet_count(b.0), 2);
    assert_eq!(b.shown(1, 5, 2), "17");

    // the other aggregations, unique names
    let count = summarize(&b, 1, Some("Summary")).unwrap();
    assert_eq!(take(foglio_sheet_name(b.0, count)), "Summary (2)");
    assert_eq!(b.shown(count, 1, 2), "Count of Amount");
    assert_eq!(b.shown(count, 5, 2), "2");
    assert_eq!(b.shown(count, 7, 2), "7");
    let avg = summarize(&b, 2, Some("Avg")).unwrap();
    assert_eq!(b.shown(avg, 5, 2), "8.5");
    assert_eq!(b.shown(avg, 6, 2), "3");
    assert_eq!(b.shown(avg, 7, 2), "4.571428571");
    let min = summarize(&b, 3, Some("Min")).unwrap();
    assert_eq!(b.shown(min, 5, 2), "7");
    assert_eq!(b.shown(min, 7, 2), "1");
    let max = summarize(&b, 4, Some("Max")).unwrap();
    assert_eq!(b.shown(max, 5, 2), "10");
    assert_eq!(b.shown(max, 7, 2), "10");

    // errors leave nothing behind
    let sheets = foglio_sheet_count(b.0);
    assert!(summarize(&b, 7, None).is_err());
    let mut err = ptr::null_mut();
    assert_eq!(unsafe { foglio_summarize(b.0, 0, 1, 1, 9, 2, 3, 2, 0, ptr::null(), &mut err) }, -1);
    assert!(!take(err).is_empty());
    assert_eq!(unsafe { foglio_summarize(b.0, 0, 6, 1, 6, 2, 1, 2, 0, ptr::null(), ptr::null_mut()) }, -1);
    assert_eq!(foglio_sheet_count(b.0), sheets);

    // xlsx: formulas survive
    let r = b.round_trip("summary.xlsx", "en", "en");
    assert_eq!(r.input(1, 5, 2), "=SUMIFS(Sheet1!$B$2:$B$9,Sheet1!$A$2:$A$9,$A5)");
    assert_eq!(r.shown(1, 7, 2), "32");
    assert_eq!(r.shown(max, 7, 2), "10");
    r.set(0, 3, 2, "50");
    assert_eq!(r.shown(1, 6, 2), "51");
}

#[test]
fn summarize_italian() {
    let b = Book::new("it", "it");
    for (i, (k, v)) in [("Città", "Importo"), ("Roma", "1,5"), ("Milano", "2"), ("Roma", "3"), ("2", "4"), ("10", "4")]
        .iter()
        .enumerate()
    {
        b.set(0, i as i32 + 1, 1, k);
        b.set(0, i as i32 + 1, 2, v);
    }
    // the sheet name needs quotes
    assert_eq!(unsafe { foglio_sheet_op(b.0, 0, 0, 0, c("Dati 2025").as_ptr()) }, 0);
    let mut err = ptr::null_mut();
    let s = unsafe { foglio_summarize(b.0, 0, 1, 1, 6, 2, 1, 2, 0, ptr::null(), &mut err) };
    assert!(s > 0, "{:?}", take_opt(err));
    let s = s as u32;
    assert_eq!(take(foglio_sheet_name(b.0, s)), "Riepilogo");
    let table: Vec<(String, String)> = (1..=6).map(|r| (b.shown(s, r, 1), b.shown(s, r, 2))).collect();
    assert_eq!(
        table,
        vec![
            ("Città".into(), "Somma di Importo".into()),
            ("2".into(), "4".into()),
            ("10".into(), "4".into()),
            ("Milano".into(), "2".into()),
            ("Roma".into(), "4,5".into()),
            ("Totale".into(), "14,5".into()),
        ]
    );
    // localized formula in the formula bar, English in the file
    assert_eq!(b.input(s, 5, 2), "=SOMMA.PIÙ.SE('Dati 2025'!$B$2:$B$6;'Dati 2025'!$A$2:$A$6;$A5)");
    let path = b.save("summary_it.xlsx");
    let xml = part(&path, "xl/worksheets/sheet2.xml").unwrap();
    assert!(xml.contains("<f>SUMIFS(&apos;Dati 2025&apos;!$B$2:$B$6,&apos;Dati 2025&apos;!$A$2:$A$6,$A5)</f>"), "{xml}");
    let r = Book::open(&path, "it", "it");
    assert_eq!(r.shown(s, 6, 2), "14,5");
    // number keys stay numbers (with the source format)
    assert_eq!(r.input(s, 2, 1), "2");
}
