//! Pictures through the C ABI: add/move/resize/crop/replace/delete with undo,
//! stacking with charts, Place in Cell, and xlsx round trips (our own files, a
//! file written by openpyxl, Excel 365 pictures in cells).

use std::ffi::{c_char, CStr, CString};
use std::io::{Cursor, Read, Write};
use std::path::{Path, PathBuf};
use std::ptr;

use foglio_core::charts::{foglio_chart_add, foglio_charts_json};
use foglio_core::io::foglio_open_any;
use foglio_core::pictures::{
    foglio_bytes_free, foglio_drawing_order_json, foglio_drawing_restack, foglio_picture_add, foglio_picture_delete,
    foglio_picture_image, foglio_picture_update, foglio_pictures_json,
};
use foglio_core::{foglio_free, foglio_new, foglio_redo, foglio_save_xlsx, foglio_set_input, foglio_string_free, foglio_undo, FoglioBook};
use serde_json::Value;

#[allow(improper_ctypes)]
extern "C" {
    fn foglio_set_row_height(b: *mut FoglioBook, sheet: u32, r0: i32, r1: i32, px: f64) -> i32;
    fn foglio_structure(b: *mut FoglioBook, sheet: u32, op: i32, index: i32, count: i32) -> i32;
    fn foglio_comment_set(b: *mut FoglioBook, sheet: u32, row: i32, col: i32, text: *const c_char, author: *const c_char) -> i32;
    fn foglio_comment_get(b: *const FoglioBook, sheet: u32, row: i32, col: i32) -> *mut c_char;
}

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
    let d = std::env::temp_dir().join(format!("foglio-picture-tests-{}", std::process::id()));
    std::fs::create_dir_all(&d).unwrap();
    d.join(name)
}

fn fixture(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures").join(name)
}

/// A PNG header with the given size and some distinguishing payload (the
/// engine never decodes images, only their header).
fn png(w: u32, h: u32, tag: u8) -> Vec<u8> {
    let mut v = vec![0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, b'I', b'H', b'D', b'R'];
    v.extend(w.to_be_bytes());
    v.extend(h.to_be_bytes());
    v.extend([8, 6, 0, 0, 0, tag, tag, tag]);
    v
}

fn jpeg(w: u16, h: u16) -> Vec<u8> {
    let mut v = vec![0xFF, 0xD8, 0xFF, 0xE0, 0, 4, 0, 0, 0xFF, 0xC0, 0, 11, 8];
    v.extend(h.to_be_bytes());
    v.extend(w.to_be_bytes());
    v.extend([3, 1, 2, 3, 0xFF, 0xD9]);
    v
}

const EMU_PX: i64 = 9525;

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
    fn pictures(&self, sheet: u32) -> Vec<Value> {
        let v: Value = serde_json::from_str(&take(foglio_pictures_json(self.0, sheet))).unwrap();
        v.as_array().unwrap().clone()
    }
    fn add(&self, sheet: u32, bytes: &[u8], patch: &str) -> i32 {
        unsafe { foglio_picture_add(self.0, sheet, bytes.as_ptr(), bytes.len(), c(patch).as_ptr()) }
    }
    fn update(&self, sheet: u32, i: u32, patch: &str) -> i32 {
        unsafe { foglio_picture_update(self.0, sheet, i, c(patch).as_ptr(), ptr::null(), 0) }
    }
    fn replace(&self, sheet: u32, i: u32, patch: &str, bytes: &[u8]) -> i32 {
        unsafe { foglio_picture_update(self.0, sheet, i, c(patch).as_ptr(), bytes.as_ptr(), bytes.len()) }
    }
    fn image(&self, sheet: u32, key: &str) -> Vec<u8> {
        let mut len = 0usize;
        let p = unsafe { foglio_picture_image(self.0, sheet, c(key).as_ptr(), &mut len) };
        assert!(!p.is_null());
        let out = unsafe { std::slice::from_raw_parts(p, len) }.to_vec();
        unsafe { foglio_bytes_free(p, len) };
        out
    }
    fn order(&self, sheet: u32) -> String {
        let v: Value = serde_json::from_str(&take(foglio_drawing_order_json(self.0, sheet))).unwrap();
        v.as_array().unwrap().iter().map(|o| format!("{}{}", &o["kind"].as_str().unwrap()[..1], o["index"])).collect::<Vec<_>>().join(",")
    }
    fn undo(&self) {
        assert_eq!(foglio_undo(self.0), 0);
    }
}

