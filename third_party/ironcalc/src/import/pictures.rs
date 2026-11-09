//! Foglio fork: reads the pictures of a worksheet.
//!
//! * Floating pictures: `xdr:pic` anchors of the drawing part (read together
//!   with the charts, see charts.rs) → drawing rels → `xl/media/*`.
//! * Excel 365 "Place in Cell" pictures: cells with a `vm` attribute whose
//!   value metadata points to a `_localImage` rich value (`xl/metadata.xml` →
//!   `xl/richData/rdrichvalue.xml` → `richValueRel.xml` → `xl/media/*`). They
//!   become in-cell pictures and the cell (which holds `#VALUE!` for older
//!   readers) is emptied.
//!
//! Tolerant like the chart reader: anything unexpected skips that picture.

use std::collections::HashMap;
use std::io::{BufReader, Read, Seek};

use ironcalc_base::charts::{advance_anchor, AnchorPoint, ChartAnchor, EMU_PER_PIXEL};
use ironcalc_base::pictures::{
    anchor_extent, fit_in_cell, image_format, image_pixel_size, store_image, Picture, PictureCrop, PictureEditAs,
};
use ironcalc_base::types::Worksheet;

use super::charts::{child, load_rels, path_child, read_xml, REL_NS};
use super::xml::XmlNode;

/// Largest image read from a file (larger ones are skipped).
const MAX_IMAGE_BYTES: u64 = 64 * 1024 * 1024;

/// Bytes of a part (case-insensitive name, like `read_xml`).
pub(super) fn read_bytes<R: Read + Seek>(archive: &mut zip::ZipArchive<R>, path: &str) -> Option<Vec<u8>> {
    let name = if archive.index_for_name(path).is_some() {
        path.to_string()
    } else {
        (0..archive.len())
            .filter_map(|i| archive.name_for_index(i).and_then(|r| r.ok()).map(|n| n.to_string()))
            .find(|n| n.eq_ignore_ascii_case(path))?
    };
    let file = archive.by_name(&name).ok()?;
    if file.size() > MAX_IMAGE_BYTES {
        return None;
    }
    let mut out = Vec::with_capacity(file.size() as usize);
    file.take(MAX_IMAGE_BYTES).read_to_end(&mut out).ok()?;
    Some(out)
}

fn ext_of(node: &XmlNode) -> Option<(i64, i64)> {
    let ext = child(node, "ext")?;
    let cx: i64 = ext.attribute("cx")?.trim().parse().ok()?;
    let cy: i64 = ext.attribute("cy")?.trim().parse().ok()?;
    (cx > 0 && cy > 0).then_some((cx, cy))
}

fn crop_of(blip_fill: &XmlNode) -> PictureCrop {
    let Some(src) = child(blip_fill, "srcRect") else { return PictureCrop::default() };
    let v = |n: &str| src.attribute(n).and_then(|v| v.trim().parse::<i32>().ok()).unwrap_or(0);
    PictureCrop { l: v("l"), t: v("t"), r: v("r"), b: v("b") }.sanitized()
}

