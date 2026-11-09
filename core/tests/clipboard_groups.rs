//! Moving ranges without touching the internal clipboard, undo groups, hyperlinks kept by
//! sort / remove duplicates, and the typed values of list validation items.
#![allow(improper_ctypes)] // FoglioBook is opaque, used through pointers only

use std::ffi::{c_char, CStr, CString};
use std::ptr;
use std::sync::Mutex;

use foglio_core::{foglio_free, foglio_get_input, foglio_new, foglio_set_input, foglio_set_locale, foglio_string_free, foglio_undo, FoglioBook};

extern "C" {
    fn foglio_copy(b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32, out_token: *mut u64) -> *mut c_char;
    fn foglio_paste_internal(b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32, token: u64, is_cut: bool) -> i32;
    fn foglio_move_range(b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32, row: i32, col: i32, is_cut: bool) -> i32;
    fn foglio_begin_group(b: *mut FoglioBook);
    fn foglio_end_group(b: *mut FoglioBook);
    fn foglio_remove_duplicates(b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32) -> i32;
    fn foglio_sort(b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32, key_col: i32, ascending: bool) -> i32;
    fn foglio_link_get(b: *const FoglioBook, sheet: u32, row: i32, col: i32) -> *mut c_char;
    fn foglio_link_set(
        b: *mut FoglioBook, sheet: u32, row: i32, col: i32, address: *const c_char, display: *const c_char,
        tooltip: *const c_char,
    ) -> i32;
    fn foglio_validation_set(
        b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32, json: *const c_char, err_out: *mut *mut c_char,
    ) -> i32;
    fn foglio_validation_list_items(b: *mut FoglioBook, sheet: u32, row: i32, col: i32) -> *mut c_char;
}

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

struct Book(*mut FoglioBook);

impl Drop for Book {
    fn drop(&mut self) {
        unsafe { foglio_free(self.0) };
    }
}

impl Book {
    fn new(locale: &str) -> Book {
        let _g = LOCALE.lock().unwrap_or_else(|e| e.into_inner());
        unsafe { foglio_set_locale(c(locale).as_ptr(), c(locale).as_ptr(), c("UTC").as_ptr()) };
        let b = foglio_new();
        unsafe { foglio_set_locale(c("en").as_ptr(), c("en").as_ptr(), c("UTC").as_ptr()) };
        assert!(!b.is_null());
        Book(b)
    }
    fn set(&self, row: i32, col: i32, v: &str) {
        assert_eq!(unsafe { foglio_set_input(self.0, 0, row, col, c(v).as_ptr()) }, 0);
    }
    fn input(&self, row: i32, col: i32) -> String {
        take_opt(foglio_get_input(self.0, 0, row, col)).unwrap_or_default()
    }
    fn link(&self, row: i32, col: i32) -> Option<String> {
        take_opt(unsafe { foglio_link_get(self.0, 0, row, col) })
            .map(|s| serde_json::from_str::<serde_json::Value>(&s).unwrap()["address"].as_str().unwrap().to_string())
    }
    fn set_link(&self, row: i32, col: i32, address: &str) {
        assert_eq!(unsafe { foglio_link_set(self.0, 0, row, col, c(address).as_ptr(), ptr::null(), ptr::null()) }, 0);
    }
}

#[test]
fn move_range_keeps_the_clipboard() {
    let b = Book::new("en");
    b.set(1, 2, "3");
    b.set(1, 1, "=B1*2");
    b.set(3, 3, "x");
    b.set(4, 4, "=C3&\"!\"");
    let mut token = 0u64;
    let text = take_opt(unsafe { foglio_copy(b.0, 0, 1, 1, 1, 1, &mut token) }).unwrap();
    assert_eq!(text, "6");
    // cut C3 to E6: references follow, the clipboard stays
    assert_eq!(unsafe { foglio_move_range(b.0, 0, 3, 3, 3, 3, 6, 5, true) }, 0);
    assert_eq!(b.input(3, 3), "");
    assert_eq!(b.input(6, 5), "x");
    assert_eq!(b.input(4, 4), "=E6&\"!\"");
    // copy (not cut) leaves the source
    assert_eq!(unsafe { foglio_move_range(b.0, 0, 6, 5, 6, 5, 8, 5, false) }, 0);
    assert_eq!(b.input(6, 5), "x");
    assert_eq!(b.input(8, 5), "x");
    // the user's copy of A1 still pastes with relative references
    assert_eq!(unsafe { foglio_paste_internal(b.0, 0, 1, 5, 1, 5, token, false) }, 0);
    assert_eq!(b.input(1, 5), "=F1*2");
    // each move is one undo step
    assert_eq!(foglio_undo(b.0), 0);
    assert_eq!(foglio_undo(b.0), 0);
    assert_eq!(b.input(8, 5), "");
    assert_eq!(foglio_undo(b.0), 0);
    assert_eq!(b.input(3, 3), "x");
    assert_eq!(b.input(6, 5), "");
}

