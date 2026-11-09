//! UI-facing C ABI: viewport, layout, structure edits, clipboard, sort, find, completion.
//! Declared in include/foglio_ui.h.

use std::collections::HashMap;
use std::ffi::c_char;
use std::ptr;
use std::sync::Mutex;

use ironcalc::base::cell::CellValue;
use ironcalc::base::types::{BorderStyle, CellType, Color, HorizontalAlignment, Style, VerticalAlignment};
use ironcalc::base::{BorderArea, ClipboardData};
use serde_json::{json, Value};

use crate::{
    area, book, book_ref, cstr, guard, parse_rgb, rc, to_c, FoglioBook, FoglioCell, FoglioViewport, StyleInfo,
    ViewportOwned, NO_COLOR,
};

type Theme = ironcalc::base::types::Theme;

pub(crate) fn style_to_info(st: &Style, theme: &Theme) -> StyleInfo {
    let color = |c: &Color| match c {
        Color::None => NO_COLOR,
        other => parse_rgb(&other.to_rgb(theme)),
    };
    let (align, valign, wrap) = match &st.alignment {
        Some(a) => (
            match a.horizontal {
                HorizontalAlignment::Left => 1,
                HorizontalAlignment::Center | HorizontalAlignment::CenterContinuous => 2,
                HorizontalAlignment::Right => 3,
                _ => 0,
            },
            match a.vertical {
                VerticalAlignment::Center => 1,
                VerticalAlignment::Top => 2,
                _ => 0,
            },
            a.wrap_text as u8,
        ),
        None => (0, 0, 0),
    };
    let (mut mask, mut weight, mut colors) = (0u8, 0u8, [NO_COLOR; 4]);
    for (i, item) in [&st.border.top, &st.border.right, &st.border.bottom, &st.border.left].into_iter().enumerate() {
        if let Some(b) = item {
            mask |= 1 << i;
            let w: u8 = match b.style {
                BorderStyle::Medium | BorderStyle::MediumDashed | BorderStyle::MediumDashDot | BorderStyle::MediumDashDotDot => 2,
                BorderStyle::Thick | BorderStyle::Double => 3,
                _ => 1,
            };
            weight |= w << (2 * i);
            colors[i] = color(&b.color);
        }
    }
    let fg = color(&st.font.color);
    StyleInfo {
        align,
        bold: st.font.b as u8,
        italic: st.font.i as u8,
        // Black is the default font colour; report it as "default" so dark mode works.
        fg: if fg == 0 { NO_COLOR } else { fg },
        bg: color(&st.fill.color),
        font_size: st.font.sz.clamp(1, 255) as u8,
        underline: st.font.u as u8,
        strike: st.font.strike as u8,
        wrap,
        valign,
        border_mask: mask,
        border_weight: weight,
        border_colors: colors,
    }
}

fn kind_of(b: &FoglioBook, sheet: u32, row: i32, col: i32) -> u8 {
    match b.model.get_cell_type(sheet, row, col) {
        Ok(CellType::Number) => 1,
        Ok(CellType::LogicalValue) => 2,
        Ok(CellType::ErrorValue) => 3,
        _ => 0,
    }
}

// ---------- viewport (hot path) ----------

