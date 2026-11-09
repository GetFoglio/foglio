//! foglio_core: a thin C ABI over IronCalc's UserModel, for the Swift/AppKit shell.
//! See include/foglio_core.h for the contract.

use std::collections::HashMap;
use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
use std::time::Instant;

use ironcalc::base::expressions::types::Area;
use ironcalc::base::{Model, UserModel};

pub(crate) const NO_COLOR: u32 = 0xFFFF_FFFF;

mod ui;
pub mod charts; // Foglio charts: C ABI in src/charts.rs, include/foglio_charts.h
pub mod pictures; // Foglio pictures: C ABI in src/pictures.rs, include/foglio_pictures.h

// ---------- locale settings (shared by new and opened workbooks) ----------

static SETTINGS: std::sync::Mutex<(&'static str, &'static str, &'static str)> = std::sync::Mutex::new(("en", "en", "UTC"));

/// (locale, language, timezone) used for new and opened workbooks.
pub(crate) fn settings() -> (&'static str, &'static str, &'static str) {
    *SETTINGS.lock().unwrap()
}

/// Sets locale ("en", "en-GB", "it", "de", "es", "fr"), function-name language ("en", "it", "de", "es", "fr")
/// and IANA timezone. Unknown values fall back to English/UTC. Call before creating or opening workbooks.
#[no_mangle]
pub unsafe extern "C" fn foglio_set_locale(locale: *const c_char, language: *const c_char, tz: *const c_char) {
    let pick = |v: Option<&str>, allowed: &[&'static str], default: &'static str| -> &'static str {
        v.and_then(|v| allowed.iter().find(|a| **a == v).copied()).unwrap_or(default)
    };
    let locale = pick(cstr(locale), &["en", "en-GB", "it", "de", "es", "fr"], "en");
    let language = pick(cstr(language), &["en", "it", "de", "es", "fr"], "en");
    let tz_s = cstr(tz).unwrap_or("UTC");
    let tz: &'static str = if ironcalc::base::get_all_timezones().iter().any(|t| t == tz_s) {
        Box::leak(tz_s.to_string().into_boxed_str())
    } else {
        "UTC"
    };
    *SETTINGS.lock().unwrap() = (locale, language, tz);
}
mod features;
mod fnames;
pub mod io;

#[repr(C)]
pub struct FoglioCell {
    pub(crate) row: i32,
    pub(crate) col: i32,
    pub(crate) text_off: u32,
    pub(crate) text_len: u32,
    pub(crate) kind: u8,
    pub(crate) align: u8,
    pub(crate) bold: u8,
    pub(crate) italic: u8,
    pub(crate) fg: u32,
    pub(crate) bg: u32,
    /// font size in points (Excel units, 11 = default)
    pub(crate) font_size: u8,
    pub(crate) underline: u8,
    pub(crate) strike: u8,
    pub(crate) wrap: u8,
    /// 0 bottom, 1 center, 2 top
    pub(crate) valign: u8,
    /// bit0 top, bit1 right, bit2 bottom, bit3 left
    pub(crate) border_mask: u8,
    /// 2 bits per side (top, right, bottom, left from the low bits): 1 thin, 2 medium, 3 thick/double
    pub(crate) border_weight: u8,
    /// 0 = default (theme) font, otherwise an id for foglio_font_name_by_id
    pub(crate) font_id: u8,
    /// top, right, bottom, left — 0xRRGGBB or NO_COLOR (automatic)
    pub(crate) border_colors: [u32; 4],
}

#[repr(C)]
pub struct FoglioViewport {
    pub(crate) cells: *const FoglioCell,
    pub(crate) count: usize,
    pub(crate) text: *const u8,
    pub(crate) text_len: usize,
}

#[repr(C)]
pub(crate) struct ViewportOwned {
    pub(crate) header: FoglioViewport,
    pub(crate) _cells: Vec<FoglioCell>,
    pub(crate) _text: Vec<u8>,
}

