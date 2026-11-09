//! Foglio fork: pictures.
//!
//! Every worksheet keeps a list of [`Picture`]s (`Worksheet::pictures`) and a
//! store of image bytes (`Worksheet::images`, keyed by a content hash, so an
//! image used twice is stored once). A picture refers to its image by key;
//! undo steps (`Diff::SetPictures`) only hold the small picture records, never
//! the bytes. The store is append-only while the workbook is open (an image
//! replaced by "Compress Pictures" stays available to undo); only images in
//! use are written to the file.
//!
//! Geometry follows the xlsx drawing part: a two-cell anchor (`from`/`to`,
//! cell + EMU offsets) plus the picture size in EMU (`cx`/`cy`, `a:ext`).
//! * `edit_as == OneCell` / `Absolute`: the size is `cx`/`cy`; `to` is derived
//!   from it (recomputed when the file is written).
//! * `edit_as == TwoCell`: the picture moves and sizes with its cells; the size
//!   is derived from `from`/`to` ([`picture_extent`]).
//! * `in_cell`: "Place in Cell" — fitted inside the cell of `from` (aspect
//!   ratio `cx:cy` kept, centred, small margin), written as a two-cell anchor
//!   that moves and sizes with the cell.
//!
//! Image processing (decoding, resampling, re-encoding) is not done here: the
//! app does it and hands back bytes. Only the header of PNG, JPEG, GIF and BMP
//! files is read (pixel size, for imported pictures without a size).

use std::collections::HashMap;

use bitcode::{Decode, Encode};
use serde::{Deserialize, Serialize};

use crate::{
    charts::{advance_anchor, column_width_emu, row_height_emu, AnchorPoint, ChartAnchor, EMU_PER_PIXEL},
    types::Worksheet,
    user_model::history::Diff,
    Model, UserModel,
};

/// How a picture follows the cells (`xdr:twoCellAnchor/@editAs`).
#[derive(Serialize, Deserialize, Encode, Decode, Debug, PartialEq, Eq, Clone, Copy, Default)]
#[serde(rename_all = "snake_case")]
pub enum PictureEditAs {
    /// Moves and sizes with cells
    TwoCell,
    /// Moves but doesn't size with cells (Excel's default for inserted pictures)
    #[default]
    OneCell,
    /// Doesn't move or size with cells
    Absolute,
}

impl PictureEditAs {
    /// Value of the `editAs` attribute.
    pub fn xml_name(self) -> &'static str {
        match self {
            PictureEditAs::TwoCell => "twoCell",
            PictureEditAs::OneCell => "oneCell",
            PictureEditAs::Absolute => "absolute",
        }
    }
}

/// Cropping (`a:srcRect`): the part of the image cut off at each side, in
/// thousandths of a percent of the image size (100000 = 100%).
#[derive(Serialize, Deserialize, Encode, Decode, Debug, PartialEq, Eq, Clone, Copy, Default)]
pub struct PictureCrop {
    /// Left
    #[serde(default)]
    pub l: i32,
    /// Top
    #[serde(default)]
    pub t: i32,
    /// Right
    #[serde(default)]
    pub r: i32,
    /// Bottom
    #[serde(default)]
    pub b: i32,
}

impl PictureCrop {
    /// True when nothing is cropped.
    pub fn is_empty(&self) -> bool {
        self.l == 0 && self.t == 0 && self.r == 0 && self.b == 0
    }
    /// Clamped so at least 1% of the image remains in each direction.
    pub fn sanitized(self) -> PictureCrop {
        let c = |v: i32| v.clamp(-1_000_000, 99_000);
        let (mut l, mut r) = (c(self.l), c(self.r));
        let (mut t, mut b) = (c(self.t), c(self.b));
        if l + r > 99_000 {
            let k = 99_000.0 / (l + r) as f64;
            l = (l as f64 * k) as i32;
            r = (r as f64 * k) as i32;
        }
        if t + b > 99_000 {
            let k = 99_000.0 / (t + b) as f64;
            t = (t as f64 * k) as i32;
            b = (b as f64 * k) as i32;
        }
        PictureCrop { l, t, r, b }
    }
}