#[no_mangle]
pub extern "C" fn foglio_viewport(b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32) -> *mut FoglioViewport {
    let Some(b) = book(b) else { return ptr::null_mut() };
    guard(ptr::null_mut(), || {
        let coords: Vec<(i32, i32)> = {
            let model = b.model.get_model();
            let Some(ws) = model.workbook.worksheets.get(sheet as usize) else { return ptr::null_mut() };
            let dim = ws.dimension();
            let (r0, r1) = (r0.max(dim.min_row), r1.min(dim.max_row));
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
            let kind = kind_of(b, sheet, row, col);
            let st = b.style_info(sheet, row, col);
            let off = text.len() as u32;
            text.extend_from_slice(s.as_bytes());
            cells.push(FoglioCell {
                row, col, text_off: off, text_len: s.len() as u32, kind,
                align: st.align, bold: st.bold, italic: st.italic, fg: st.fg, bg: st.bg,
                font_size: st.font_size, underline: st.underline, strike: st.strike, wrap: st.wrap,
                valign: st.valign, border_mask: st.border_mask, border_weight: st.border_weight, _pad: 0,
                border_colors: st.border_colors,
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
        Box::into_raw(owned) as *mut FoglioViewport
    })
}

#[no_mangle]
pub unsafe extern "C" fn foglio_viewport_free(v: *mut FoglioViewport) {
    if !v.is_null() {
        drop(Box::from_raw(v as *mut ViewportOwned));
    }
}

// ---------- style of one cell (toolbar state) ----------

#[repr(C)]
pub struct FoglioStyle {
    bold: u8,
    italic: u8,
    underline: u8,
    strike: u8,
    align: u8,
    valign: u8,
    wrap: u8,
    font_size: u8,
    fg: u32,
    bg: u32,
    num_fmt: *mut c_char,
}

#[no_mangle]
pub unsafe extern "C" fn foglio_style_at(b: *mut FoglioBook, sheet: u32, row: i32, col: i32, out: *mut FoglioStyle) -> i32 {
    let Some(b) = book(b) else { return -1 };
    if out.is_null() {
        return -1;
    }
    guard(-1, || {
        let Ok(st) = b.model.get_cell_style(sheet, row, col) else { return -1 };
        let i = style_to_info(&st, &b.model.get_model().workbook.theme);
        *out = FoglioStyle {
            bold: i.bold, italic: i.italic, underline: i.underline, strike: i.strike, align: i.align,
            valign: i.valign, wrap: i.wrap, font_size: i.font_size, fg: i.fg, bg: i.bg, num_fmt: to_c(st.num_fmt.clone()),
        };
        0
    })
}

// ---------- layout ----------

#[repr(C)]
pub struct FoglioAxisEntry {
    index: i32,
    hidden: u8,
    size: f64,
}

#[repr(C)]
pub struct FoglioLayout {
    cols: *const FoglioAxisEntry,
    ncols: usize,
    rows: *const FoglioAxisEntry,
    nrows: usize,
    default_col: f64,
    default_row: f64,
    frozen_rows: i32,
    frozen_cols: i32,
    show_grid: u8,
    max_row: i32,
    max_col: i32,
}

#[repr(C)]
struct LayoutOwned {
    header: FoglioLayout,
    cols: Vec<FoglioAxisEntry>,
    rows: Vec<FoglioAxisEntry>,
}

const DEFAULT_COL_PX: f64 = 90.0;
const DEFAULT_ROW_PX: f64 = 25.0;

#[no_mangle]
pub extern "C" fn foglio_layout(b: *const FoglioBook, sheet: u32) -> *mut FoglioLayout {
    let Some(b) = book_ref(b) else { return ptr::null_mut() };
    guard(ptr::null_mut(), || {
        let model = b.model.get_model();
        let Some(ws) = model.workbook.worksheets.get(sheet as usize) else { return ptr::null_mut() };
        let mut cols = Vec::new();
        for c in &ws.cols {
            for i in c.min.max(1)..=c.max.min(16_384) {
                let w = model.get_column_width(sheet, i).unwrap_or(DEFAULT_COL_PX);
                if c.hidden || (w - DEFAULT_COL_PX).abs() > 0.01 {
                    cols.push(FoglioAxisEntry { index: i, hidden: c.hidden as u8, size: if c.hidden { 0.0 } else { w } });
                }
            }
        }
        cols.sort_by_key(|e| e.index);
        cols.dedup_by_key(|e| e.index);
        let mut rows = Vec::new();
        for r in &ws.rows {
            if r.hidden || r.custom_height {
                let h = model.get_row_height(sheet, r.r).unwrap_or(DEFAULT_ROW_PX);
                if r.hidden || (h - DEFAULT_ROW_PX).abs() > 0.01 {
                    rows.push(FoglioAxisEntry { index: r.r, hidden: r.hidden as u8, size: if r.hidden { 0.0 } else { h } });
                }
            }
        }
        rows.sort_by_key(|e| e.index);
        rows.dedup_by_key(|e| e.index);
        let dim = ws.dimension();
        let mut owned = Box::new(LayoutOwned {
            header: FoglioLayout {
                cols: ptr::null(), ncols: 0, rows: ptr::null(), nrows: 0,
                default_col: DEFAULT_COL_PX, default_row: DEFAULT_ROW_PX,
                frozen_rows: ws.frozen_rows, frozen_cols: ws.frozen_columns, show_grid: ws.show_grid_lines as u8,
                max_row: dim.max_row, max_col: dim.max_column,
            },
            cols,
            rows,
        });
        owned.header.cols = owned.cols.as_ptr();
        owned.header.ncols = owned.cols.len();
        owned.header.rows = owned.rows.as_ptr();
        owned.header.nrows = owned.rows.len();
        Box::into_raw(owned) as *mut FoglioLayout
    })
}

#[no_mangle]
pub unsafe extern "C" fn foglio_layout_free(l: *mut FoglioLayout) {
    if !l.is_null() {
        drop(Box::from_raw(l as *mut LayoutOwned));
    }
}

#[no_mangle]
pub extern "C" fn foglio_set_col_width(b: *mut FoglioBook, sheet: u32, c0: i32, c1: i32, px: f64) -> i32 {
    let Some(b) = book(b) else { return -1 };
    guard(-1, || rc(b.model.set_columns_width(sheet, c0.min(c1), c0.max(c1), px)))
}

#[no_mangle]
pub extern "C" fn foglio_set_row_height(b: *mut FoglioBook, sheet: u32, r0: i32, r1: i32, px: f64) -> i32 {
    let Some(b) = book(b) else { return -1 };
    guard(-1, || rc(b.model.set_rows_height(sheet, r0.min(r1), r0.max(r1), px)))
}

#[no_mangle]
pub extern "C" fn foglio_set_hidden(b: *mut FoglioBook, sheet: u32, is_rows: bool, i0: i32, i1: i32, hidden: bool) -> i32 {
    let Some(b) = book(b) else { return -1 };
    guard(-1, || {
        if is_rows {
            rc(b.model.set_rows_hidden(sheet, i0.min(i1), i0.max(i1), hidden))
        } else {
            rc(b.model.set_columns_hidden(sheet, i0.min(i1), i0.max(i1), hidden))
        }
    })
}

#[no_mangle]
pub extern "C" fn foglio_set_frozen(b: *mut FoglioBook, sheet: u32, rows: i32, cols: i32) -> i32 {
    let Some(b) = book(b) else { return -1 };
    guard(-1, || {
        let a = b.model.set_frozen_rows_count(sheet, rows.max(0));
        let c = b.model.set_frozen_columns_count(sheet, cols.max(0));
        rc(a.and(c))
    })
}

#[no_mangle]
pub extern "C" fn foglio_set_show_grid(b: *mut FoglioBook, sheet: u32, show: bool) -> i32 {
    let Some(b) = book(b) else { return -1 };
    guard(-1, || rc(b.model.set_show_grid_lines(sheet, show)))
}

// ---------- rows / columns ----------

/// op: 0 insert rows, 1 delete rows, 2 insert columns, 3 delete columns
#[no_mangle]
pub extern "C" fn foglio_structure(b: *mut FoglioBook, sheet: u32, op: i32, index: i32, count: i32) -> i32 {
    let Some(b) = book(b) else { return -1 };
    let r = guard(-1, || {
        rc(match op {
            0 => b.model.insert_rows(sheet, index, count),
            1 => b.model.delete_rows(sheet, index, count),
            2 => b.model.insert_columns(sheet, index, count),
            3 => b.model.delete_columns(sheet, index, count),
            _ => Err("bad op".into()),
        })
    });
    b.style_cache.clear();
    r
}

// ---------- sheets ----------

/// op: 0 rename(name), 1 delete, 2 move to `arg`, 3 duplicate, 4 hide, 5 unhide
#[no_mangle]
pub unsafe extern "C" fn foglio_sheet_op(b: *mut FoglioBook, sheet: u32, op: i32, arg: u32, name: *const c_char) -> i32 {
    let Some(b) = book(b) else { return -1 };
    let name = cstr(name).unwrap_or("").to_string();
    guard(-1, || {
        rc(match op {
            0 => b.model.rename_sheet(sheet, &name),
            1 => b.model.delete_sheet(sheet),
            2 => b.model.move_sheet(sheet, arg),
            3 => b.model.duplicate_sheet(sheet),
            4 => b.model.hide_sheet(sheet),
            5 => b.model.unhide_sheet(sheet),
            _ => Err("bad op".into()),
        })
    })
}

/// 1 if the sheet is hidden.
#[no_mangle]
pub extern "C" fn foglio_sheet_hidden(b: *const FoglioBook, sheet: u32) -> i32 {
    let Some(b) = book_ref(b) else { return 0 };
    b.model
        .get_worksheets_properties()
        .get(sheet as usize)
        .map(|p| (p.state != "visible") as i32)
        .unwrap_or(0)
}

// ---------- merges ----------

/// Returns 4*n ints (row, col, width, height) — free with foglio_ints_free(ptr, 4*n).
#[no_mangle]
pub unsafe extern "C" fn foglio_merges(b: *const FoglioBook, sheet: u32, out_n: *mut usize) -> *mut i32 {
    let Some(b) = book_ref(b) else { return ptr::null_mut() };
    let list = b.model.get_merged_cells(sheet).unwrap_or_default();
    let mut v: Vec<i32> = Vec::with_capacity(list.len() * 4);
    for m in &list {
        v.extend_from_slice(&[m.row, m.column, m.width, m.height]);
    }
    if !out_n.is_null() {
        *out_n = list.len();
    }
    let mut v = v.into_boxed_slice();
    let p = v.as_mut_ptr();
    std::mem::forget(v);
    p
}

#[no_mangle]
pub unsafe extern "C" fn foglio_ints_free(p: *mut i32, len: usize) {
    if !p.is_null() {
        drop(Box::from_raw(std::slice::from_raw_parts_mut(p, len)));
    }
}

/// mode: 0 unmerge, 1 merge, 2 merge & center
#[no_mangle]
pub extern "C" fn foglio_merge(b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32, mode: i32) -> i32 {
    let Some(b) = book(b) else { return -1 };
    let a = area(sheet, r0, c0, r1, c1);
    let r = guard(-1, || {
        rc(match mode {
            0 => b.model.unmerge_cells(&a),
            1 => b.model.merge_cells(&a),
            _ => b.model.merge_cells_center(&a),
        })
    });
    b.style_cache.clear();
    r
}

// ---------- borders ----------

/// kind: All, Inner, Outer, Top, Right, Bottom, Left, None. style: thin, medium, thick, double, dotted…
#[no_mangle]
pub unsafe extern "C" fn foglio_set_border(
    b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32,
    kind: *const c_char, style: *const c_char, color: *const c_char,
) -> i32 {
    let (Some(b), Some(kind), Some(style)) = (book(b), cstr(kind), cstr(style)) else { return -1 };
    let color = cstr(color).unwrap_or("#000000");
    let r = guard(-1, || {
        let v = json!({"item": {"style": style, "color": color}, "type": kind});
        let Ok(ba) = serde_json::from_value::<BorderArea>(v) else { return -1 };
        rc(b.model.set_area_with_border(&area(sheet, r0, c0, r1, c1), &ba))
    });
    b.style_cache.clear();
    r
}

#[no_mangle]
pub extern "C" fn foglio_clear_formats(b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32) -> i32 {
    let Some(b) = book(b) else { return -1 };
    let r = guard(-1, || rc(b.model.range_clear_formatting(&area(sheet, r0, c0, r1, c1))));
    b.style_cache.clear();
    r
}

// ---------- clipboard (formulas + styles, Excel-like relative adjustment) ----------

struct Clip {
    token: u64,
    book: usize,
    sheet: u32,
    range: (i32, i32, i32, i32),
    data: Value,
}
static CLIP: Mutex<Option<Clip>> = Mutex::new(None);
static TOKEN: Mutex<u64> = Mutex::new(0);

fn select(b: &mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32) -> Result<(), String> {
    b.model.set_selected_sheet(sheet)?;
    b.model.set_selected_cell(r0, c0)?;
    b.model.set_selected_range(r0, c0, r1, c1)
}

/// Copies a range. Returns tab-separated text (for other apps) and stores the rich copy internally.
/// `out_token` receives an id the UI puts on the pasteboard to recognise its own copy.
#[no_mangle]
pub unsafe extern "C" fn foglio_copy(b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32, out_token: *mut u64) -> *mut c_char {
    let addr = b as usize;
    let Some(b) = book(b) else { return ptr::null_mut() };
    guard(ptr::null_mut(), || {
        if select(b, sheet, r0.min(r1), c0.min(c1), r0.max(r1), c0.max(c1)).is_err() {
            return ptr::null_mut();
        }
        let Ok(clip) = b.model.copy_to_clipboard() else { return ptr::null_mut() };
        let Ok(v) = serde_json::to_value(&clip) else { return ptr::null_mut() };
        let csv = v.get("csv").and_then(|c| c.as_str()).unwrap_or("").to_string();
        let range = v.get("range").and_then(|r| serde_json::from_value::<(i32, i32, i32, i32)>(r.clone()).ok());
        let Some(range) = range else { return ptr::null_mut() };
        let mut t = TOKEN.lock().unwrap();
        *t += 1;
        let token = *t;
        *CLIP.lock().unwrap() = Some(Clip { token, book: addr, sheet, range, data: v.get("data").cloned().unwrap_or(Value::Null) });
        if !out_token.is_null() {
            *out_token = token;
        }
        to_c(csv)
    })
}

/// Pastes the internal copy identified by `token` at the target range. Returns -2 if the token is stale.
#[no_mangle]
pub extern "C" fn foglio_paste_internal(b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32, token: u64, is_cut: bool) -> i32 {
    let addr = b as usize;
    let Some(b) = book(b) else { return -1 };
    let r = guard(-1, || {
        let mut guard_clip = CLIP.lock().unwrap();
        let Some(clip) = guard_clip.as_ref() else { return -2 };
        if clip.token != token {
            return -2;
        }
        let Ok(data) = serde_json::from_value::<ClipboardData>(clip.data.clone()) else { return -1 };
        // Cutting from another workbook would clear the wrong sheet: degrade to copy.
        let cut = is_cut && clip.book == addr;
        if select(b, sheet, r0.min(r1), c0.min(c1), r0.max(r1), c0.max(c1)).is_err() {
            return -1;
        }
        let res = rc(b.model.paste_from_clipboard(clip.sheet, clip.range, &data, cut));
        if cut && res == 0 {
            *guard_clip = None; // Excel: a cut can be pasted once
        }
        res
    });
    b.style_cache.clear();
    r
}

/// Pastes tab-separated text (from another app) at (row, col) as one undo step.
#[no_mangle]
pub unsafe extern "C" fn foglio_paste_text(b: *mut FoglioBook, sheet: u32, row: i32, col: i32, tsv: *const c_char) -> i32 {
    let (Some(b), Some(tsv)) = (book(b), cstr(tsv)) else { return -1 };
    guard(-1, || {
        let _ = select(b, sheet, row, col, row, col);
        rc(b.model.paste_csv_string(&area(sheet, row, col, row, col), tsv))
    })
}

// ---------- sort ----------

fn sort_key(v: &CellValue) -> (u8, f64, String) {
    match v {
        CellValue::Number(n) => (0, *n, String::new()),
        CellValue::String(s) => (1, 0.0, s.to_lowercase()),
        CellValue::Boolean(x) => (2, *x as u8 as f64, String::new()),
        CellValue::None => (9, 0.0, String::new()),
    }
}

/// Sorts the rows of the range by `key_col` (absolute column). Blanks always go last, like Excel.
/// Formulas move with their row (relative references adjusted), styles move too. One undo step.
#[no_mangle]
pub extern "C" fn foglio_sort(b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32, key_col: i32, ascending: bool) -> i32 {
    let Some(b) = book(b) else { return -1 };
    let r = guard(-1, || {
        let (r0, r1, c0, c1) = (r0.min(r1), r0.max(r1), c0.min(c1), c0.max(c1));
        let model = b.model.get_model();
        let Some(ws) = model.workbook.worksheets.get(sheet as usize) else { return -1 };
        let dim = ws.dimension();
        let r1 = r1.min(dim.max_row);
        let c1 = c1.min(dim.max_column);
        if r1 <= r0 || c1 < c0 {
            return 0;
        }
        let mut order: Vec<(i32, (u8, f64, String))> = (r0..=r1)
            .map(|r| (r, sort_key(&model.get_cell_value_by_index(sheet, r, key_col).unwrap_or(CellValue::None))))
            .collect();
        order.sort_by(|a, b| {
            let (ka, kb) = (&a.1, &b.1);
            if ka.0 == 9 || kb.0 == 9 {
                return ka.0.cmp(&kb.0); // blanks last in both directions
            }
            let o = ka.0.cmp(&kb.0).then(ka.1.partial_cmp(&kb.1).unwrap_or(std::cmp::Ordering::Equal)).then(ka.2.cmp(&kb.2));
            if ascending { o } else { o.reverse() }
        });
        let mut data = serde_json::Map::new();
        for (i, (src, _)) in order.iter().enumerate() {
            let dst = r0 + i as i32;
            let mut row = serde_json::Map::new();
            for c in c0..=c1 {
                let text = match model.get_cell_formula(sheet, *src, c) {
                    Ok(Some(_)) => model.extend_to(sheet, *src, c, dst, c).unwrap_or_default(),
                    _ => b.model.get_cell_content(sheet, *src, c).unwrap_or_default(),
                };
                let style = b.model.get_cell_style(sheet, *src, c).unwrap_or_default();
                row.insert(c.to_string(), json!({"text": text, "is_spill": false, "style": style, "link": null}));
            }
            data.insert(dst.to_string(), Value::Object(row));
        }
        let Ok(data) = serde_json::from_value::<ClipboardData>(Value::Object(data)) else { return -1 };
        if select(b, sheet, r0, c0, r1, c1).is_err() {
            return -1;
        }
        rc(b.model.paste_from_clipboard(sheet, (r0, c0, r1, c1), &data, false))
    });
    b.style_cache.clear();
    r
}

// ---------- navigation helpers ----------

fn filled(b: &FoglioBook, sheet: u32, r: i32, c: i32) -> bool {
    !matches!(b.model.get_model().get_cell_value_by_index(sheet, r, c), Ok(CellValue::None) | Err(_))
}

/// Excel's "current region": the contiguous block of data around (row, col).
#[no_mangle]
pub unsafe extern "C" fn foglio_current_region(b: *const FoglioBook, sheet: u32, row: i32, col: i32, out: *mut i32) -> i32 {
    let Some(b) = book_ref(b) else { return -1 };
    if out.is_null() {
        return -1;
    }
    let (mut r0, mut c0, mut r1, mut c1) = (row, col, row, col);
    for _ in 0..10_000 {
        let mut grew = false;
        let (er0, ec0, er1, ec1) = ((r0 - 1).max(1), (c0 - 1).max(1), (r1 + 1).min(1_048_576), (c1 + 1).min(16_384));
        if er0 < r0 && (ec0..=ec1).any(|c| filled(b, sheet, er0, c)) { r0 = er0; grew = true; }
        if er1 > r1 && (ec0..=ec1).any(|c| filled(b, sheet, er1, c)) { r1 = er1; grew = true; }
        if ec0 < c0 && (er0..=er1).any(|r| filled(b, sheet, r, ec0)) { c0 = ec0; grew = true; }
        if ec1 > c1 && (er0..=er1).any(|r| filled(b, sheet, r, ec1)) { c1 = ec1; grew = true; }
        if !grew {
            break;
        }
    }
    let o = std::slice::from_raw_parts_mut(out, 4);
    o.copy_from_slice(&[r0, c0, r1, c1]);
    0
}

/// Ctrl/⌘+arrow: jump to the edge of the data region in direction (dr, dc).
#[no_mangle]
pub unsafe extern "C" fn foglio_jump(b: *const FoglioBook, sheet: u32, row: i32, col: i32, dr: i32, dc: i32, out: *mut i32) -> i32 {
    let Some(b) = book_ref(b) else { return -1 };
    if out.is_null() {
        return -1;
    }
    let dim = match b.model.get_model().workbook.worksheets.get(sheet as usize) {
        Some(ws) => ws.dimension(),
        None => return -1,
    };
    let (max_r, max_c) = (1_048_576, 16_384);
    let inside = |r: i32, c: i32| r >= 1 && c >= 1 && r <= max_r && c <= max_c;
    let (mut r, mut c) = (row, col);
    let next_filled = filled(b, sheet, r + dr, c + dc) && inside(r + dr, c + dc);
    if filled(b, sheet, r, c) && next_filled {
        while inside(r + dr, c + dc) && filled(b, sheet, r + dr, c + dc) {
            r += dr;
            c += dc;
        }
    } else {
        loop {
            if !inside(r + dr, c + dc) {
                break;
            }
            r += dr;
            c += dc;
            if filled(b, sheet, r, c) {
                break;
            }
            // Past the data: go straight to the sheet edge.
            if (dr > 0 && r > dim.max_row) || (dc > 0 && c > dim.max_column) {
                r = if dr > 0 { max_r } else { r };
                c = if dc > 0 { max_c } else { c };
                break;
            }
        }
    }
    let o = std::slice::from_raw_parts_mut(out, 2);
    o.copy_from_slice(&[r, c]);
    0
}

// ---------- status bar ----------

#[repr(C)]
pub struct FoglioStats {
    count: u64,
    numeric: u64,
    sum: f64,
    min: f64,
    max: f64,
}

#[no_mangle]
pub unsafe extern "C" fn foglio_stats(b: *const FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32, out: *mut FoglioStats) -> i32 {
    let Some(b) = book_ref(b) else { return -1 };
    if out.is_null() {
        return -1;
    }
    let model = b.model.get_model();
    let Some(ws) = model.workbook.worksheets.get(sheet as usize) else { return -1 };
    let dim = ws.dimension();
    let mut s = FoglioStats { count: 0, numeric: 0, sum: 0.0, min: f64::INFINITY, max: f64::NEG_INFINITY };
    for r in r0.max(dim.min_row)..=r1.min(dim.max_row) {
        for (c, _) in ws.sheet_data.cells_in_row_between(r, c0, c1) {
            match model.get_cell_value_by_index(sheet, r, c) {
                Ok(CellValue::Number(n)) => {
                    s.count += 1;
                    s.numeric += 1;
                    s.sum += n;
                    s.min = s.min.min(n);
                    s.max = s.max.max(n);
                }
                Ok(CellValue::None) | Err(_) => {}
                Ok(_) => s.count += 1,
            }
        }
    }
    *out = s;
    0
}

// ---------- find ----------

/// flags: bit0 match case, bit1 whole cell, bit2 look in formulas, bit3 search backwards.
/// Searches the sheet row by row starting after (row, col), wrapping around. Returns 1 if found.
#[no_mangle]
pub unsafe extern "C" fn foglio_find(
    b: *const FoglioBook, sheet: u32, row: i32, col: i32, query: *const c_char, flags: u32, out: *mut i32,
) -> i32 {
    let (Some(b), Some(q)) = (book_ref(b), cstr(query)) else { return -1 };
    if q.is_empty() || out.is_null() {
        return 0;
    }
    let case = flags & 1 != 0;
    let whole = flags & 2 != 0;
    let formulas = flags & 4 != 0;
    let back = flags & 8 != 0;
    let needle = if case { q.to_string() } else { q.to_lowercase() };
    let model = b.model.get_model();
    let Some(ws) = model.workbook.worksheets.get(sheet as usize) else { return -1 };
    let mut cells: Vec<(i32, i32)> = ws.sheet_data.cells().map(|(r, c, _)| (r, c)).collect();
    cells.sort_unstable();
    if back {
        cells.reverse();
    }
    let start = cells.iter().position(|&p| if back { p < (row, col) } else { p > (row, col) }).unwrap_or(0);
    let n = cells.len();
    for i in 0..n {
        let (r, c) = cells[(start + i) % n];
        let hay = if formulas {
            b.model.get_cell_content(sheet, r, c).unwrap_or_default()
        } else {
            b.model.get_formatted_cell_value(sheet, r, c).unwrap_or_default()
        };
        let hay = if case { hay } else { hay.to_lowercase() };
        let hit = if whole { hay == needle } else { hay.contains(&needle) };
        if hit {
            let o = std::slice::from_raw_parts_mut(out, 2);
            o.copy_from_slice(&[r, c]);
            return 1;
        }
    }
    0
}

/// Replaces `query` with `repl` in every cell's content (case-insensitive unless bit0). Returns count.
#[no_mangle]
pub unsafe extern "C" fn foglio_replace_all(b: *mut FoglioBook, sheet: u32, query: *const c_char, repl: *const c_char, flags: u32) -> i32 {
    let (Some(b), Some(q), Some(repl)) = (book(b), cstr(query), cstr(repl)) else { return -1 };
    if q.is_empty() {
        return 0;
    }
    let case = flags & 1 != 0;
    let whole = flags & 2 != 0;
    guard(-1, || {
        let coords: Vec<(i32, i32)> = match b.model.get_model().workbook.worksheets.get(sheet as usize) {
            Some(ws) => ws.sheet_data.cells().map(|(r, c, _)| (r, c)).collect(),
            None => return -1,
        };
        let mut edits = Vec::new();
        for (r, c) in coords {
            let content = b.model.get_cell_content(sheet, r, c).unwrap_or_default();
            if content.is_empty() {
                continue;
            }
            let new = if whole {
                let eq = if case { content == q } else { content.to_lowercase() == q.to_lowercase() };
                if eq { Some(repl.to_string()) } else { None }
            } else if case {
                content.contains(q).then(|| content.replace(q, repl))
            } else {
                replace_ci(&content, q, repl)
            };
            if let Some(n) = new {
                if n != content {
                    edits.push((r, c, n));
                }
            }
        }
        b.model.pause_evaluation();
        for (r, c, n) in &edits {
            let _ = b.model.set_user_input(sheet, *r, *c, n);
        }
        b.model.resume_evaluation();
        b.model.evaluate();
        edits.len() as i32
    })
}

fn replace_ci(hay: &str, needle: &str, repl: &str) -> Option<String> {
    let lower = hay.to_lowercase();
    let n = needle.to_lowercase();
    if !lower.contains(&n) || lower.len() != hay.len() {
        // Bail out on case-mapping that changes byte lengths (rare); fall back to exact match.
        return hay.contains(needle).then(|| hay.replace(needle, repl));
    }
    let mut out = String::with_capacity(hay.len());
    let mut i = 0;
    while let Some(p) = lower[i..].find(&n) {
        out.push_str(&hay[i..i + p]);
        out.push_str(repl);
        i += p + n.len();
    }
    out.push_str(&hay[i..]);
    Some(out)
}

// ---------- formula editing helpers ----------

/// Every function the engine knows, one per line as "LOCALIZED\tENGLISH" for the current language.
#[no_mangle]
pub extern "C" fn foglio_function_names() -> *mut c_char {
    guard(ptr::null_mut(), || {
        let (_, language, _) = crate::settings();
        let (Ok(en), Ok(local)) = (ironcalc::base::language::get_language("en"), ironcalc::base::language::get_language(language)) else {
            return ptr::null_mut();
        };
        let en = crate::fnames::all_names(&en.functions);
        let local = crate::fnames::all_names(&local.functions);
        let mut pairs: Vec<String> = local.iter().zip(en.iter()).map(|(l, e)| format!("{l}\t{e}")).collect();
        pairs.sort();
        pairs.dedup();
        to_c(pairs.join("\n"))
    })
}

#[repr(C)]
pub struct FoglioCompletion {
    /// 0 none, 1 function name prefix, 2 inside a function argument, 3 a range is expected
    kind: u8,
    /// char index where the typed token starts
    replace_from: u32,
    arg_index: u32,
    /// function name (prefix for kind 1, enclosing function for kind 2)
    name: *mut c_char,
}

#[no_mangle]
pub unsafe extern "C" fn foglio_completion(
    b: *mut FoglioBook, sheet: u32, row: i32, col: i32, formula: *const c_char, cursor: u32, out: *mut FoglioCompletion,
) -> i32 {
    let (Some(b), Some(f)) = (book(b), cstr(formula)) else { return -1 };
    if out.is_null() {
        return -1;
    }
    guard(-1, || {
        let Ok(ctx) = b.model.formula_completion(sheet, row, col, f, cursor as usize) else { return -1 };
        use ironcalc::base::expressions::parser::ExpectedTokens as E;
        let mut res = FoglioCompletion { kind: 0, replace_from: ctx.replace_from as u32, arg_index: 0, name: ptr::null_mut() };
        for e in &ctx.expecting {
            if let E::FunctionName(p) = e {
                res.kind = 1;
                res.name = to_c(p.clone());
                break;
            }
        }
        if res.kind == 0 {
            for e in &ctx.expecting {
                match e {
                    E::Argument(name, i) => {
                        res.kind = 2;
                        res.arg_index = *i;
                        res.name = to_c(name.clone());
                        break;
                    }
                    E::Range => res.kind = 3,
                    _ => {}
                }
            }
        }
        *out = res;
        0
    })
}

/// F4: cycles $ in the reference under the selection. Returns new text; writes new selection.
#[no_mangle]
pub unsafe extern "C" fn foglio_cycle_reference(b: *const FoglioBook, text: *const c_char, start: u32, end: u32, out: *mut i32) -> *mut c_char {
    let (Some(b), Some(t)) = (book_ref(b), cstr(text)) else { return ptr::null_mut() };
    guard(ptr::null_mut(), || match b.model.cycle_reference(t, start as usize, end as usize) {
        Ok((s, a, z)) => {
            if !out.is_null() {
                std::slice::from_raw_parts_mut(out, 2).copy_from_slice(&[a, z]);
            }
            to_c(s)
        }
        Err(_) => ptr::null_mut(),
    })
}

/// Distinct values in a column range (for future filter UI), newline separated. Capped at 10k.
#[no_mangle]
pub extern "C" fn foglio_unique_values(b: *const FoglioBook, sheet: u32, col: i32, r0: i32, r1: i32) -> *mut c_char {
    let Some(b) = book_ref(b) else { return ptr::null_mut() };
    let mut seen: HashMap<String, ()> = HashMap::new();
    let mut out = Vec::new();
    for r in r0..=r1 {
        let v = b.model.get_formatted_cell_value(sheet, r, col).unwrap_or_default();
        if seen.insert(v.clone(), ()).is_none() {
            out.push(v);
            if out.len() >= 10_000 {
                break;
            }
        }
    }
    to_c(out.join("\n"))
}

// ---------- conditional formatting (Excel's "Highlight Cells Rules", Top/Bottom, Color Scales) ----------

/// kind: 0 cell value (op: 0 =, 1 >, 2 >=, 3 <, 4 <=, 5 <>, 6 between, 7 not between),
///       1 text contains (op: 0 contains, 1 not contains, 2 begins, 3 ends, 4 equals),
///       2 duplicate values, 3 unique values, 4 top N (v1 = N), 5 bottom N, 6 above average, 7 below average,
///       8 colour scale green-yellow-red, 9 colour scale red-yellow-green, 10 colour scale white-blue, 11 blanks, 12 errors.
/// style: 0 light red fill + dark red text, 1 yellow fill + dark yellow text, 2 green fill + dark green text,
///        3 light red fill, 4 red text, 5 bold.
#[no_mangle]
pub unsafe extern "C" fn foglio_add_cf(
    b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32,
    kind: u32, op: u32, v1: *const c_char, v2: *const c_char, style: u32,
) -> i32 {
    use ironcalc::base::cf_types::{CfRuleInput, Cfvo, ColorScaleThreshold, TextOperator, ValueOperator};
    use ironcalc::base::types::{Dxf, DxfFont, Fill};
    let Some(b) = book(b) else { return -1 };
    let v1 = cstr(v1).unwrap_or("").to_string();
    let v2 = cstr(v2).unwrap_or("").to_string();
    let a = area(sheet, r0, c0, r1, c1);
    let range = {
        let col = |c: i32| ironcalc::base::expressions::utils::number_to_column(c).unwrap_or_default();
        format!("{}{}:{}{}", col(a.column), a.row, col(a.column + a.width - 1), a.row + a.height - 1)
    };
    let rgb = |s: &str| Color::Rgb(s.to_string());
    let format = {
        let (fill, font, bold) = match style {
            0 => (Some("#FFC7CE"), Some("#9C0006"), false),
            1 => (Some("#FFEB9C"), Some("#9C5700"), false),
            2 => (Some("#C6EFCE"), Some("#006100"), false),
            3 => (Some("#FFC7CE"), None, false),
            4 => (None, Some("#C00000"), false),
            _ => (None, None, true),
        };
        let mut dxf = Dxf::default();
        if let Some(f) = fill {
            dxf.fill = Some(Fill { color: rgb(f) });
        }
        if font.is_some() || bold {
            let mut df = DxfFont::default();
            if let Some(c) = font {
                df.color = rgb(c);
            }
            if bold {
                df.b = Some(true);
            }
            dxf.font = Some(df);
        }
        dxf
    };
    // Values typed in a decimal-comma locale ("1,5") are stored the way Excel stores them ("1.5").
    let num = |s: &str| -> String {
        let t = s.trim();
        let swapped = t.replace('.', "").replace(',', ".");
        if t.parse::<f64>().is_err() && swapped.parse::<f64>().is_ok() { swapped } else { t.to_string() }
    };
    let quoted = |s: &str| -> String {
        let n = num(s);
        if n.parse::<f64>().is_ok() || n.starts_with('=') { n.trim_start_matches('=').to_string() } else { format!("\"{}\"", s.replace('"', "\"\"")) }
    };
    let scale = |colors: &[&str]| -> CfRuleInput {
        let n = colors.len();
        let thresholds = colors
            .iter()
            .enumerate()
            .map(|(i, c)| ColorScaleThreshold {
                cfvo: if i == 0 { Cfvo::Min } else if i == n - 1 { Cfvo::Max } else { Cfvo::Percentile(50.0) },
                color: rgb(c),
            })
            .collect();
        CfRuleInput::ColorScale { thresholds }
    };
    let rule = match kind {
        0 => {
            let operator = match op {
                0 => ValueOperator::Equal,
                1 => ValueOperator::GreaterThan,
                2 => ValueOperator::GreaterThanOrEqual,
                3 => ValueOperator::LessThan,
                4 => ValueOperator::LessThanOrEqual,
                5 => ValueOperator::NotEqual,
                6 => ValueOperator::Between,
                _ => ValueOperator::NotBetween,
            };
            let formula2 = if op >= 6 { Some(quoted(&v2)) } else { None };
            CfRuleInput::CellIs { operator, formula: quoted(&v1), formula2, format, stop_if_true: false }
        }
        1 => {
            let operator = match op {
                0 => TextOperator::Contains,
                1 => TextOperator::DoesNotContain,
                2 => TextOperator::BeginsWith,
                3 => TextOperator::EndsWith,
                _ => TextOperator::Equals,
            };
            CfRuleInput::Text { operator, value: v1, format, stop_if_true: false }
        }
        2 => CfRuleInput::DuplicateValues { format, stop_if_true: false },
        3 => CfRuleInput::UniqueValues { format, stop_if_true: false },
        4 | 5 => {
            let rank = v1.trim().parse::<u32>().unwrap_or(10).max(1);
            if kind == 4 {
                CfRuleInput::Top10 { rank, percent: false, format, stop_if_true: false }
            } else {
                CfRuleInput::Bottom10 { rank, percent: false, format, stop_if_true: false }
            }
        }
        6 => CfRuleInput::AboveAverage { format, stop_if_true: false },
        7 => CfRuleInput::BelowAverage { format, stop_if_true: false },
        8 => scale(&["#63BE7B", "#FFEB84", "#F8696B"]),
        9 => scale(&["#F8696B", "#FFEB84", "#63BE7B"]),
        10 => scale(&["#FFFFFF", "#5A8AC6"]),
        11 => CfRuleInput::Blanks { format, stop_if_true: false },
        _ => CfRuleInput::Errors { format, stop_if_true: false },
    };
    let r = guard(-1, || rc(b.model.add_conditional_formatting(sheet, &range, rule)));
    b.style_cache.clear();
    r
}

/// Removes conditional-formatting rules whose range intersects the area (whole sheet when r0 == 0).
#[no_mangle]
pub extern "C" fn foglio_clear_cf(b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32) -> i32 {
    let Some(b) = book(b) else { return -1 };
    let target = area(sheet, r0.max(1), c0.max(1), r1.max(1), c1.max(1));
    let whole = r0 <= 0;
    let r = guard(-1, || {
        let Ok(list) = b.model.get_conditional_formatting_list(sheet) else { return -1 };
        let mut doomed: Vec<usize> = list
            .iter()
            .filter(|cf| whole || cf.range.split(' ').any(|part| range_intersects(part, &target)))
            .map(|cf| cf.index)
            .collect();
        doomed.sort_unstable_by(|a, b| b.cmp(a)); // delete from the end so indices stay valid
        for i in &doomed {
            let _ = b.model.delete_conditional_formatting(sheet, *i as u32);
        }
        doomed.len() as i32
    });
    b.style_cache.clear();
    r
}

fn range_intersects(a1: &str, t: &ironcalc::base::expressions::types::Area) -> bool {
    use ironcalc::base::expressions::utils::column_to_number;
    let parse = |s: &str| -> Option<(i32, i32)> {
        let s = s.replace('$', "");
        let split = s.find(|c: char| c.is_ascii_digit())?;
        Some((s[split..].parse().ok()?, column_to_number(&s[..split]).ok()?))
    };
    let mut it = a1.split(':');
    let Some(first) = it.next().and_then(parse) else { return false };
    let last = it.next().and_then(parse).unwrap_or(first);
    let (ar0, ac0, ar1, ac1) = (first.0.min(last.0), first.1.min(last.1), first.0.max(last.0), first.1.max(last.1));
    !(ar1 < t.row || ar0 > t.row + t.height - 1 || ac1 < t.column || ac0 > t.column + t.width - 1)
}

// ---------- format painter ----------

static STYLE_CLIP: Mutex<Option<Vec<Vec<Style>>>> = Mutex::new(None);

/// Remembers the styles of a range (max 1000 x 200) for foglio_paste_styles.
#[no_mangle]
pub extern "C" fn foglio_copy_styles(b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32) -> i32 {
    let Some(b) = book(b) else { return -1 };
    guard(-1, || {
        let (r0, r1, c0, c1) = (r0.min(r1), r0.max(r1).min(r0.min(r1) + 999), c0.min(c1), c0.max(c1).min(c0.min(c1) + 199));
        let mut grid = Vec::new();
        for r in r0..=r1 {
            let mut row = Vec::new();
            for c in c0..=c1 {
                row.push(b.model.get_cell_style(sheet, r, c).unwrap_or_default());
            }
            grid.push(row);
        }
        *STYLE_CLIP.lock().unwrap() = Some(grid);
        0
    })
}

/// Applies the remembered styles to the area, repeating the pattern like Excel's Format Painter. One undo step.
#[no_mangle]
pub extern "C" fn foglio_paste_styles(b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32) -> i32 {
    let Some(b) = book(b) else { return -1 };
    let r = guard(-1, || {
        let clip = STYLE_CLIP.lock().unwrap();
        let Some(styles) = clip.as_ref() else { return -1 };
        if select(b, sheet, r0.min(r1), c0.min(c1), r0.max(r1), c0.max(c1)).is_err() {
            return -1;
        }
        rc(b.model.on_paste_styles(styles))
    });
    b.style_cache.clear();
    r
}

// ---------- remove duplicates ----------

/// Excel's Data ▸ Remove Duplicates over all columns of the range: keeps the first occurrence of each row,
/// packs the kept rows to the top (formulas adjusted, styles kept) and clears the rest. Returns rows removed.
#[no_mangle]
pub extern "C" fn foglio_remove_duplicates(b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32) -> i32 {
    let Some(b) = book(b) else { return -1 };
    let r = guard(-1, || {
        let (r0, r1, c0, c1) = (r0.min(r1), r0.max(r1), c0.min(c1), c0.max(c1));
        let model = b.model.get_model();
        let mut seen = std::collections::HashSet::new();
        let mut keep = Vec::new();
        for r in r0..=r1 {
            let key: Vec<String> = (c0..=c1)
                .map(|c| b.model.get_formatted_cell_value(sheet, r, c).unwrap_or_default().to_lowercase())
                .collect();
            if seen.insert(key) {
                keep.push(r);
            }
        }
        let removed = (r1 - r0 + 1) as usize - keep.len();
        if removed == 0 {
            return 0;
        }
        let mut data = serde_json::Map::new();
        for (i, src) in keep.iter().enumerate() {
            let dst = r0 + i as i32;
            let mut row = serde_json::Map::new();
            for c in c0..=c1 {
                let text = match model.get_cell_formula(sheet, *src, c) {
                    Ok(Some(_)) => model.extend_to(sheet, *src, c, dst, c).unwrap_or_default(),
                    _ => b.model.get_cell_content(sheet, *src, c).unwrap_or_default(),
                };
                let style = b.model.get_cell_style(sheet, *src, c).unwrap_or_default();
                row.insert(c.to_string(), json!({"text": text, "is_spill": false, "style": style, "link": null}));
            }
            data.insert(dst.to_string(), Value::Object(row));
        }
        let new_last = r0 + keep.len() as i32 - 1;
        let Ok(data) = serde_json::from_value::<ClipboardData>(Value::Object(data)) else { return -1 };
        if select(b, sheet, r0, c0, new_last, c1).is_err() {
            return -1;
        }
        if b.model.paste_from_clipboard(sheet, (r0, c0, new_last, c1), &data, false).is_err() {
            return -1;
        }
        let rest = area(sheet, new_last + 1, c0, r1, c1);
        let _ = b.model.range_clear_contents(&rest);
        let _ = b.model.range_clear_formatting(&rest);
        removed as i32
    });
    b.style_cache.clear();
    r
}
