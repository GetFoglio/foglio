//! Pictures: C ABI over `ironcalc_base::pictures` (see include/foglio_pictures.h).
//!
//! Like charts, small payloads travel as JSON and anchors as a 1-based cell
//! plus fractions of it. Sizes are in EMU (914400 per inch, 9525 per pixel at
//! 96 dpi). Image bytes cross the boundary as plain buffers: the app decodes,
//! crops, resamples and re-encodes (ImageIO); the engine only stores bytes.

use std::ffi::c_char;
use std::ptr;

use ironcalc::base::charts::{advance_anchor, ChartAnchor};
use ironcalc::base::pictures::{
    anchor_extent, drawing_order, export_anchor, fit_in_cell, image_format, image_pixel_size, picture_extent, DrawingObject, Picture,
    PictureCrop, PictureEditAs, Restack,
};
use ironcalc::base::types::Worksheet;
use serde_json::{json, Map, Value};

use crate::charts::{point_from, point_json};
use crate::{book, book_ref, cstr, guard, to_c, FoglioBook};

fn edit_as_name(e: PictureEditAs) -> &'static str {
    match e {
        PictureEditAs::TwoCell => "two_cell",
        PictureEditAs::OneCell => "one_cell",
        PictureEditAs::Absolute => "absolute",
    }
}

fn edit_as_from(s: &str) -> Option<PictureEditAs> {
    Some(match s {
        "two_cell" | "twoCell" => PictureEditAs::TwoCell,
        "one_cell" | "oneCell" => PictureEditAs::OneCell,
        "absolute" => PictureEditAs::Absolute,
        _ => return None,
    })
}

fn picture_json(ws: &Worksheet, index: usize, p: &Picture) -> Value {
    let bytes = ws.images.get(&p.image).map(|b| b.as_slice()).unwrap_or(&[]);
    let (cx, cy) = picture_extent(ws, p);
    let (pw, ph) = image_pixel_size(bytes).unwrap_or((0, 0));
    json!({
        "index": index,
        "name": p.name,
        "descr": p.descr,
        "image": p.image,
        "format": image_format(bytes),
        "bytes": bytes.len(),
        "px_w": pw,
        "px_h": ph,
        "from": point_json(ws, &p.anchor.from),
        // Where the picture ends with the current row heights and column widths (one-cell and absolute pictures
        // keep their size: their stored `to` can be stale).
        "to": point_json(ws, &export_anchor(ws, p).to),
        "cx": cx,
        "cy": cy,
        "edit_as": edit_as_name(p.edit_as),
        "crop": { "l": p.crop.l, "t": p.crop.t, "r": p.crop.r, "b": p.crop.b },
        "in_cell": p.in_cell,
        "z": p.z,
    })
}

fn num(v: &Value, key: &str) -> Option<f64> {
    v.get(key).and_then(Value::as_f64).filter(|f| f.is_finite())
}

/// Applies a JSON patch (see foglio_pictures.h) to `p`.
fn apply_patch(ws: &Worksheet, p: &mut Picture, patch: &Map<String, Value>) {
    if let Some(n) = patch.get("name").and_then(Value::as_str) {
        if !n.is_empty() {
            p.name = n.to_string();
        }
    }
    if let Some(d) = patch.get("descr").and_then(Value::as_str) {
        p.descr = d.to_string();
    }
    if let Some(c) = patch.get("crop") {
        let v = |k: &str| num(c, k).unwrap_or(0.0).round() as i32;
        p.crop = PictureCrop { l: v("l"), t: v("t"), r: v("r"), b: v("b") }.sanitized();
    }
    if let Some(e) = patch.get("edit_as").and_then(Value::as_str).and_then(edit_as_from) {
        p.edit_as = e;
    }
    let was_in_cell = p.in_cell;
    if let Some(b) = patch.get("in_cell").and_then(Value::as_bool) {
        p.in_cell = b;
    }
    let from = patch.get("from").map(|f| {
        point_from(
            ws,
            num(f, "row").unwrap_or(1.0) as i32,
            num(f, "col").unwrap_or(1.0) as i32,
            num(f, "fy").unwrap_or(0.0),
            num(f, "fx").unwrap_or(0.0),
        )
    });
    let size_given = patch.contains_key("cx") || patch.contains_key("cy");
    // The size before the change (in-cell: what it occupies in its cell).
    let (cur_cx, cur_cy) = if was_in_cell { anchor_extent(ws, &p.anchor) } else { picture_extent(ws, p) };
    let size = |k: &str| patch.get(k).and_then(Value::as_f64).filter(|f| f.is_finite()).map(|v| v.round() as i64);
    let cx = size("cx").unwrap_or(cur_cx).clamp(1, 1 << 40);
    let cy = size("cy").unwrap_or(cur_cy).clamp(1, 1 << 40);
    if p.in_cell {
        // Fitted in the cell of `from` (the new one if given); `cx:cy` keeps the aspect ratio.
        let (row, column) = from.map(|f| (f.row, f.column)).unwrap_or((p.anchor.from.row, p.anchor.from.column));
        let (acx, acy) = if size_given || !was_in_cell { (cx, cy) } else { (p.cx.max(1), p.cy.max(1)) };
        p.cx = acx;
        p.cy = acy;
        p.edit_as = PictureEditAs::TwoCell;
        p.anchor = fit_in_cell(ws, row, column, acx, acy);
    } else if was_in_cell || from.is_some() || size_given {
        if was_in_cell && !patch.contains_key("edit_as") {
            // "Place over Cells": a normal picture that moves with its cell.
            p.edit_as = PictureEditAs::OneCell;
        }
        let from = from.unwrap_or(p.anchor.from);
        p.cx = cx;
        p.cy = cy;
        p.anchor = ChartAnchor { from, to: advance_anchor(ws, from, cx, cy) };
    }
}