/// A picture placed on a worksheet.
#[derive(Serialize, Deserialize, Encode, Decode, Debug, PartialEq, Eq, Clone, Default)]
pub struct Picture {
    /// Name of the drawing object ("Picture 1")
    pub name: String,
    /// Alternative text (`cNvPr/@descr`)
    #[serde(default)]
    pub descr: String,
    /// Key of the image in `Worksheet::images`
    pub image: String,
    /// Placement (see the module documentation)
    pub anchor: ChartAnchor,
    /// Width in EMU (displayed, i.e. after cropping)
    pub cx: i64,
    /// Height in EMU
    pub cy: i64,
    /// How the picture follows the cells
    #[serde(default)]
    pub edit_as: PictureEditAs,
    /// Cropping
    #[serde(default)]
    pub crop: PictureCrop,
    /// "Place in Cell": fitted inside the cell of `anchor.from`
    #[serde(default)]
    pub in_cell: bool,
    /// Stacking order among the drawing objects (charts and pictures) of the
    /// sheet: higher is in front
    #[serde(default)]
    pub z: i32,
}

// ---------------------------------------------------------------------------
// Image bytes
// ---------------------------------------------------------------------------

/// Image formats recognised from their first bytes.
pub fn image_format(bytes: &[u8]) -> &'static str {
    let starts = |p: &[u8]| bytes.len() >= p.len() && &bytes[..p.len()] == p;
    if starts(&[0x89, b'P', b'N', b'G']) {
        "png"
    } else if starts(&[0xFF, 0xD8, 0xFF]) {
        "jpeg"
    } else if starts(b"GIF8") {
        "gif"
    } else if starts(b"BM") {
        "bmp"
    } else if starts(b"II*\0") || starts(b"MM\0*") {
        "tiff"
    } else if starts(&[0x01, 0x00, 0x00, 0x00]) && bytes.len() > 44 && &bytes[40..44] == b" EMF" {
        "emf"
    } else if starts(&[0xD7, 0xCD, 0xC6, 0x9A]) || starts(&[0x01, 0x00, 0x09, 0x00]) || starts(&[0x02, 0x00, 0x09, 0x00]) {
        "wmf"
    } else {
        "bin"
    }
}

/// MIME type for the `[Content_Types].xml` default of an extension.
pub fn image_content_type(format: &str) -> Option<&'static str> {
    Some(match format {
        "png" => "image/png",
        "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "bmp" => "image/bmp",
        "tiff" => "image/tiff",
        "emf" => "image/x-emf",
        "wmf" => "image/x-wmf",
        _ => return None,
    })
}

/// Pixel size of a PNG, JPEG, GIF or BMP image (read from its header).
pub fn image_pixel_size(bytes: &[u8]) -> Option<(u32, u32)> {
    let be16 = |i: usize| -> Option<u32> { Some(u16::from_be_bytes([*bytes.get(i)?, *bytes.get(i + 1)?]) as u32) };
    let le16 = |i: usize| -> Option<u32> { Some(u16::from_le_bytes([*bytes.get(i)?, *bytes.get(i + 1)?]) as u32) };
    let be32 = |i: usize| -> Option<u32> {
        Some(u32::from_be_bytes([*bytes.get(i)?, *bytes.get(i + 1)?, *bytes.get(i + 2)?, *bytes.get(i + 3)?]))
    };
    let le32 = |i: usize| -> Option<i32> {
        Some(i32::from_le_bytes([*bytes.get(i)?, *bytes.get(i + 1)?, *bytes.get(i + 2)?, *bytes.get(i + 3)?]))
    };
    let size = match image_format(bytes) {
        "png" => (be32(16)?, be32(20)?),
        "gif" => (le16(6)?, le16(8)?),
        "bmp" => (le32(18)?.unsigned_abs(), le32(22)?.unsigned_abs()),
        "jpeg" => {
            let mut i = 2;
            loop {
                // Skip fill bytes, then read the marker.
                while *bytes.get(i)? == 0xFF && *bytes.get(i + 1)? == 0xFF {
                    i += 1;
                }
                if *bytes.get(i)? != 0xFF {
                    return None;
                }
                let marker = *bytes.get(i + 1)?;
                let len = be16(i + 2)? as usize;
                // SOF0..SOF15 except DHT (C4), JPG (C8), DAC (CC)
                if (0xC0..=0xCF).contains(&marker) && !matches!(marker, 0xC4 | 0xC8 | 0xCC) {
                    break (be16(i + 7)?, be16(i + 5)?);
                }
                if len < 2 {
                    return None;
                }
                i += 2 + len;
            }
        }
        _ => return None,
    };
    (size.0 > 0 && size.1 > 0).then_some(size)
}