#[test]
fn undo_groups() {
    let b = Book::new("en");
    b.set(1, 1, "a");
    unsafe { foglio_begin_group(b.0) };
    b.set(2, 1, "b");
    unsafe { foglio_begin_group(b.0) }; // nested
    b.set(3, 1, "c");
    unsafe { foglio_end_group(b.0) };
    b.set(4, 1, "d");
    unsafe { foglio_end_group(b.0) };
    assert_eq!(foglio_undo(b.0), 0);
    assert_eq!((b.input(1, 1), b.input(2, 1), b.input(3, 1), b.input(4, 1)), ("a".into(), "".into(), "".into(), "".into()));
    // an empty group adds no step
    unsafe { foglio_begin_group(b.0) };
    unsafe { foglio_end_group(b.0) };
    assert_eq!(foglio_undo(b.0), 0);
    assert_eq!(b.input(1, 1), "");
}

#[test]
fn remove_duplicates_is_one_step_and_keeps_links() {
    let b = Book::new("en");
    for (r, v) in ["x", "x", "y", "x", "z"].iter().enumerate() {
        b.set(r as i32 + 1, 1, v);
    }
    b.set_link(3, 1, "https://y.example");
    assert_eq!(unsafe { foglio_remove_duplicates(b.0, 0, 1, 1, 5, 1) }, 2);
    assert_eq!((b.input(1, 1), b.input(2, 1), b.input(3, 1), b.input(4, 1)), ("x".into(), "y".into(), "z".into(), "".into()));
    assert_eq!(b.link(2, 1).as_deref(), Some("https://y.example"));
    assert_eq!(b.link(3, 1), None);
    assert_eq!(foglio_undo(b.0), 0);
    assert_eq!(b.input(4, 1), "x");
    assert_eq!(b.input(5, 1), "z");
    assert_eq!(b.link(3, 1).as_deref(), Some("https://y.example"));
}

#[test]
fn sort_moves_links_with_their_row() {
    let b = Book::new("en");
    b.set(1, 1, "b");
    b.set(2, 1, "a");
    b.set_link(1, 1, "https://b.example");
    assert_eq!(unsafe { foglio_sort(b.0, 0, 1, 1, 2, 1, 1, true) }, 0);
    assert_eq!(b.input(1, 1), "a");
    assert_eq!(b.link(1, 1), None);
    assert_eq!(b.link(2, 1).as_deref(), Some("https://b.example"));
}

fn items(b: &Book, row: i32, col: i32) -> Vec<(String, String)> {
    let s = take_opt(unsafe { foglio_validation_list_items(b.0, 0, row, col) }).unwrap();
    serde_json::from_str::<Vec<serde_json::Value>>(&s)
        .unwrap()
        .into_iter()
        .map(|v| (v["display"].as_str().unwrap().to_string(), v["input"].as_str().unwrap().to_string()))
        .collect()
}

#[test]
fn list_items_give_typed_values() {
    let b = Book::new("it");
    b.set(1, 10, "1234,5");
    b.set(2, 10, "=1/3");
    b.set(3, 10, "'007");
    b.set(4, 10, "=\"12\"");
    b.set(5, 10, "Rossi");
    let rule = r##"{"type": "list", "formula1": "=$J$1:$J$5"}"##;
    assert_eq!(unsafe { foglio_validation_set(b.0, 0, 1, 1, 3, 1, c(rule).as_ptr(), ptr::null_mut()) }, 0);
    let got = items(&b, 1, 1);
    assert_eq!(got.len(), 5, "{got:?}");
    assert_eq!(got[0].1, "1234,5");
    assert!(got[1].1.starts_with("0,333333333333"), "{got:?}");
    assert_eq!(got[2].1, "'007");
    assert_eq!(got[3].1, "'12");
    assert_eq!(got[4], ("Rossi".to_string(), "Rossi".to_string()));
    // inline lists: what is shown is what is typed
    let inline = r##"{"type": "list", "formula1": "Sì;No"}"##;
    assert_eq!(unsafe { foglio_validation_set(b.0, 0, 1, 2, 1, 2, c(inline).as_ptr(), ptr::null_mut()) }, 0);
    assert_eq!(items(&b, 1, 2), vec![("Sì".to_string(), "Sì".to_string()), ("No".to_string(), "No".to_string())]);
}