/// A picture of a drawing anchor (`xdr:twoCellAnchor`, `xdr:oneCellAnchor` or
/// `xdr:absoluteAnchor` holding an `xdr:pic`), its image added to the sheet's
/// store. `z` is the position of the anchor in the drawing.
pub(super) fn parse_picture<R: Read + Seek>(
    archive: &mut zip::ZipArchive<R>,
    ws: &mut Worksheet,
    anchor: &XmlNode,
    drawing_rels: &HashMap<String, (String, String)>,
    z: i32,
) -> Option<Picture> {
    let pic = child(anchor, "pic")?;
    let blip_fill = child(pic, "blipFill")?;
    let rid = child(blip_fill, "blip")?.attribute_ns(REL_NS, "embed")?;
    let (t, media_path) = drawing_rels.get(rid)?;
    if !t.ends_with("/image") {
        return None;
    }
    let bytes = read_bytes(archive, media_path)?;
    if bytes.is_empty() {
        return None;
    }
    let xfrm_ext = path_child(pic, &["spPr", "xfrm"]).and_then(ext_of);
    let (anchor_rect, edit_as, size) = match anchor.tag_name() {
        "twoCellAnchor" => {
            let from = child(anchor, "from").and_then(super::charts::anchor_point)?;
            let to = child(anchor, "to").and_then(super::charts::anchor_point)?;
            let edit_as = match anchor.attribute("editAs") {
                Some("oneCell") => PictureEditAs::OneCell,
                Some("absolute") => PictureEditAs::Absolute,
                _ => PictureEditAs::TwoCell,
            };
            (ChartAnchor { from, to }, edit_as, None)
        }
        "oneCellAnchor" => {
            let from = child(anchor, "from").and_then(super::charts::anchor_point)?;
            let (cx, cy) = ext_of(anchor).or(xfrm_ext)?;
            (ChartAnchor { from, to: advance_anchor(ws, from, cx, cy) }, PictureEditAs::OneCell, Some((cx, cy)))
        }
        "absoluteAnchor" => {
            let pos = child(anchor, "pos")?;
            let x: i64 = pos.attribute("x")?.trim().parse().ok()?;
            let y: i64 = pos.attribute("y")?.trim().parse().ok()?;
            let (cx, cy) = ext_of(anchor).or(xfrm_ext)?;
            let origin = AnchorPoint { row: 1, column: 1, row_offset: 0, column_offset: 0 };
            let from = advance_anchor(ws, origin, x.max(0), y.max(0));
            (ChartAnchor { from, to: advance_anchor(ws, from, cx, cy) }, PictureEditAs::Absolute, Some((cx, cy)))
        }
        _ => return None,
    };
    // The size: what the anchor spans (two-cell), else the stated size.
    let spanned = anchor_extent(ws, &anchor_rect);
    let (cx, cy) = match (edit_as, size, xfrm_ext) {
        (PictureEditAs::TwoCell, _, _) if spanned.0 > 0 && spanned.1 > 0 => spanned,
        (_, Some(s), _) => s,
        (_, None, Some(s)) => s,
        _ if spanned.0 > 0 && spanned.1 > 0 => spanned,
        _ => {
            let (w, h) = image_pixel_size(&bytes)?;
            (w as i64 * 9525, h as i64 * 9525)
        }
    };
    let (name, descr) = names_of(pic);
    let a = anchor_rect;
    // Foglio writes "Place in Cell" pictures as two-cell anchors fitted in their cell: read those back as in-cell.
    let in_cell = edit_as == PictureEditAs::TwoCell && is_fitted_in_cell(ws, &a);
    let image = store_image(&mut ws.images, &bytes);
    Some(Picture {
        name,
        descr,
        image,
        anchor: a,
        cx,
        cy,
        edit_as,
        crop: crop_of(blip_fill),
        in_cell,
        z,
        group: 0,
    })
}

/// `cNvPr/@name` and `@descr` of an `xdr:pic`.
fn names_of(pic: &XmlNode) -> (String, String) {
    let c_nv_pr = path_child(pic, &["nvPicPr", "cNvPr"]);
    let name = c_nv_pr.and_then(|n| n.attribute("name")).unwrap_or("").to_string();
    let descr = c_nv_pr.and_then(|n| n.attribute("descr")).unwrap_or("").to_string();
    (name, descr)
}

/// True for a two-cell anchor exactly as Foglio writes an in-cell picture: inside one cell, centred, fitted to it
/// with the aspect ratio kept ([`fit_in_cell`], 1 px tolerance). Any other picture that happens to sit inside one
/// cell (a logo in a header cell, a product photo in a tall row) stays a floating picture where the file puts it.
fn is_fitted_in_cell(ws: &Worksheet, a: &ChartAnchor) -> bool {
    if a.from.row != a.to.row || a.from.column != a.to.column {
        return false;
    }
    let (cx, cy) = anchor_extent(ws, a);
    if cx <= 0 || cy <= 0 {
        return false;
    }
    let f = fit_in_cell(ws, a.from.row, a.from.column, cx, cy);
    let near = |x: i64, y: i64| (x - y).abs() <= EMU_PER_PIXEL;
    near(f.from.column_offset, a.from.column_offset)
        && near(f.from.row_offset, a.from.row_offset)
        && near(f.to.column_offset, a.to.column_offset)
        && near(f.to.row_offset, a.to.row_offset)
}

/// `a:off` (x, y) of an `a:xfrm`, `a:chOff` with `name = "chOff"`.
fn point_of(xfrm: &XmlNode, name: &str) -> Option<(f64, f64)> {
    let n = child(xfrm, name)?;
    Some((n.attribute("x")?.trim().parse().ok()?, n.attribute("y")?.trim().parse().ok()?))
}