/// The key of an image in the store: a 64-bit FNV-1a hash of the bytes and their length.
pub fn image_key(bytes: &[u8]) -> String {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for b in bytes {
        h ^= *b as u64;
        h = h.wrapping_mul(0x0000_0100_0000_01B3);
    }
    format!("{h:016x}{:08x}", bytes.len())
}

/// Adds `bytes` to the image store of `worksheet` (if not there yet) and returns the key.
pub fn store_image(images: &mut HashMap<String, Vec<u8>>, bytes: &[u8]) -> String {
    let key = image_key(bytes);
    images.entry(key.clone()).or_insert_with(|| bytes.to_vec());
    key
}

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

/// Distance in EMU from the top-left corner of the sheet to `p` (x, y).
pub fn anchor_position(ws: &Worksheet, p: &AnchorPoint) -> (i64, i64) {
    // Columns: few have their own width; rows: only the ones listed.
    let mut x = 0;
    let mut c = 1;
    while c < p.column {
        // Runs of columns that share a width are added in one step.
        let span = ws.cols.iter().find(|col| c >= col.min && c <= col.max);
        let end = match span {
            Some(col) => col.max.min(p.column - 1),
            None => {
                let next = ws.cols.iter().filter(|col| col.min > c).map(|col| col.min).min().unwrap_or(i32::MAX);
                (next - 1).min(p.column - 1)
            }
        };
        x += column_width_emu(ws, c) * (end - c + 1) as i64;
        c = end + 1;
    }
    let default_h = 15 * crate::charts::EMU_PER_POINT;
    let mut y = default_h * (p.row - 1).max(0) as i64;
    for r in &ws.rows {
        if r.r < p.row {
            y += row_height_emu(ws, r.r) - default_h;
        }
    }
    (x + p.column_offset, y + p.row_offset)
}

/// Size in EMU between two anchor points (walking column widths and row heights).
pub fn anchor_extent(ws: &Worksheet, a: &ChartAnchor) -> (i64, i64) {
    let (x0, y0) = anchor_position(ws, &a.from);
    let (x1, y1) = anchor_position(ws, &a.to);
    ((x1 - x0).max(0), (y1 - y0).max(0))
}

/// The displayed size of a picture in EMU (see the module documentation).
pub fn picture_extent(ws: &Worksheet, p: &Picture) -> (i64, i64) {
    if p.edit_as == PictureEditAs::TwoCell && !p.in_cell {
        let (cx, cy) = anchor_extent(ws, &p.anchor);
        if cx > 0 && cy > 0 {
            return (cx, cy);
        }
    }
    (p.cx.max(1), p.cy.max(1))
}

/// Margin between an in-cell picture and the cell borders (1 px).
pub const IN_CELL_MARGIN: i64 = EMU_PER_PIXEL;

/// The anchor of a picture with aspect ratio `cx:cy` fitted inside cell
/// (row, column): centred, aspect ratio kept, [`IN_CELL_MARGIN`] around it.
pub fn fit_in_cell(ws: &Worksheet, row: i32, column: i32, cx: i64, cy: i64) -> ChartAnchor {
    let w = column_width_emu(ws, column);
    let h = row_height_emu(ws, row);
    let (aw, ah) = ((w - 2 * IN_CELL_MARGIN).max(1), (h - 2 * IN_CELL_MARGIN).max(1));
    let (cx, cy) = (cx.max(1) as f64, cy.max(1) as f64);
    let k = (aw as f64 / cx).min(ah as f64 / cy);
    let (fw, fh) = (((cx * k).round() as i64).clamp(1, aw), ((cy * k).round() as i64).clamp(1, ah));
    let x = ((w - fw) / 2).max(0);
    let y = ((h - fh) / 2).max(0);
    ChartAnchor {
        from: AnchorPoint { row, column, row_offset: y, column_offset: x },
        to: AnchorPoint { row, column, row_offset: (y + fh).min(h), column_offset: (x + fw).min(w) },
    }
}

/// The anchor written to the file for `p`: `to` recomputed from the size
/// (one-cell and absolute pictures) or from the cell (in-cell pictures).
pub fn export_anchor(ws: &Worksheet, p: &Picture) -> ChartAnchor {
    if p.in_cell {
        return fit_in_cell(ws, p.anchor.from.row, p.anchor.from.column, p.cx, p.cy);
    }
    match p.edit_as {
        PictureEditAs::TwoCell => p.anchor,
        PictureEditAs::OneCell | PictureEditAs::Absolute => ChartAnchor {
            from: p.anchor.from,
            to: advance_anchor(ws, p.anchor.from, p.cx.max(1), p.cy.max(1)),
        },
    }
}