#[derive(Clone, Copy)]
pub(crate) struct StyleInfo {
    pub(crate) align: u8,
    pub(crate) bold: u8,
    pub(crate) italic: u8,
    pub(crate) fg: u32,
    pub(crate) bg: u32,
    pub(crate) font_size: u8,
    pub(crate) underline: u8,
    pub(crate) strike: u8,
    pub(crate) wrap: u8,
    pub(crate) valign: u8,
    pub(crate) border_mask: u8,
    pub(crate) border_weight: u8,
    pub(crate) border_colors: [u32; 4],
    pub(crate) font_id: u8,
}

pub struct FoglioBook {
    pub(crate) model: UserModel<'static>,
    pub(crate) style_cache: HashMap<i32, StyleInfo>,
    /// Interned explicit font names (id = index + 1).
    pub(crate) font_names: Vec<String>,
}

// ---------- helpers ----------

pub(crate) fn guard<T>(default: T, f: impl FnOnce() -> T) -> T {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or(default)
}

pub(crate) unsafe fn cstr<'a>(p: *const c_char) -> Option<&'a str> {
    if p.is_null() {
        return None;
    }
    CStr::from_ptr(p).to_str().ok()
}

pub(crate) fn to_c(s: String) -> *mut c_char {
    CString::new(s.replace('\0', "")).map(|c| c.into_raw()).unwrap_or(ptr::null_mut())
}

pub(crate) unsafe fn write_err(err_out: *mut *mut c_char, msg: String) {
    if !err_out.is_null() {
        *err_out = to_c(msg);
    }
}

pub(crate) fn rc(r: Result<(), String>) -> i32 {
    if r.is_ok() {
        0
    } else {
        -1
    }
}

pub(crate) fn area(sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32) -> Area {
    let (r0, r1) = (r0.min(r1), r0.max(r1));
    let (c0, c1) = (c0.min(c1), c0.max(c1));
    Area { sheet, row: r0, column: c0, width: c1 - c0 + 1, height: r1 - r0 + 1 }
}

pub(crate) fn parse_rgb(s: &str) -> u32 {
    let h = s.trim_start_matches('#');
    if h.len() == 6 {
        u32::from_str_radix(h, 16).unwrap_or(NO_COLOR)
    } else {
        NO_COLOR
    }
}

pub(crate) fn book<'a>(b: *mut FoglioBook) -> Option<&'a mut FoglioBook> {
    unsafe { b.as_mut() }
}
pub(crate) fn book_ref<'a>(b: *const FoglioBook) -> Option<&'a FoglioBook> {
    unsafe { b.as_ref() }
}

impl FoglioBook {
    pub(crate) fn wrap(model: UserModel<'static>) -> *mut FoglioBook {
        Box::into_raw(Box::new(FoglioBook { model, style_cache: HashMap::new(), font_names: Vec::new() }))
    }

    /// Theme fonts (and the Office defaults) render with the system font: id 0.
    fn font_id(&mut self, f: &ironcalc::base::types::Font) -> u8 {
        use ironcalc::base::types::FontScheme;
        let n = f.name.trim();
        if f.scheme != FontScheme::None || n.is_empty() || ["calibri", "aptos", "aptos narrow", "calibri light"].contains(&n.to_lowercase().as_str()) {
            return 0;
        }
        if let Some(i) = self.font_names.iter().position(|x| x == n) {
            return (i + 1).min(255) as u8;
        }
        if self.font_names.len() >= 254 {
            return 0;
        }
        self.font_names.push(n.to_string());
        self.font_names.len() as u8
    }

    pub(crate) fn style_info(&mut self, sheet: u32, row: i32, col: i32) -> StyleInfo {
        let model: &Model = self.model.get_model();
        let has_cf = model
            .workbook
            .worksheets
            .get(sheet as usize)
            .map(|w| !w.conditional_formatting.is_empty())
            .unwrap_or(false);
        if has_cf {
            // Conditional formatting depends on the value: no caching by style index.
            if let Ok(ext) = self.model.get_extended_cell_style(sheet, row, col) {
                let mut info = ui::style_to_info(&ext.style, &self.model.get_model().workbook.theme);
                info.font_id = self.font_id(&ext.style.font);
                return info;
            }
        }
        let idx = model.get_cell_style_index(sheet, row, col).unwrap_or(0);
        if let Some(s) = self.style_cache.get(&idx) {
            return *s;
        }
        let st = model.get_style_for_cell(sheet, row, col).unwrap_or_default();
        let mut info = ui::style_to_info(&st, &model.workbook.theme);
        info.font_id = self.font_id(&st.font);
        self.style_cache.insert(idx, info);
        info
    }
}

