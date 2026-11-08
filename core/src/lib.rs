//! foglio_core: a thin C ABI over IronCalc's UserModel, for the Swift/AppKit shell.
//! See include/foglio_core.h for the contract.

use std::collections::HashMap;
use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
use std::time::Instant;

use ironcalc::base::expressions::types::Area;
use ironcalc::base::types::{CellType, Color, HorizontalAlignment};
use ironcalc::base::{Model, UserModel};

const NO_COLOR: u32 = 0xFFFF_FFFF;

#[repr(C)]
pub struct FoglioCell {
    row: i32,
    col: i32,
    text_off: u32,
    text_len: u32,
    kind: u8,
    align: u8,
    bold: u8,
    italic: u8,
    fg: u32,
    bg: u32,
}

#[repr(C)]
pub struct FoglioViewport {
    cells: *const FoglioCell,
    count: usize,
    text: *const u8,
    text_len: usize,
}

#[repr(C)]
struct ViewportOwned {
    header: FoglioViewport,
    _cells: Vec<FoglioCell>,
    _text: Vec<u8>,
}

#[derive(Clone, Copy)]
pub(crate) struct StyleInfo {
    align: u8,
    bold: u8,
    italic: u8,
    fg: u32,
    bg: u32,
}

pub struct FoglioBook {
    pub(crate) model: UserModel<'static>,
    pub(crate) style_cache: HashMap<i32, StyleInfo>,
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

fn rc(r: Result<(), String>) -> i32 {
    if r.is_ok() {
        0
    } else {
        -1
    }
}

fn area(sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32) -> Area {
    let (r0, r1) = (r0.min(r1), r0.max(r1));
    let (c0, c1) = (c0.min(c1), c0.max(c1));
    Area { sheet, row: r0, column: c0, width: c1 - c0 + 1, height: r1 - r0 + 1 }
}

fn parse_rgb(s: &str) -> u32 {
    let h = s.trim_start_matches('#');
    if h.len() == 6 {
        u32::from_str_radix(h, 16).unwrap_or(NO_COLOR)
    } else {
        NO_COLOR
    }
}

fn book<'a>(b: *mut FoglioBook) -> Option<&'a mut FoglioBook> {
    unsafe { b.as_mut() }
}
fn book_ref<'a>(b: *const FoglioBook) -> Option<&'a FoglioBook> {
    unsafe { b.as_ref() }
}

impl FoglioBook {
    pub(crate) fn wrap(model: UserModel<'static>) -> *mut FoglioBook {
        Box::into_raw(Box::new(FoglioBook { model, style_cache: HashMap::new() }))
    }

    fn style_info(&mut self, sheet: u32, row: i32, col: i32) -> StyleInfo {
        let model: &Model = self.model.get_model();
        let idx = model.get_cell_style_index(sheet, row, col).unwrap_or(0);
        if let Some(s) = self.style_cache.get(&idx) {
            return *s;
        }
        let info = match model.get_style_for_cell(sheet, row, col) {
            Ok(st) => {
                let theme = &model.workbook.theme;
                let color = |c: &Color| match c {
                    Color::None => NO_COLOR,
                    other => parse_rgb(&other.to_rgb(theme)),
                };
                let align = match st.alignment.as_ref().map(|a| &a.horizontal) {
                    Some(HorizontalAlignment::Left) => 1,
                    Some(HorizontalAlignment::Center) | Some(HorizontalAlignment::CenterContinuous) => 2,
                    Some(HorizontalAlignment::Right) => 3,
                    _ => 0,
                };
                let fg = color(&st.font.color);
                StyleInfo {
                    align,
                    bold: st.font.b as u8,
                    italic: st.font.i as u8,
                    // Black is the default font colour; report it as "default" so dark mode works.
                    fg: if fg == 0x000000 { NO_COLOR } else { fg },
                    bg: color(&st.fill.color),
                }
            }
            Err(_) => StyleInfo { align: 0, bold: 0, italic: 0, fg: NO_COLOR, bg: NO_COLOR },
        };
        self.style_cache.insert(idx, info);
        info
    }
}

// ---------- lifecycle ----------

#[no_mangle]
pub extern "C" fn foglio_new() -> *mut FoglioBook {
    guard(ptr::null_mut(), || match UserModel::new_empty("Workbook1", "en", "UTC", "en") {
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

// ---------- viewport (hot path) ----------

#[no_mangle]
pub extern "C" fn foglio_viewport(b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32) -> *mut FoglioViewport {
    let Some(b) = book(b) else { return ptr::null_mut() };
    guard(ptr::null_mut(), || {
        // Collect coordinates first (immutable borrow of the sheet), then format.
        let coords: Vec<(i32, i32)> = {
            let model = b.model.get_model();
            let Some(ws) = model.workbook.worksheets.get(sheet as usize) else { return ptr::null_mut() };
            let mut v = Vec::new();
            for row in r0..=r1 {
                for (col, _) in ws.sheet_data.cells_in_row_between(row, c0, c1) {
                    v.push((row, col));
                }
            }
            v
        };
        let mut cells = Vec::with_capacity(coords.len());
        let mut text: Vec<u8> = Vec::with_capacity(coords.len() * 8);
        for (row, col) in coords {
            let s = b.model.get_formatted_cell_value(sheet, row, col).unwrap_or_default();
            let kind = match b.model.get_cell_type(sheet, row, col) {
                Ok(CellType::Number) => 1,
                Ok(CellType::LogicalValue) => 2,
                Ok(CellType::ErrorValue) => 3,
                _ => 0,
            };
            let st = b.style_info(sheet, row, col);
            let off = text.len() as u32;
            text.extend_from_slice(s.as_bytes());
            cells.push(FoglioCell {
                row, col, text_off: off, text_len: s.len() as u32,
                kind, align: st.align, bold: st.bold, italic: st.italic, fg: st.fg, bg: st.bg,
            });
        }
        let mut owned = Box::new(ViewportOwned {
            header: FoglioViewport { cells: ptr::null(), count: 0, text: ptr::null(), text_len: 0 },
            _cells: cells,
            _text: text,
        });
        owned.header = FoglioViewport {
            cells: owned._cells.as_ptr(),
            count: owned._cells.len(),
            text: owned._text.as_ptr(),
            text_len: owned._text.len(),
        };
        // `header` is the first field, so a pointer to the box is a pointer to the header.
        Box::into_raw(owned) as *mut FoglioViewport
    })
}

#[no_mangle]
pub unsafe extern "C" fn foglio_viewport_free(v: *mut FoglioViewport) {
    if !v.is_null() {
        drop(Box::from_raw(v as *mut ViewportOwned));
    }
}

#[no_mangle]
pub extern "C" fn foglio_evaluate_us(b: *mut FoglioBook) -> u64 {
    let Some(b) = book(b) else { return 0 };
    let t = Instant::now();
    b.model.evaluate();
    t.elapsed().as_micros() as u64
}