/// Insert (count > 0) or delete (count < 0) rows or columns at `at`: moves the
/// pictures of the sheet like Excel (absolute pictures stay where they are).
pub(crate) fn displace_pictures(ws: &mut Worksheet, rows: bool, at: i32, count: i32) {
    let shift = |index: &mut i32, offset: &mut i64| {
        if count >= 0 {
            if *index >= at {
                *index += count;
            }
        } else {
            let n = -count;
            if *index > at + n - 1 {
                *index -= n;
            } else if *index >= at {
                *index = at;
                *offset = 0;
            }
        }
    };
    for p in &mut ws.pictures {
        if p.edit_as == PictureEditAs::Absolute && !p.in_cell {
            continue;
        }
        let a = &mut p.anchor;
        if rows {
            shift(&mut a.from.row, &mut a.from.row_offset);
            shift(&mut a.to.row, &mut a.to.row_offset);
        } else {
            shift(&mut a.from.column, &mut a.from.column_offset);
            shift(&mut a.to.column, &mut a.to.column_offset);
        }
    }
    // A two-cell picture whose cells were all deleted keeps a minimal size.
    for p in &mut ws.pictures {
        let a = &mut p.anchor;
        if p.edit_as == PictureEditAs::TwoCell && !p.in_cell {
            if (a.to.row, a.to.row_offset) <= (a.from.row, a.from.row_offset) {
                a.to = AnchorPoint { row: a.from.row, row_offset: a.from.row_offset + EMU_PER_PIXEL * 4, ..a.to };
            }
            if (a.to.column, a.to.column_offset) <= (a.from.column, a.from.column_offset) {
                a.to = AnchorPoint { column: a.from.column, column_offset: a.from.column_offset + EMU_PER_PIXEL * 4, ..a.to };
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Stacking order (shared with charts)
// ---------------------------------------------------------------------------

/// A drawing object of a sheet: a chart or a picture, by index.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum DrawingObject {
    /// `Worksheet::charts[i]`
    Chart(usize),
    /// `Worksheet::pictures[i]`
    Picture(usize),
}

/// The drawing objects of a sheet from back to front (ties: charts first,
/// then by index), the order of the anchors in the drawing part.
pub fn drawing_order(ws: &Worksheet) -> Vec<DrawingObject> {
    let mut list: Vec<(i32, u8, usize)> = ws
        .charts
        .iter()
        .enumerate()
        .map(|(i, c)| (c.z, 0, i))
        .chain(ws.pictures.iter().enumerate().map(|(i, p)| (p.z, 1, i)))
        .collect();
    list.sort();
    list.into_iter()
        .map(|(_, kind, i)| if kind == 0 { DrawingObject::Chart(i) } else { DrawingObject::Picture(i) })
        .collect()
}

/// The z value that puts a new object in front of every other one.
pub fn next_z(ws: &Worksheet) -> i32 {
    ws.charts.iter().map(|c| c.z).chain(ws.pictures.iter().map(|p| p.z)).max().map_or(0, |z| z + 1)
}

/// How to restack a drawing object.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Restack {
    /// One step towards the front
    Forward,
    /// One step towards the back
    Backward,
    /// In front of everything
    Front,
    /// Behind everything
    Back,
}

// ---------------------------------------------------------------------------
// Undoable edits
// ---------------------------------------------------------------------------

impl Model<'_> {
    /// The pictures of a sheet.
    pub fn get_pictures(&self, sheet: u32) -> Result<&[Picture], String> {
        Ok(&self.workbook.worksheet(sheet)?.pictures)
    }
}

impl UserModel<'_> {
    /// The pictures of a sheet.
    pub fn get_pictures(&self, sheet: u32) -> Result<&[Picture], String> {
        self.model.get_pictures(sheet)
    }

    /// The bytes of image `key` of `sheet`.
    pub fn get_picture_image(&self, sheet: u32, key: &str) -> Option<&[u8]> {
        self.model.workbook.worksheet(sheet).ok()?.images.get(key).map(|v| v.as_slice())
    }

    /// Stores image bytes in the sheet (not an undo step: the store only grows)
    /// and returns the key to use in [`Picture::image`].
    pub fn add_picture_image(&mut self, sheet: u32, bytes: &[u8]) -> Result<String, String> {
        let ws = self.model.workbook.worksheet_mut(sheet)?;
        Ok(store_image(&mut ws.images, bytes))
    }

    fn set_pictures(&mut self, sheet: u32, new_value: Vec<Picture>) -> Result<(), String> {
        let worksheet = self.model.workbook.worksheet_mut(sheet)?;
        if worksheet.pictures == new_value {
            return Ok(());
        }
        if let Some(p) = new_value.iter().find(|p| !worksheet.images.contains_key(&p.image)) {
            return Err(format!("Unknown image {}", p.image));
        }
        let old_value = std::mem::replace(&mut worksheet.pictures, new_value.clone());
        self.push_diff_list(vec![Diff::SetPictures { sheet, old_value, new_value }]);
        Ok(())
    }

    /// Adds a picture (its image must be in the store) in front of the other
    /// drawing objects and returns its index. One undo step.
    pub fn add_picture(&mut self, sheet: u32, mut picture: Picture) -> Result<usize, String> {
        let ws = self.model.workbook.worksheet(sheet)?;
        let mut pictures = ws.pictures.clone();
        if picture.name.is_empty() {
            let n = self.model.workbook.worksheets.iter().map(|w| w.pictures.len()).sum::<usize>();
            picture.name = format!("Picture {}", n + 1);
        }
        picture.z = next_z(ws);
        picture.crop = picture.crop.sanitized();
        pictures.push(picture);
        let index = pictures.len() - 1;
        self.set_pictures(sheet, pictures)?;
        Ok(index)
    }

    /// Replaces picture `index`. One undo step (nothing if unchanged).
    pub fn update_picture(&mut self, sheet: u32, index: usize, mut picture: Picture) -> Result<(), String> {
        let mut pictures = self.model.get_pictures(sheet)?.to_vec();
        let slot = pictures.get_mut(index).ok_or_else(|| format!("No picture {index}"))?;
        picture.crop = picture.crop.sanitized();
        *slot = picture;
        self.set_pictures(sheet, pictures)
    }

    /// Deletes picture `index`. One undo step.
    pub fn delete_picture(&mut self, sheet: u32, index: usize) -> Result<(), String> {
        let mut pictures = self.model.get_pictures(sheet)?.to_vec();
        if index >= pictures.len() {
            return Err(format!("No picture {index}"));
        }
        pictures.remove(index);
        self.set_pictures(sheet, pictures)
    }

    /// Moves a chart or picture forward/backward among the drawing objects of
    /// the sheet. One undo step (nothing if it is already there).
    pub fn restack_drawing(&mut self, sheet: u32, object: DrawingObject, how: Restack) -> Result<(), String> {
        let ws = self.model.workbook.worksheet(sheet)?;
        let mut order = drawing_order(ws);
        let pos = order.iter().position(|o| *o == object).ok_or("No such drawing object")?;
        let target = match how {
            Restack::Forward => (pos + 1).min(order.len() - 1),
            Restack::Backward => pos.saturating_sub(1),
            Restack::Front => order.len() - 1,
            Restack::Back => 0,
        };
        if target == pos {
            return Ok(());
        }
        let o = order.remove(pos);
        order.insert(target, o);
        let mut charts = ws.charts.clone();
        let mut pictures = ws.pictures.clone();
        for (z, o) in order.iter().enumerate() {
            match *o {
                DrawingObject::Chart(i) => charts[i].z = z as i32,
                DrawingObject::Picture(i) => pictures[i].z = z as i32,
            }
        }
        let ws = self.model.workbook.worksheet_mut(sheet)?;
        let old_charts = std::mem::replace(&mut ws.charts, charts.clone());
        let old_pictures = std::mem::replace(&mut ws.pictures, pictures.clone());
        let mut diffs = vec![];
        if old_charts != charts {
            diffs.push(Diff::SetCharts { sheet, old_value: old_charts, new_value: charts });
        }
        if old_pictures != pictures {
            diffs.push(Diff::SetPictures { sheet, old_value: old_pictures, new_value: pictures });
        }
        if !diffs.is_empty() {
            self.push_diff_list(diffs);
        }
        Ok(())
    }

    /// Undo/redo of `Diff::SetPictures`.
    pub(crate) fn apply_pictures_diff(&mut self, sheet: u32, value: &[Picture]) -> Result<(), String> {
        self.model.workbook.worksheet_mut(sheet)?.pictures = value.to_vec();
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;

    fn png(w: u32, h: u32) -> Vec<u8> {
        let mut v = vec![0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, b'I', b'H', b'D', b'R'];
        v.extend(w.to_be_bytes());
        v.extend(h.to_be_bytes());
        v.extend([8, 6, 0, 0, 0]);
        v
    }

    #[test]
    fn headers() {
        assert_eq!(image_pixel_size(&png(640, 480)), Some((640, 480)));
        assert_eq!(image_format(&png(1, 1)), "png");
        let jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0, 4, 0, 0, 0xFF, 0xC0, 0, 11, 8, 0, 120, 0, 160, 3];
        assert_eq!(image_pixel_size(&jpeg), Some((160, 120)));
        assert_eq!(image_pixel_size(b"GIF89a\x10\x00\x20\x00"), Some((16, 32)));
        assert_eq!(image_pixel_size(b"nonsense"), None);
        assert_eq!(image_pixel_size(&[0xFF, 0xD8, 0xFF]), None);
        assert_ne!(image_key(b"a"), image_key(b"b"));
    }

    #[test]
    fn edits_undo_and_order() {
        let mut model = UserModel::new_empty("model", "en", "UTC", "en").unwrap();
        let key = model.add_picture_image(0, &png(10, 10)).unwrap();
        assert_eq!(model.add_picture_image(0, &png(10, 10)).unwrap(), key);
        let pic = Picture {
            image: key.clone(),
            anchor: ChartAnchor { from: AnchorPoint { row: 2, column: 2, ..Default::default() }, to: Default::default() },
            cx: 952_500,
            cy: 952_500,
            ..Default::default()
        };
        assert_eq!(model.add_picture(0, pic.clone()).unwrap(), 0);
        assert_eq!(model.get_pictures(0).unwrap()[0].name, "Picture 1");
        model.add_chart(0, crate::charts::Chart::default()).unwrap();
        model.add_picture(0, pic.clone()).unwrap();
        let ws = model.get_model().workbook.worksheet(0).unwrap();
        assert_eq!(drawing_order(ws), vec![DrawingObject::Picture(0), DrawingObject::Chart(0), DrawingObject::Picture(1)]);
        model.restack_drawing(0, DrawingObject::Picture(1), Restack::Back).unwrap();
        let ws = model.get_model().workbook.worksheet(0).unwrap();
        assert_eq!(drawing_order(ws), vec![DrawingObject::Picture(1), DrawingObject::Picture(0), DrawingObject::Chart(0)]);
        model.undo().unwrap();
        let ws = model.get_model().workbook.worksheet(0).unwrap();
        assert_eq!(drawing_order(ws)[2], DrawingObject::Picture(1));

        // Rows inserted above move the picture; undo moves it back.
        model.insert_rows(0, 1, 3).unwrap();
        assert_eq!(model.get_pictures(0).unwrap()[0].anchor.from.row, 5);
        model.undo().unwrap();
        assert_eq!(model.get_pictures(0).unwrap()[0].anchor.from.row, 2);

        model.delete_picture(0, 0).unwrap();
        assert_eq!(model.get_pictures(0).unwrap().len(), 1);
        model.undo().unwrap();
        assert_eq!(model.get_pictures(0).unwrap().len(), 2);

        // Unknown image keys are refused.
        let bad = Picture { image: "nope".into(), ..pic };
        assert!(model.add_picture(0, bad).is_err());
    }

    #[test]
    fn geometry() {
        let model = UserModel::new_empty("model", "en", "UTC", "en").unwrap();
        let ws = model.get_model().workbook.worksheet(0).unwrap();
        // Default cells: 64 x 20 px.
        let a = fit_in_cell(ws, 3, 2, 100, 100);
        assert_eq!(a.from.row, 3);
        assert_eq!(a.to.column, 2);
        let (w, h) = anchor_extent(ws, &a);
        assert_eq!(w, h);
        assert_eq!(h, 20 * EMU_PER_PIXEL - 2 * IN_CELL_MARGIN);
        let p = AnchorPoint { row: 3, column: 4, row_offset: 10, column_offset: 20 };
        assert_eq!(anchor_position(ws, &p), (3 * 64 * EMU_PER_PIXEL + 20, 2 * 20 * EMU_PER_PIXEL + 10));
        let crop = PictureCrop { l: 80_000, r: 60_000, t: 0, b: 0 }.sanitized();
        assert!(crop.l + crop.r <= 99_000);
    }
}