// ---------- C ABI ----------

/// JSON array of the pictures of `sheet` (see foglio_pictures.h).
#[no_mangle]
pub extern "C" fn foglio_pictures_json(b: *const FoglioBook, sheet: u32) -> *mut c_char {
    let Some(b) = book_ref(b) else { return ptr::null_mut() };
    guard(ptr::null_mut(), || {
        let model = b.model.get_model();
        let Ok(ws) = model.workbook.worksheet(sheet) else { return ptr::null_mut() };
        let list: Vec<Value> = ws.pictures.iter().enumerate().map(|(i, p)| picture_json(ws, i, p)).collect();
        to_c(Value::Array(list).to_string())
    })
}

/// Number of pictures on `sheet`.
#[no_mangle]
pub extern "C" fn foglio_picture_count(b: *const FoglioBook, sheet: u32) -> i32 {
    let Some(b) = book_ref(b) else { return -1 };
    guard(-1, || b.model.get_pictures(sheet).map(|p| p.len() as i32).unwrap_or(-1))
}

/// Copy of the bytes of image `key` of `sheet` (free with foglio_bytes_free).
#[no_mangle]
pub unsafe extern "C" fn foglio_picture_image(b: *const FoglioBook, sheet: u32, key: *const c_char, len: *mut usize) -> *mut u8 {
    let (Some(b), Some(key)) = (book_ref(b), cstr(key)) else { return ptr::null_mut() };
    if len.is_null() {
        return ptr::null_mut();
    }
    guard(ptr::null_mut(), || {
        let Some(bytes) = b.model.get_picture_image(sheet, key) else { return ptr::null_mut() };
        let boxed: Box<[u8]> = bytes.to_vec().into_boxed_slice();
        *len = boxed.len();
        Box::into_raw(boxed) as *mut u8
    })
}

/// Frees a buffer returned by foglio_picture_image.
#[no_mangle]
pub unsafe extern "C" fn foglio_bytes_free(p: *mut u8, len: usize) {
    if !p.is_null() {
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(p, len)));
    }
}

unsafe fn bytes_arg<'a>(data: *const u8, len: usize) -> Option<&'a [u8]> {
    (!data.is_null() && len > 0).then(|| std::slice::from_raw_parts(data, len))
}