/// `a:ext` / `a:chExt` (cx, cy) of an `a:xfrm`, zero sizes allowed.
fn size_of(xfrm: &XmlNode, name: &str) -> Option<(f64, f64)> {
    let n = child(xfrm, name)?;
    Some((n.attribute("cx")?.trim().parse().ok()?, n.attribute("cy")?.trim().parse().ok()?))
}

/// Maps coordinates of a group's child space to EMU from the top-left corner of the anchor: `p * scale + offset`.
#[derive(Clone, Copy)]
struct GroupTransform {
    scale: (f64, f64),
    offset: (f64, f64),
}

impl GroupTransform {
    /// The transform of the children of `group` (an `xdr:grpSp`) given the one of its own coordinates
    /// (`a:xfrm` off/ext place the group in its parent; `chOff`/`chExt` are the coordinates its children use).
    fn children_of(self, group: &XmlNode) -> Option<GroupTransform> {
        let xfrm = path_child(group, &["grpSpPr", "xfrm"])?;
        let off = point_of(xfrm, "off").unwrap_or((0.0, 0.0));
        let ext = size_of(xfrm, "ext")?;
        let ch_off = point_of(xfrm, "chOff").unwrap_or(off);
        let ch_ext = size_of(xfrm, "chExt").unwrap_or(ext);
        if ch_ext.0 <= 0.0 || ch_ext.1 <= 0.0 {
            return None;
        }
        let k = (ext.0 / ch_ext.0, ext.1 / ch_ext.1);
        Some(GroupTransform {
            scale: (self.scale.0 * k.0, self.scale.1 * k.1),
            offset: (
                self.offset.0 + self.scale.0 * (off.0 - ch_off.0 * k.0),
                self.offset.1 + self.scale.1 * (off.1 - ch_off.1 * k.1),
            ),
        })
    }
}

/// The pictures of a drawing anchor holding a group shape (`xdr:grpSp`, groups nested at any depth): each becomes
/// a picture of its own, placed where the group puts it inside the anchor and following the cells like the
/// anchor (`editAs`). Other members of the group (shapes, connectors, text boxes) are skipped, like elsewhere.
/// `z` is the stacking position of the first picture; it advances by one per picture.
pub(super) fn parse_group_pictures<R: Read + Seek>(
    archive: &mut zip::ZipArchive<R>,
    ws: &mut Worksheet,
    anchor: &XmlNode,
    drawing_rels: &HashMap<String, (String, String)>,
    z: &mut i32,
) -> Vec<Picture> {
    let mut out = vec![];
    let Some(group) = child(anchor, "grpSp") else { return out };
    let Some(group_xfrm) = path_child(group, &["grpSpPr", "xfrm"]) else { return out };
    let group_off = point_of(group_xfrm, "off").unwrap_or((0.0, 0.0));
    let group_ext = size_of(group_xfrm, "ext").unwrap_or((0.0, 0.0));
    // Where the anchor puts the group on the sheet, and its size there (EMU).
    let (from, edit_as, (aw, ah)) = match anchor.tag_name() {
        "twoCellAnchor" => {
            let Some(from) = child(anchor, "from").and_then(super::charts::anchor_point) else { return out };
            let Some(to) = child(anchor, "to").and_then(super::charts::anchor_point) else { return out };
            let edit_as = match anchor.attribute("editAs") {
                Some("oneCell") => PictureEditAs::OneCell,
                Some("absolute") => PictureEditAs::Absolute,
                _ => PictureEditAs::TwoCell,
            };
            (from, edit_as, anchor_extent(ws, &ChartAnchor { from, to }))
        }
        "oneCellAnchor" => {
            let Some(from) = child(anchor, "from").and_then(super::charts::anchor_point) else { return out };
            let Some(size) = ext_of(anchor) else { return out };
            (from, PictureEditAs::OneCell, size)
        }
        "absoluteAnchor" => {
            let Some(pos) = child(anchor, "pos") else { return out };
            let (Some(x), Some(y)) = (
                pos.attribute("x").and_then(|v| v.trim().parse::<i64>().ok()),
                pos.attribute("y").and_then(|v| v.trim().parse::<i64>().ok()),
            ) else {
                return out;
            };
            let Some(size) = ext_of(anchor) else { return out };
            let origin = AnchorPoint { row: 1, column: 1, row_offset: 0, column_offset: 0 };
            (advance_anchor(ws, origin, x.max(0), y.max(0)), PictureEditAs::Absolute, size)
        }
        _ => return out,
    };
    // A group squeezed to nothing (Excel files have such leftovers) shows nothing.
    if aw <= 0 || ah <= 0 || group_ext.0 <= 0.0 || group_ext.1 <= 0.0 {
        return out;
    }
    // The group's own coordinates (its a:off/a:ext) span the anchor.
    let sx = aw as f64 / group_ext.0;
    let sy = ah as f64 / group_ext.1;
    let outer = GroupTransform { scale: (sx, sy), offset: (-group_off.0 * sx, -group_off.1 * sy) };
    let Some(t) = outer.children_of(group) else { return out };
    collect_group(archive, ws, group, t, from, edit_as, drawing_rels, z, &mut out, 0);
    // One group number per top-level group, so saving writes the group back.
    if out.len() > 1 {
        let id = ws.pictures.iter().map(|p| p.group).max().unwrap_or(0) + 1;
        for p in &mut out {
            p.group = id;
        }
    }
    out
}

