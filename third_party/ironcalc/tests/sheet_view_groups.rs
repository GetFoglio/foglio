//! Foglio fork: sheet zoom, "show zeros", default row height, AutoFilter and grouped pictures survive a
//! save and a reload.
#![allow(clippy::unwrap_used)]

use std::io::Read;

use ironcalc::export::save_to_xlsx;
use ironcalc::import::load_from_xlsx;
use ironcalc_base::charts::{AnchorPoint, ChartAnchor};
use ironcalc_base::pictures::{store_image, Picture, PictureEditAs};
use ironcalc_base::types::{AutoFilter, FilterColumn};
use ironcalc_base::Model;

fn tmp(name: &str) -> String {
    let d = std::env::temp_dir().join(format!("ironcalc-sheet-view-{}", std::process::id()));
    std::fs::create_dir_all(&d).unwrap();
    d.join(name).to_string_lossy().into_owned()
}

fn part(path: &str, name: &str) -> String {
    let mut zip = zip::ZipArchive::new(std::fs::File::open(path).unwrap()).unwrap();
    let mut s = String::new();
    zip.by_name(name).unwrap().read_to_string(&mut s).unwrap();
    s
}

/// A valid 1×1 PNG.
const PNG: &[u8] = &[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00,
    0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49,
    0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0, 0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D,
    0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

#[test]
fn sheet_view_round_trip() {
    let mut model = Model::new_empty("view", "en", "UTC", "en").unwrap();
    model.set_user_input(0, 1, 1, "Name".to_string()).unwrap();
    model.set_user_input(0, 2, 1, "a".to_string()).unwrap();
    model.set_user_input(0, 3, 1, "b".to_string()).unwrap();
    {
        let ws = model.workbook.worksheet_mut(0).unwrap();
        ws.zoom = 170;
        ws.show_zeros = false;
        ws.default_row_height = 11.45;
        ws.auto_filter = Some(AutoFilter {
            range: "A1:B3".to_string(),
            columns: vec![FilterColumn { col_id: 0, values: vec!["a".to_string(), "x<&>".to_string()], blank: true }],
        });
    }
    let path = tmp("view.xlsx");
    save_to_xlsx(&model, &path).unwrap();
    let xml = part(&path, "xl/worksheets/sheet1.xml");
    assert!(xml.contains(r#"showZeros="0""#), "{xml}");
    assert!(xml.contains(r#"zoomScale="170""#), "{xml}");
    assert!(xml.contains(r#"<sheetFormatPr defaultRowHeight="11.45" customHeight="1"/>"#), "{xml}");
    assert!(xml.contains(r#"<autoFilter ref="A1:B3">"#), "{xml}");
    assert!(xml.contains(r#"<filter val="x&lt;&amp;&gt;"/>"#), "{xml}");
    // schema order: autoFilter right after sheetData, before mergeCells
    assert!(xml.find("</sheetData>").unwrap() < xml.find("<autoFilter").unwrap());

    let back = load_from_xlsx(&path, "en", "UTC", "en").unwrap();
    let ws = back.workbook.worksheet(0).unwrap();
    assert_eq!(ws.zoom, 170);
    assert!(!ws.show_zeros);
    assert!((ws.default_row_height - 11.45).abs() < 1e-9);
    assert_eq!(ws.auto_filter, model.workbook.worksheet(0).unwrap().auto_filter);
    // rows without a height of their own take the sheet's default
    assert!((ws.row_height(10).unwrap() - 11.45 * 25.0 / 16.0).abs() < 1e-6);
}

#[test]
fn ordinary_files_keep_the_defaults() {
    let model = Model::new_empty("plain", "en", "UTC", "en").unwrap();
    let path = tmp("plain.xlsx");
    save_to_xlsx(&model, &path).unwrap();
    let xml = part(&path, "xl/worksheets/sheet1.xml");
    assert!(!xml.contains("zoomScale") && !xml.contains("showZeros") && !xml.contains("autoFilter"));
    assert!(!xml.contains("sheetFormatPr"));
    let back = load_from_xlsx(&path, "en", "UTC", "en").unwrap();
    let ws = back.workbook.worksheet(0).unwrap();
    assert_eq!((ws.zoom, ws.show_zeros, ws.default_row_height), (0, true, 0.0));
    assert!(ws.auto_filter.is_none());
}

#[test]
fn grouped_pictures_are_saved_as_a_group() {
    let mut model = Model::new_empty("groups", "en", "UTC", "en").unwrap();
    let ws = model.workbook.worksheet_mut(0).unwrap();
    let image = store_image(&mut ws.images, PNG);
    let at = |row, column| ChartAnchor {
        from: AnchorPoint { row, column, row_offset: 9525 * 3, column_offset: 9525 * 5 },
        to: AnchorPoint { row, column, row_offset: 0, column_offset: 0 },
    };
    for (i, (row, col, group)) in [(2, 2, 7), (6, 4, 7), (10, 2, 0)].into_iter().enumerate() {
        ws.pictures.push(Picture {
            name: format!("Photo {i}"),
            image: image.clone(),
            anchor: at(row, col),
            cx: 9525 * 40,
            cy: 9525 * 30,
            edit_as: PictureEditAs::OneCell,
            z: i as i32,
            group,
            ..Default::default()
        });
    }
    let path = tmp("groups.xlsx");
    save_to_xlsx(&model, &path).unwrap();
    let drawing = part(&path, "xl/drawings/drawing1.xml");
    assert_eq!(drawing.matches("<xdr:grpSp>").count(), 1, "{drawing}");
    assert_eq!(drawing.matches("<xdr:pic>").count(), 3);
    // shape ids are unique
    let mut ids: Vec<&str> = drawing
        .split(r#"cNvPr id=""#)
        .skip(1)
        .map(|rest| rest.split('"').next().unwrap())
        .collect();
    let n = ids.len();
    ids.sort();
    ids.dedup();
    assert_eq!(ids.len(), n, "{drawing}");

    let back = load_from_xlsx(&path, "en", "UTC", "en").unwrap();
    let pics = &back.workbook.worksheet(0).unwrap().pictures;
    assert_eq!(pics.len(), 3);
    let grouped: Vec<&Picture> = pics.iter().filter(|p| p.group != 0).collect();
    assert_eq!(grouped.len(), 2);
    assert_eq!(grouped[0].group, grouped[1].group);
    // each picture is where it was
    for p in &model.workbook.worksheet(0).unwrap().pictures {
        let q = pics.iter().find(|q| q.name == p.name).unwrap();
        assert_eq!((q.anchor.from.row, q.anchor.from.column), (p.anchor.from.row, p.anchor.from.column), "{}", p.name);
        assert!((q.anchor.from.row_offset - p.anchor.from.row_offset).abs() <= 9525, "{}", p.name);
        assert!((q.anchor.from.column_offset - p.anchor.from.column_offset).abs() <= 9525, "{}", p.name);
    }
}