/// Adds a picture showing the image in `data` (PNG, JPEG, GIF, BMP, TIFF, EMF or WMF)
/// placed as described by `json` (see foglio_pictures.h). Returns the index or -1.
#[no_mangle]
pub unsafe extern "C" fn foglio_picture_add(b: *mut FoglioBook, sheet: u32, data: *const u8, len: usize, json: *const c_char) -> i32 {
    let (Some(b), Some(bytes)) = (book(b), bytes_arg(data, len)) else { return -1 };
    let patch = cstr(json).unwrap_or("{}");
    guard(-1, || {
        if !matches!(image_format(bytes), "png" | "jpeg" | "gif" | "bmp" | "tiff" | "emf" | "wmf") {
            return -1;
        }
        let Ok(Value::Object(patch)) = serde_json::from_str::<Value>(patch) else { return -1 };
        let Ok(key) = b.model.add_picture_image(sheet, bytes) else { return -1 };
        let Ok(ws) = b.model.get_model().workbook.worksheet(sheet) else { return -1 };
        let (pw, ph) = image_pixel_size(bytes).unwrap_or((100, 100));
        let mut p = Picture {
            image: key,
            cx: pw as i64 * 9525,
            cy: ph as i64 * 9525,
            edit_as: PictureEditAs::OneCell,
            ..Default::default()
        };
        p.anchor = ChartAnchor { from: point_from(ws, 1, 1, 0.0, 0.0), to: point_from(ws, 1, 1, 0.0, 0.0) };
        let mut patch = patch;
        // Size defaults to the image's pixel size; placement to A1.
        patch.entry("cx").or_insert(json!(p.cx));
        patch.entry("cy").or_insert(json!(p.cy));
        patch.entry("from").or_insert(json!({"row": 1, "col": 1, "fy": 0.0, "fx": 0.0}));
        apply_patch(ws, &mut p, &patch);
        b.model.add_picture(sheet, p).map(|i| i as i32).unwrap_or(-1)
    })
}

/// Changes picture `index` with the JSON patch; if `data` is not null, the
/// picture shows that image instead ("Change Picture", "Compress Pictures").
/// One undo step. Returns 0 or -1.
#[no_mangle]
pub unsafe extern "C" fn foglio_picture_update(
    b: *mut FoglioBook, sheet: u32, index: u32, json: *const c_char, data: *const u8, len: usize,
) -> i32 {
    let Some(b) = book(b) else { return -1 };
    let patch = cstr(json).unwrap_or("{}");
    let bytes = bytes_arg(data, len);
    guard(-1, || {
        let Ok(Value::Object(patch)) = serde_json::from_str::<Value>(patch) else { return -1 };
        let Some(mut p) = b.model.get_pictures(sheet).ok().and_then(|l| l.get(index as usize)).cloned() else { return -1 };
        if let Some(bytes) = bytes {
            if !matches!(image_format(bytes), "png" | "jpeg" | "gif" | "bmp" | "tiff" | "emf" | "wmf") {
                return -1;
            }
            let Ok(key) = b.model.add_picture_image(sheet, bytes) else { return -1 };
            p.image = key;
        }
        let Ok(ws) = b.model.get_model().workbook.worksheet(sheet) else { return -1 };
        apply_patch(ws, &mut p, &patch);
        if b.model.update_picture(sheet, index as usize, p).is_ok() { 0 } else { -1 }
    })
}

/// Deletes picture `index`. One undo step.
#[no_mangle]
pub extern "C" fn foglio_picture_delete(b: *mut FoglioBook, sheet: u32, index: u32) -> i32 {
    let Some(b) = book(b) else { return -1 };
    guard(-1, || if b.model.delete_picture(sheet, index as usize).is_ok() { 0 } else { -1 })
}

/// Charts and pictures of `sheet` from back to front:
/// `[{"kind":"chart"|"picture","index":N}, ...]`.
#[no_mangle]
pub extern "C" fn foglio_drawing_order_json(b: *const FoglioBook, sheet: u32) -> *mut c_char {
    let Some(b) = book_ref(b) else { return ptr::null_mut() };
    guard(ptr::null_mut(), || {
        let Ok(ws) = b.model.get_model().workbook.worksheet(sheet) else { return ptr::null_mut() };
        let list: Vec<Value> = drawing_order(ws)
            .into_iter()
            .map(|o| match o {
                DrawingObject::Chart(i) => json!({"kind": "chart", "index": i}),
                DrawingObject::Picture(i) => json!({"kind": "picture", "index": i}),
            })
            .collect();
        to_c(Value::Array(list).to_string())
    })
}

/// Restacks a chart or picture ("forward", "backward", "front", "back"). One undo step.
#[no_mangle]
pub unsafe extern "C" fn foglio_drawing_restack(b: *mut FoglioBook, sheet: u32, kind: *const c_char, index: u32, how: *const c_char) -> i32 {
    let (Some(b), Some(kind), Some(how)) = (book(b), cstr(kind), cstr(how)) else { return -1 };
    let object = match kind {
        "chart" => DrawingObject::Chart(index as usize),
        "picture" => DrawingObject::Picture(index as usize),
        _ => return -1,
    };
    let how = match how {
        "forward" => Restack::Forward,
        "backward" => Restack::Backward,
        "front" => Restack::Front,
        "back" => Restack::Back,
        _ => return -1,
    };
    guard(-1, || if b.model.restack_drawing(sheet, object, how).is_ok() { 0 } else { -1 })
}