#[allow(clippy::too_many_arguments)]
fn collect_group<R: Read + Seek>(
    archive: &mut zip::ZipArchive<R>,
    ws: &mut Worksheet,
    group: &XmlNode,
    t: GroupTransform,
    from: AnchorPoint,
    edit_as: PictureEditAs,
    drawing_rels: &HashMap<String, (String, String)>,
    z: &mut i32,
    out: &mut Vec<Picture>,
    depth: usize,
) {
    if depth > 32 {
        return;
    }
    for node in group.children() {
        if node.has_tag_name("grpSp") {
            if let Some(inner) = t.children_of(node) {
                collect_group(archive, ws, node, inner, from, edit_as, drawing_rels, z, out, depth + 1);
            }
            continue;
        }
        if !node.has_tag_name("pic") {
            continue;
        }
        let Some(p) = group_picture(archive, ws, node, t, from, edit_as, drawing_rels, *z) else { continue };
        out.push(p);
        *z += 1;
    }
}

#[allow(clippy::too_many_arguments)]
fn group_picture<R: Read + Seek>(
    archive: &mut zip::ZipArchive<R>,
    ws: &mut Worksheet,
    pic: &XmlNode,
    t: GroupTransform,
    from: AnchorPoint,
    edit_as: PictureEditAs,
    drawing_rels: &HashMap<String, (String, String)>,
    z: i32,
) -> Option<Picture> {
    let blip_fill = child(pic, "blipFill")?;
    let rid = child(blip_fill, "blip")?.attribute_ns(REL_NS, "embed")?;
    let (kind, media_path) = drawing_rels.get(rid)?;
    if !kind.ends_with("/image") {
        return None;
    }
    let xfrm = path_child(pic, &["spPr", "xfrm"])?;
    let off = point_of(xfrm, "off")?;
    let ext = size_of(xfrm, "ext")?;
    // EMU from the anchor's top-left corner.
    let x0 = (off.0 * t.scale.0 + t.offset.0).round().max(0.0) as i64;
    let y0 = (off.1 * t.scale.1 + t.offset.1).round().max(0.0) as i64;
    let cx = (ext.0 * t.scale.0).round() as i64;
    let cy = (ext.1 * t.scale.1).round() as i64;
    if cx <= 0 || cy <= 0 {
        return None;
    }
    let bytes = read_bytes(archive, media_path)?;
    if bytes.is_empty() {
        return None;
    }
    let anchor = ChartAnchor { from: advance_anchor(ws, from, x0, y0), to: advance_anchor(ws, from, x0 + cx, y0 + cy) };
    let (name, descr) = names_of(pic);
    let image = store_image(&mut ws.images, &bytes);
    Some(Picture { name, descr, image, anchor, cx, cy, edit_as, crop: crop_of(blip_fill), in_cell: false, z, group: 0 })
}

// ---------------------------------------------------------------------------
// Excel 365 pictures in cells (rich values)
// ---------------------------------------------------------------------------

/// For each value-metadata index (`vm`, 1-based): the image part and alt text
/// of the `_localImage` rich value it points to.
#[derive(Default)]
pub(super) struct RichValueImages {
    by_vm: HashMap<u32, (String, String)>,
}