/// Name for a font id from FoglioCell.font_id (NULL for 0/unknown).
#[no_mangle]
pub extern "C" fn foglio_font_name_by_id(b: *const FoglioBook, id: u8) -> *mut c_char {
    let Some(b) = book_ref(b) else { return ptr::null_mut() };
    if id == 0 {
        return ptr::null_mut();
    }
    b.font_names.get(id as usize - 1).map(|n| to_c(n.clone())).unwrap_or(ptr::null_mut())
}

// ---------- lifecycle ----------

#[no_mangle]
pub extern "C" fn foglio_new() -> *mut FoglioBook {
    let (locale, language, tz) = settings();
    guard(ptr::null_mut(), || match UserModel::new_empty("Workbook1", locale, tz, language) {
        Ok(m) => FoglioBook::wrap(m),
        Err(_) => ptr::null_mut(),
    })
}

#[no_mangle]
pub unsafe extern "C" fn foglio_open_xlsx(path: *const c_char, err_out: *mut *mut c_char) -> *mut FoglioBook {
    let Some(path) = cstr(path) else {
        write_err(err_out, "invalid path".into());
        return ptr::null_mut();
    };
    let result = catch_unwind(|| ironcalc::import::load_from_xlsx(path, "en", "UTC", "en"));
    match result {
        Ok(Ok(model)) => FoglioBook::wrap(UserModel::from_model(model)),
        Ok(Err(e)) => {
            write_err(err_out, format!("{e:?}"));
            ptr::null_mut()
        }
        Err(_) => {
            write_err(err_out, "engine panicked while reading the file".into());
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn foglio_save_xlsx(b: *mut FoglioBook, path: *const c_char, err_out: *mut *mut c_char) -> i32 {
    let (Some(b), Some(path)) = (book(b), cstr(path)) else { return -1 };
    // IronCalc refuses to overwrite: write to a temp file and atomically replace.
    let tmp = format!("{path}.foglio-tmp.xlsx");
    let _ = std::fs::remove_file(&tmp);
    let res = catch_unwind(AssertUnwindSafe(|| ironcalc::export::save_to_xlsx(b.model.get_model(), &tmp)));
    match res {
        Ok(Ok(())) => match std::fs::rename(&tmp, path) {
            Ok(()) => 0,
            Err(e) => {
                write_err(err_out, e.to_string());
                -1
            }
        },
        Ok(Err(e)) => {
            write_err(err_out, format!("{e:?}"));
            -1
        }
        Err(_) => {
            write_err(err_out, "engine panicked while saving".into());
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn foglio_free(b: *mut FoglioBook) {
    if !b.is_null() {
        drop(Box::from_raw(b));
    }
}

#[no_mangle]
pub unsafe extern "C" fn foglio_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

// ---------- sheets ----------

#[no_mangle]
pub extern "C" fn foglio_sheet_count(b: *const FoglioBook) -> u32 {
    book_ref(b).map(|b| b.model.get_worksheets_properties().len() as u32).unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn foglio_sheet_name(b: *const FoglioBook, sheet: u32) -> *mut c_char {
    let Some(b) = book_ref(b) else { return ptr::null_mut() };
    let props = b.model.get_worksheets_properties();
    props.get(sheet as usize).map(|p| to_c(p.name.clone())).unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn foglio_add_sheet(b: *mut FoglioBook) -> i32 {
    let Some(b) = book(b) else { return -1 };
    guard(-1, || rc(b.model.new_sheet()))
}

// ---------- cells ----------

#[no_mangle]
pub unsafe extern "C" fn foglio_set_input(b: *mut FoglioBook, sheet: u32, row: i32, col: i32, s: *const c_char) -> i32 {
    let (Some(b), Some(s)) = (book(b), cstr(s)) else { return -1 };
    guard(-1, || rc(b.model.set_user_input(sheet, row, col, s)))
}

#[no_mangle]
pub extern "C" fn foglio_get_input(b: *const FoglioBook, sheet: u32, row: i32, col: i32) -> *mut c_char {
    let Some(b) = book_ref(b) else { return ptr::null_mut() };
    guard(ptr::null_mut(), || to_c(b.model.get_cell_content(sheet, row, col).unwrap_or_default()))
}

#[no_mangle]
pub extern "C" fn foglio_get_formatted(b: *const FoglioBook, sheet: u32, row: i32, col: i32) -> *mut c_char {
    let Some(b) = book_ref(b) else { return ptr::null_mut() };
    guard(ptr::null_mut(), || to_c(b.model.get_formatted_cell_value(sheet, row, col).unwrap_or_default()))
}

#[no_mangle]
pub extern "C" fn foglio_clear_range(b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32) -> i32 {
    let Some(b) = book(b) else { return -1 };
    guard(-1, || rc(b.model.range_clear_contents(&area(sheet, r0, c0, r1, c1))))
}

#[no_mangle]
pub unsafe extern "C" fn foglio_set_style(
    b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32,
    path: *const c_char, value: *const c_char,
) -> i32 {
    let (Some(b), Some(path), Some(value)) = (book(b), cstr(path), cstr(value)) else { return -1 };
    let r = guard(-1, || rc(b.model.update_range_style(&area(sheet, r0, c0, r1, c1), path, value)));
    b.style_cache.clear();
    r
}

#[no_mangle]
pub extern "C" fn foglio_autofill(
    b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32, to_row: i32, to_col: i32,
) -> i32 {
    let Some(b) = book(b) else { return -1 };
    let src = area(sheet, r0, c0, r1, c1);
    guard(-1, || {
        if to_row > 0 {
            rc(b.model.auto_fill_rows(&src, to_row))
        } else if to_col > 0 {
            rc(b.model.auto_fill_columns(&src, to_col))
        } else {
            -1
        }
    })
}

#[no_mangle]
pub unsafe extern "C" fn foglio_paste_tsv(b: *mut FoglioBook, sheet: u32, row: i32, col: i32, tsv: *const c_char) -> i32 {
    let (Some(b), Some(tsv)) = (book(b), cstr(tsv)) else { return -1 };
    guard(-1, || {
        b.model.pause_evaluation();
        let mut status = 0;
        for (dr, line) in tsv.trim_end_matches(['\n', '\r']).split('\n').enumerate() {
            for (dc, value) in line.trim_end_matches('\r').split('\t').enumerate() {
                if b.model.set_user_input(sheet, row + dr as i32, col + dc as i32, value).is_err() {
                    status = -1;
                }
            }
        }
        b.model.resume_evaluation();
        b.model.evaluate();
        status
    })
}

// ---------- undo ----------

#[no_mangle]
pub extern "C" fn foglio_undo(b: *mut FoglioBook) -> i32 {
    let Some(b) = book(b) else { return -1 };
    let r = guard(-1, || rc(b.model.undo()));
    b.style_cache.clear();
    r
}
#[no_mangle]
pub extern "C" fn foglio_redo(b: *mut FoglioBook) -> i32 {
    let Some(b) = book(b) else { return -1 };
    let r = guard(-1, || rc(b.model.redo()));
    b.style_cache.clear();
    r
}
#[no_mangle]
pub extern "C" fn foglio_can_undo(b: *const FoglioBook) -> bool {
    book_ref(b).map(|b| b.model.can_undo()).unwrap_or(false)
}
#[no_mangle]
pub extern "C" fn foglio_can_redo(b: *const FoglioBook) -> bool {
    book_ref(b).map(|b| b.model.can_redo()).unwrap_or(false)
}

/// Full recalculation of every formula (F9 / "Calculate Now"). Returns elapsed microseconds.
#[no_mangle]
pub extern "C" fn foglio_evaluate_us(b: *mut FoglioBook) -> u64 {
    let Some(b) = book(b) else { return 0 };
    let t = Instant::now();
    guard((), || b.model.evaluate_full());
    b.style_cache.clear();
    t.elapsed().as_micros() as u64
}