fn zip_entries(path: &Path) -> Vec<(String, Vec<u8>)> {
    let mut z = zip::ZipArchive::new(std::fs::File::open(path).unwrap()).unwrap();
    (0..z.len())
        .map(|i| {
            let mut f = z.by_index(i).unwrap();
            let mut d = Vec::new();
            f.read_to_end(&mut d).unwrap();
            (f.name().unwrap().to_string(), d)
        })
        .collect()
}

fn part(path: &Path, name: &str) -> String {
    zip_entries(path).into_iter().find(|(n, _)| n == name).map(|(_, d)| String::from_utf8(d).unwrap()).unwrap_or_default()
}

#[test]
fn add_edit_undo() {
    let b = Book::new();
    let img = png(400, 200, 1);
    let i = b.add(0, &img, r#"{"from":{"row":2,"col":2,"fy":0,"fx":0},"cx":3810000,"cy":1905000,"descr":"Logo"}"#);
    assert_eq!(i, 0);
    let p = &b.pictures(0)[0];
    assert_eq!(p["name"], "Picture 1");
    assert_eq!(p["descr"], "Logo");
    assert_eq!(p["format"], "png");
    assert_eq!((p["px_w"].as_i64(), p["px_h"].as_i64()), (Some(400), Some(200)));
    assert_eq!((p["cx"].as_i64(), p["cy"].as_i64()), (Some(3_810_000), Some(1_905_000)));
    assert_eq!(p["edit_as"], "one_cell");
    assert_eq!(b.image(0, p["image"].as_str().unwrap()), img);

    // Move, resize, crop: one undo step each.
    assert_eq!(b.update(0, 0, r#"{"from":{"row":5,"col":3,"fy":0.5,"fx":0}}"#), 0);
    assert_eq!(b.pictures(0)[0]["from"]["row"], 5);
    assert_eq!(b.update(0, 0, r#"{"cx":1905000,"cy":952500}"#), 0);
    assert_eq!(b.pictures(0)[0]["cx"], 1_905_000);
    assert_eq!(b.update(0, 0, r#"{"crop":{"l":10000,"t":0,"r":25000,"b":5000}}"#), 0);
    assert_eq!(b.pictures(0)[0]["crop"]["r"], 25_000);
    b.undo();
    assert_eq!(b.pictures(0)[0]["crop"]["r"], 0);
    b.undo();
    assert_eq!(b.pictures(0)[0]["cx"], 3_810_000);
    b.undo();
    assert_eq!(b.pictures(0)[0]["from"]["row"], 2);
    assert_eq!(foglio_redo(b.0), 0);
    assert_eq!(b.pictures(0)[0]["from"]["row"], 5);

    // Replace the image (Change Picture / Compress): undo brings the old one back.
    let small = jpeg(100, 50);
    assert_eq!(b.replace(0, 0, r#"{"crop":{"l":0,"t":0,"r":0,"b":0}}"#, &small), 0);
    let p = &b.pictures(0)[0];
    assert_eq!(p["format"], "jpeg");
    assert_eq!(p["bytes"].as_u64(), Some(small.len() as u64));
    b.undo();
    let p = &b.pictures(0)[0];
    assert_eq!(p["format"], "png");
    assert_eq!(b.image(0, p["image"].as_str().unwrap()), img);

    // Rows inserted above move it; delete + undo.
    assert_eq!(unsafe { foglio_structure(b.0, 0, 0, 1, 2) }, 0);
    assert_eq!(b.pictures(0)[0]["from"]["row"], 7);
    assert_eq!(foglio_picture_delete(b.0, 0, 0), 0);
    assert!(b.pictures(0).is_empty());
    b.undo();
    assert_eq!(b.pictures(0).len(), 1);

    // Not an image: refused.
    assert_eq!(b.add(0, b"hello world", "{}"), -1);
}

#[test]
fn stacking_with_charts() {
    let b = Book::new();
    for (r, v) in [(1, "Sales"), (2, "3"), (3, "5")] {
        assert_eq!(unsafe { foglio_set_input(b.0, 0, r, 1, c(v).as_ptr()) }, 0);
    }
    b.add(0, &png(10, 10, 1), "{}");
    assert_eq!(unsafe { foglio_chart_add(b.0, 0, c("column").as_ptr(), 1, 1, 3, 1, 0, 0) }, 0);
    b.add(0, &png(10, 10, 2), "{}");
    assert_eq!(b.order(0), "p0,c0,p1");
    let restack = |kind: &str, i: u32, how: &str| unsafe { foglio_drawing_restack(b.0, 0, c(kind).as_ptr(), i, c(how).as_ptr()) };
    assert_eq!(restack("picture", 0, "forward"), 0);
    assert_eq!(b.order(0), "c0,p0,p1");
    assert_eq!(restack("chart", 0, "front"), 0);
    assert_eq!(b.order(0), "p0,p1,c0");
    b.undo();
    assert_eq!(b.order(0), "c0,p0,p1");

    // The order survives a round trip (it is the order of the anchors).
    let path = tmp("stacking.xlsx");
    b.save(&path);
    let back = Book::open(&path);
    assert_eq!(back.order(0), "c0,p0,p1");
    let drawing = part(&path, "xl/drawings/drawing1.xml");
    let chart_at = drawing.find("graphicFrame").unwrap();
    let pic_at = drawing.find("<xdr:pic>").unwrap();
    assert!(chart_at < pic_at);
}

#[test]
fn round_trip_with_charts_and_comments() {
    let b = Book::new();
    for (r, v) in [(1, "Sales"), (2, "3"), (3, "5")] {
        assert_eq!(unsafe { foglio_set_input(b.0, 0, r, 1, c(v).as_ptr()) }, 0);
    }
    assert_eq!(unsafe { foglio_comment_set(b.0, 0, 1, 1, c("note").as_ptr(), c("me").as_ptr()) }, 0);
    assert_eq!(unsafe { foglio_chart_add(b.0, 0, c("line").as_ptr(), 1, 1, 3, 1, 0, 0) }, 0);
    let logo = png(64, 32, 7);
    b.add(0, &logo, r#"{"from":{"row":3,"col":3,"fy":0.25,"fx":0.5},"cx":609600,"cy":304800,"descr":"A & B <logo>","name":"Logo"}"#);
    b.add(0, &logo, r#"{"from":{"row":8,"col":2,"fy":0,"fx":0},"edit_as":"absolute"}"#);
    b.add(0, &jpeg(300, 150), r#"{"from":{"row":12,"col":1,"fy":0,"fx":0},"cx":2857500,"cy":1428750,"edit_as":"two_cell"}"#);
    b.update(0, 2, r#"{"crop":{"l":12500,"t":0,"r":0,"b":33000}}"#);
    let path = tmp("roundtrip.xlsx");
    b.save(&path);

    let entries = zip_entries(&path);
    let media: Vec<&String> = entries.iter().map(|(n, _)| n).filter(|n| n.starts_with("xl/media/") && !n.ends_with('/')).collect();
    assert_eq!(media.len(), 2, "identical images are written once: {media:?}");
    let types = part(&path, "[Content_Types].xml");
    assert!(types.contains(r#"<Default Extension="png" ContentType="image/png"/>"#));
    assert!(types.contains(r#"<Default Extension="jpeg" ContentType="image/jpeg"/>"#));
    assert!(types.contains(r#"<Default Extension="vml""#));
    let drawing = part(&path, "xl/drawings/drawing1.xml");
    assert!(drawing.contains(r#"editAs="oneCell""#) && drawing.contains(r#"editAs="absolute""#) && drawing.contains(r#"editAs="twoCell""#));
    assert!(drawing.contains(r#"<a:srcRect l="12500" b="33000"/>"#));
    assert!(drawing.contains("descr=\"A &amp; B &lt;logo&gt;\""));
    let rels = part(&path, "xl/drawings/_rels/drawing1.xml.rels");
    assert_eq!(rels.matches("relationships/image").count(), 2);
    assert_eq!(rels.matches("relationships/chart").count(), 1);
    let sheet = part(&path, "xl/worksheets/sheet1.xml");
    assert!(sheet.find("<drawing").unwrap() < sheet.find("<legacyDrawing").unwrap());

    let back = Book::open(&path);
    let pics = back.pictures(0);
    assert_eq!(pics.len(), 3);
    assert_eq!(pics[0]["name"], "Logo");
    assert_eq!(pics[0]["descr"], "A & B <logo>");
    assert_eq!((pics[0]["from"]["row"].as_i64(), pics[0]["from"]["col"].as_i64()), (Some(3), Some(3)));
    assert!((pics[0]["from"]["fx"].as_f64().unwrap() - 0.5).abs() < 0.01);
    assert_eq!((pics[0]["cx"].as_i64(), pics[0]["cy"].as_i64()), (Some(609_600), Some(304_800)));
    assert_eq!(pics[1]["edit_as"], "absolute");
    assert_eq!((pics[1]["cx"].as_i64(), pics[1]["cy"].as_i64()), (Some(64 * EMU_PX), Some(32 * EMU_PX)));
    assert_eq!(pics[2]["edit_as"], "two_cell");
    assert_eq!(pics[2]["crop"]["l"], 12_500);
    assert_eq!(pics[2]["crop"]["b"], 33_000);
    assert_eq!(pics[0]["image"], pics[1]["image"]);
    assert_eq!(back.image(0, pics[0]["image"].as_str().unwrap()), logo);
    let charts: Value = serde_json::from_str(&take(foglio_charts_json(back.0, 0))).unwrap();
    assert_eq!(charts.as_array().unwrap().len(), 1);
    assert_eq!(take(unsafe { foglio_comment_get(back.0, 0, 1, 1) }), "note");

    // Saving the reopened file gives the same drawing.
    let again = tmp("roundtrip2.xlsx");
    back.save(&again);
    assert_eq!(part(&again, "xl/drawings/drawing1.xml"), drawing);
}

#[test]
fn place_in_cell() {
    let b = Book::new();
    b.add(0, &png(200, 100, 3), r#"{"from":{"row":4,"col":2,"fy":0,"fx":0}}"#);
    assert_eq!(b.update(0, 0, r#"{"in_cell":true}"#), 0);
    let p = &b.pictures(0)[0];
    assert_eq!(p["in_cell"], true);
    assert_eq!(p["edit_as"], "two_cell");
    assert_eq!((p["from"]["row"].as_i64(), p["to"]["row"].as_i64()), (Some(4), Some(4)));
    assert_eq!((p["from"]["col"].as_i64(), p["to"]["col"].as_i64()), (Some(2), Some(2)));
    // Taller row: the picture still fits its cell after saving.
    assert_eq!(unsafe { foglio_set_row_height(b.0, 0, 4, 4, 120.0) }, 0);
    let path = tmp("incell.xlsx");
    b.save(&path);
    let drawing = part(&path, "xl/drawings/drawing1.xml");
    assert!(drawing.contains(r#"editAs="twoCell""#));
    let back = Book::open(&path);
    let p = &back.pictures(0)[0];
    assert_eq!(p["in_cell"], true);
    assert_eq!((p["from"]["row"].as_i64(), p["to"]["row"].as_i64()), (Some(4), Some(4)));
    // 2:1 picture in a 64 px wide cell: width limited, 62 x 31 px.
    let cx = p["cx"].as_f64().unwrap();
    let cy = p["cy"].as_f64().unwrap();
    assert!((cx / cy - 2.0).abs() < 0.05, "aspect {cx}/{cy}");
    // Inserting rows above moves it with its cell.
    assert_eq!(unsafe { foglio_structure(back.0, 0, 0, 2, 1) }, 0);
    assert_eq!(back.pictures(0)[0]["from"]["row"], 5);
    // Place over Cells: a normal picture where it was, the same size.
    assert_eq!(back.update(0, 0, r#"{"in_cell":false}"#), 0);
    let p = &back.pictures(0)[0];
    assert_eq!(p["in_cell"], false);
    assert_eq!(p["edit_as"], "one_cell");
    assert_eq!(p["from"]["row"], 5);
    assert!((p["cx"].as_f64().unwrap() - cx).abs() < 2.0 * EMU_PX as f64);
}

#[test]
fn openpyxl_file() {
    let path = fixture("pictures_openpyxl.xlsx");
    let b = Book::open(&path);
    let pics = b.pictures(0);
    assert_eq!(pics.len(), 2);
    assert_eq!(pics[0]["format"], "png");
    assert_eq!(pics[1]["format"], "jpeg");
    assert_eq!((pics[0]["from"]["row"].as_i64(), pics[0]["from"]["col"].as_i64()), (Some(2), Some(4)));
    assert_eq!((pics[0]["cx"].as_i64(), pics[0]["cy"].as_i64()), (Some(120 * EMU_PX), Some(80 * EMU_PX)));
    assert_eq!((pics[0]["px_w"].as_i64(), pics[0]["px_h"].as_i64()), (Some(120), Some(80)));
    assert_eq!(pics[0]["edit_as"], "one_cell");
    assert_eq!(b.order(0), "c0,p0,p1");
    assert_eq!(b.pictures(1).len(), 1);
    assert_eq!(take(unsafe { foglio_comment_get(b.0, 0, 1, 1) }), "A note");

    let out = tmp("openpyxl-resaved.xlsx");
    b.save(&out);
    let media: Vec<String> = zip_entries(&out).into_iter().map(|(n, _)| n).filter(|n| n.starts_with("xl/media/") && !n.ends_with('/')).collect();
    assert_eq!(media.len(), 2, "the PNG used on both sheets is written once: {media:?}");
    let back = Book::open(&out);
    assert_eq!(back.pictures(0).len(), 2);
    assert_eq!(back.pictures(1).len(), 1);
    assert_eq!(back.pictures(1)[0]["image"], back.pictures(0)[0]["image"]);
    assert_eq!(back.order(0), "c0,p0,p1");
}

/// Builds an Excel 365 workbook with a picture in cell B2 (rich value) from
/// one of ours, by adding the parts Excel writes.
fn rich_value_workbook(path: &Path) -> Vec<u8> {
    let b = Book::new();
    assert_eq!(unsafe { foglio_set_input(b.0, 0, 2, 2, c("placeholder").as_ptr()) }, 0);
    assert_eq!(unsafe { foglio_set_input(b.0, 0, 3, 1, c("keep").as_ptr()) }, 0);
    let base = tmp("rich-base.xlsx");
    b.save(&base);
    let image = png(300, 150, 9);
    let mut out = zip::ZipWriter::new(Cursor::new(Vec::new()));
    let opts = zip::write::SimpleFileOptions::default();
    for (name, data) in zip_entries(&base) {
        let data = match name.as_str() {
            "xl/worksheets/sheet1.xml" => {
                let s = String::from_utf8(data).unwrap();
                let start = s.find("<c r=\"B2\"").unwrap();
                let end = start + s[start..].find("</c>").unwrap() + 4;
                format!("{}<c r=\"B2\" t=\"e\" vm=\"1\"><v>#VALUE!</v></c>{}", &s[..start], &s[end..]).into_bytes()
            }
            "xl/metadata.xml" => br#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<metadata xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:xlrd="http://schemas.microsoft.com/office/spreadsheetml/2017/richdata"><metadataTypes count="1"><metadataType name="XLRICHVALUE" minSupportedVersion="120000" copy="1" pasteAll="1" pasteValues="1" merge="1" splitFirst="1" rowColShift="1" clearFormats="1" clearComments="1" assign="1" coerce="1"/></metadataTypes><futureMetadata name="XLRICHVALUE" count="1"><bk><extLst><ext uri="{3e2802c4-a4d2-4d8b-9148-e3be6c30e623}"><xlrd:rvb i="0"/></ext></extLst></bk></futureMetadata><valueMetadata count="1"><bk><rc t="1" v="0"/></bk></valueMetadata></metadata>"#.to_vec(),
            _ => data,
        };
        out.start_file(name, opts).unwrap();
        out.write_all(&data).unwrap();
    }
    let extra: [(&str, &[u8]); 5] = [
        ("xl/richData/rdrichvaluestructure.xml", br#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<rvStructures xmlns="http://schemas.microsoft.com/office/spreadsheetml/2017/richdata" count="1"><s t="_localImage"><k n="_rvRel:LocalImageIdentifier" t="i"/><k n="CalcOrigin" t="i"/><k n="Text" t="s"/></s></rvStructures>"#),
        ("xl/richData/rdrichvalue.xml", br#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<rvData xmlns="http://schemas.microsoft.com/office/spreadsheetml/2017/richdata" count="1"><rv s="0"><v>0</v><v>5</v><v>A cat</v></rv></rvData>"#),
        ("xl/richData/richValueRel.xml", br#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<richValueRels xmlns="http://schemas.microsoft.com/office/spreadsheetml/2022/richvaluerel" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><rel r:id="rId1"/></richValueRels>"#),
        ("xl/richData/_rels/richValueRel.xml.rels", br#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image1.png"/></Relationships>"#),
        ("xl/media/image1.png", &image),
    ];
    for (name, data) in extra {
        out.start_file(name, opts).unwrap();
        out.write_all(data).unwrap();
    }
    std::fs::write(path, out.finish().unwrap().into_inner()).unwrap();
    image
}

#[test]
fn excel_pictures_in_cells() {
    let path = tmp("richvalue.xlsx");
    let image = rich_value_workbook(&path);
    let b = Book::open(&path);
    let pics = b.pictures(0);
    assert_eq!(pics.len(), 1);
    let p = &pics[0];
    assert_eq!(p["in_cell"], true);
    assert_eq!(p["descr"], "A cat");
    assert_eq!((p["from"]["row"].as_i64(), p["from"]["col"].as_i64()), (Some(2), Some(2)));
    assert_eq!(b.image(0, p["image"].as_str().unwrap()), image);
    // The #VALUE! placeholder is gone, other cells stay.
    #[allow(improper_ctypes)]
    extern "C" {
        fn foglio_get_input(b: *const FoglioBook, sheet: u32, row: i32, col: i32) -> *mut c_char;
    }
    assert_eq!(take(unsafe { foglio_get_input(b.0, 0, 2, 2) }), "");
    assert_eq!(take(unsafe { foglio_get_input(b.0, 0, 3, 1) }), "keep");
}

#[test]
fn broken_drawing_parts_are_skipped() {
    let b = Book::new();
    b.add(0, &png(10, 10, 1), r#"{"from":{"row":1,"col":1,"fy":0,"fx":0}}"#);
    b.add(0, &png(10, 10, 2), r#"{"from":{"row":5,"col":1,"fy":0,"fx":0}}"#);
    let path = tmp("broken-src.xlsx");
    b.save(&path);
    // Drop one image part and make the other rel point nowhere: the file still opens.
    let mut out = zip::ZipWriter::new(Cursor::new(Vec::new()));
    for (name, data) in zip_entries(&path) {
        if name == "xl/media/image1.png" {
            continue;
        }
        let data = if name == "xl/drawings/drawing1.xml" {
            String::from_utf8(data).unwrap().replacen("<xdr:twoCellAnchor", "<xdr:twoCellAnchor><xdr:sp/></xdr:twoCellAnchor><xdr:twoCellAnchor", 1).into_bytes()
        } else {
            data
        };
        out.start_file(name, zip::write::SimpleFileOptions::default()).unwrap();
        out.write_all(&data).unwrap();
    }
    let broken = tmp("broken.xlsx");
    std::fs::write(&broken, out.finish().unwrap().into_inner()).unwrap();
    let back = Book::open(&broken);
    assert_eq!(back.pictures(0).len(), 1);
}

/// Real files with pictures (Apache POI test data, when present: FOGLIO_CORPUS or the default path):
/// every picture survives a save and reopen with its image, crop and placement.
#[test]
fn real_files_round_trip() {
    let dir = std::env::var("FOGLIO_CORPUS").unwrap_or_else(|_| "/tmp/poi-test/files".into());
    let Ok(entries) = std::fs::read_dir(&dir) else { return };
    let mut checked = 0;
    for e in entries.flatten() {
        let path = e.path();
        let ext = path.extension().and_then(|x| x.to_str()).unwrap_or("").to_ascii_lowercase();
        if ext != "xlsx" && ext != "xlsm" {
            continue;
        }
        let has_media = zip::ZipArchive::new(std::fs::File::open(&path).unwrap())
            .map(|z| z.file_names().filter_map(|n| n.ok()).any(|n| n.to_ascii_lowercase().starts_with("xl/media/")))
            .unwrap_or(false);
        if !has_media {
            continue;
        }
        let mut err: *mut c_char = ptr::null_mut();
        let b = unsafe { foglio_open_any(c(path.to_str().unwrap()).as_ptr(), &mut err) };
        if b.is_null() {
            if !err.is_null() {
                take(err);
            }
            continue;
        }
        let b = Book(b);
        let sheets = foglio_core::foglio_sheet_count(b.0);
        let before: Vec<Vec<Value>> = (0..sheets).map(|s| b.pictures(s)).collect();
        if before.iter().all(|p| p.is_empty()) {
            continue;
        }
        let out = tmp(&format!("corpus-{}", path.file_name().unwrap().to_str().unwrap()));
        b.save(&out);
        let back = Book::open(&out);
        for s in 0..sheets {
            let after = back.pictures(s);
            assert_eq!(before[s as usize].len(), after.len(), "{path:?} sheet {s}");
            for (x, y) in before[s as usize].iter().zip(&after) {
                for k in ["image", "crop", "edit_as", "in_cell", "descr", "format"] {
                    assert_eq!(x[k], y[k], "{path:?} sheet {s} {k}");
                }
                assert_eq!(x["from"]["row"], y["from"]["row"], "{path:?}");
                assert_eq!(x["from"]["col"], y["from"]["col"], "{path:?}");
                let close = |a: &Value, b: &Value| (a.as_f64().unwrap() - b.as_f64().unwrap()).abs() <= 2.0 * EMU_PX as f64;
                assert!(close(&x["cx"], &y["cx"]) && close(&x["cy"], &y["cy"]), "{path:?} size {x} {y}");
            }
        }
        checked += 1;
    }
    eprintln!("checked {checked} files with pictures");
}