impl RichValueImages {
    /// Reads `xl/metadata.xml` and `xl/richData/*`. Empty if the workbook has
    /// no pictures in cells (or anything is missing).
    pub(super) fn load<R: Read + Seek>(archive: &mut zip::ZipArchive<R>) -> RichValueImages {
        Self::try_load(archive).unwrap_or_default()
    }

    pub(super) fn is_empty(&self) -> bool {
        self.by_vm.is_empty()
    }

    fn try_load<R: Read + Seek>(archive: &mut zip::ZipArchive<R>) -> Option<RichValueImages> {
        let has_rich_data = (0..archive.len())
            .filter_map(|i| archive.name_for_index(i).and_then(|r| r.ok()))
            .any(|n| n.to_ascii_lowercase().starts_with("xl/richdata/"));
        if !has_rich_data {
            return None;
        }
        let metadata = read_xml(archive, "xl/metadata.xml")?;
        // metadataTypes: 1-based index of XLRICHVALUE
        let types = child(&metadata, "metadataTypes")?;
        let rich_type = types
            .children()
            .filter(|n| n.has_tag_name("metadataType"))
            .position(|n| n.attribute("name") == Some("XLRICHVALUE"))?
            + 1;
        // futureMetadata name="XLRICHVALUE": bk -> rvb/@i (rich value index)
        let future = metadata
            .children()
            .find(|n| n.has_tag_name("futureMetadata") && n.attribute("name") == Some("XLRICHVALUE"))?;
        let rv_of_bk: Vec<Option<usize>> = future
            .children()
            .filter(|n| n.has_tag_name("bk"))
            .map(|bk| {
                bk.descendants()
                    .find(|n| n.has_tag_name("rvb"))
                    .and_then(|n| n.attribute("i"))
                    .and_then(|i| i.trim().parse().ok())
            })
            .collect();
        // Structures: position of the image key in each.
        let structures = read_xml(archive, "xl/richData/rdrichvaluestructure.xml")?;
        let keys: Vec<(bool, Option<usize>, Option<usize>)> = structures
            .children()
            .filter(|n| n.has_tag_name("s"))
            .map(|s| {
                let ks: Vec<&str> = s.children().filter(|k| k.has_tag_name("k")).map(|k| k.attribute("n").unwrap_or("")).collect();
                (
                    s.attribute("t") == Some("_localImage"),
                    ks.iter().position(|k| *k == "_rvRel:LocalImageIdentifier"),
                    ks.iter().position(|k| *k == "Text"),
                )
            })
            .collect();
        let values = read_xml(archive, "xl/richData/rdrichvalue.xml")?;
        let rich_values: Vec<Option<(usize, String)>> = values
            .children()
            .filter(|n| n.has_tag_name("rv"))
            .map(|rv| {
                let s: usize = rv.attribute("s")?.trim().parse().ok()?;
                let (is_image, image_key, text_key) = *keys.get(s)?;
                if !is_image {
                    return None;
                }
                let vs: Vec<String> = rv.children().filter(|v| v.has_tag_name("v")).map(|v| v.text().unwrap_or("").to_string()).collect();
                let rel: usize = vs.get(image_key?)?.trim().parse().ok()?;
                let text = text_key.and_then(|k| vs.get(k).cloned()).unwrap_or_default();
                Some((rel, text))
            })
            .collect();
        let rel_part = "xl/richData/richValueRel.xml";
        let rel_list = read_xml(archive, rel_part)?;
        let rel_ids: Vec<Option<String>> = rel_list
            .children()
            .filter(|n| n.has_tag_name("rel"))
            .map(|n| n.attribute_ns(REL_NS, "id").map(str::to_string))
            .collect();
        let rels = load_rels(archive, rel_part);
        // valueMetadata: vm (1-based) -> bk -> rc t/v
        let value_md = child(&metadata, "valueMetadata")?;
        let mut by_vm = HashMap::new();
        for (i, bk) in value_md.children().filter(|n| n.has_tag_name("bk")).enumerate() {
            let Some(rc) = child(bk, "rc") else { continue };
            let t: Option<usize> = rc.attribute("t").and_then(|t| t.trim().parse().ok());
            let v: Option<usize> = rc.attribute("v").and_then(|v| v.trim().parse().ok());
            if t != Some(rich_type) {
                continue;
            }
            let Some(Some(rv)) = v.and_then(|v| rv_of_bk.get(v).copied()) else { continue };
            let Some(Some((rel, text))) = rich_values.get(rv) else { continue };
            let Some(Some(rid)) = rel_ids.get(*rel) else { continue };
            let Some((rel_type, target)) = rels.get(rid) else { continue };
            if rel_type.ends_with("/image") {
                by_vm.insert(i as u32 + 1, (target.clone(), text.clone()));
            }
        }
        Some(RichValueImages { by_vm })
    }

    /// Cells of the sheet part that show a rich-value image: (row, column, vm).
    fn image_cells<R: Read + Seek>(&self, archive: &mut zip::ZipArchive<R>, sheet_path: &str) -> Vec<(i32, i32, u32)> {
        let mut out = vec![];
        let name = if archive.index_for_name(sheet_path).is_some() {
            sheet_path.to_string()
        } else {
            match (0..archive.len())
                .filter_map(|i| archive.name_for_index(i).and_then(|r| r.ok()).map(|n| n.to_string()))
                .find(|n| n.eq_ignore_ascii_case(sheet_path))
            {
                Some(n) => n,
                None => return out,
            }
        };
        let Ok(file) = archive.by_name(&name) else { return out };
        let mut reader = quick_xml::Reader::from_reader(BufReader::new(file));
        let mut buffer = Vec::new();
        loop {
            let event = match reader.read_event_into(&mut buffer) {
                Ok(e) => e,
                Err(_) => break,
            };
            match &event {
                quick_xml::events::Event::Eof => break,
                quick_xml::events::Event::Start(e) | quick_xml::events::Event::Empty(e) if e.local_name().as_ref() == "c" => {
                    let (mut r, mut vm) = (None, None);
                    for a in e.attributes().flatten() {
                        match a.key.local_name().as_ref() {
                            "r" => r = Some(a.value.to_string()),
                            "vm" => vm = a.value.trim().parse::<u32>().ok(),
                            _ => {}
                        }
                    }
                    if let (Some(r), Some(vm)) = (r, vm) {
                        if self.by_vm.contains_key(&vm) {
                            if let Some((row, column)) = parse_reference(&r) {
                                out.push((row, column, vm));
                            }
                        }
                    }
                }
                _ => {}
            }
            buffer.clear();
        }
        out
    }

    /// Adds the in-cell pictures of the sheet stored at `sheet_path` and empties their cells.
    pub(super) fn add_to_sheet<R: Read + Seek>(&self, archive: &mut zip::ZipArchive<R>, sheet_path: &str, ws: &mut Worksheet) {
        if self.is_empty() {
            return;
        }
        let mut z = ws.charts.iter().map(|c| c.z).chain(ws.pictures.iter().map(|p| p.z)).max().map_or(0, |z| z + 1);
        for (row, column, vm) in self.image_cells(archive, sheet_path) {
            let Some((path, text)) = self.by_vm.get(&vm) else { continue };
            let Some(bytes) = read_bytes(archive, path) else { continue };
            if image_format(&bytes) == "bin" {
                continue;
            }
            let (w, h) = image_pixel_size(&bytes).unwrap_or((100, 100));
            let (cx, cy) = (w as i64 * 9525, h as i64 * 9525);
            let image = store_image(&mut ws.images, &bytes);
            let _ = ws.cell_clear_contents(row, column);
            let n = ws.pictures.len() + 1;
            ws.pictures.push(Picture {
                name: format!("Picture in cell {n}"),
                descr: text.clone(),
                image,
                anchor: fit_in_cell(ws, row, column, cx, cy),
                cx,
                cy,
                edit_as: PictureEditAs::TwoCell,
                crop: PictureCrop::default(),
                in_cell: true,
                z,
                group: 0,
            });
            z += 1;
        }
    }
}

/// "B12" -> (12, 2)
fn parse_reference(r: &str) -> Option<(i32, i32)> {
    let letters: String = r.chars().take_while(|c| c.is_ascii_alphabetic()).collect();
    let digits = r[letters.len()..].trim_start_matches('$');
    let letters = letters.trim_start_matches('$');
    let column = ironcalc_base::expressions::utils::column_to_number(&letters.to_ascii_uppercase()).ok()?;
    let row: i32 = digits.parse().ok()?;
    (row >= 1 && row <= 1_048_576 && column >= 1).then_some((row, column))
}
