//! Foglio fork: writes pictures (see ironcalc_base/src/pictures.rs).
//!
//! Pictures share the sheet's drawing part with charts (charts.rs writes the
//! part; this module gives it the `xdr:pic` anchors). Images go to
//! `xl/media/image{N}.{ext}`, numbered across the workbook; an image used by
//! several pictures (on any sheet) is written once. Every picture is a
//! `xdr:twoCellAnchor` with `editAs` (twoCell, oneCell or absolute), whose
//! `to` corner is computed from the size for one-cell/absolute pictures and
//! from the cell for pictures placed in a cell.

use std::collections::HashMap;

use ironcalc_base::{
    charts::AnchorPoint,
    pictures::{anchor_position, export_anchor, image_content_type, image_format, picture_extent, Picture, PictureEditAs},
    types::{Workbook, Worksheet},
};

use super::escape::escape_xml;

const NS_R: &str = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";

/// True if the picture can be written (its image is known and in a format
/// Excel reads).
pub(crate) fn is_exportable(ws: &Worksheet, p: &Picture) -> bool {
    ws.images.get(&p.image).is_some_and(|b| image_content_type(image_format(b)).is_some())
}

/// The images written to `xl/media`: image key -> (number, extension), in
/// order of first use.
pub(crate) struct Media {
    pub(crate) list: Vec<(String, usize, &'static str)>,
    index: HashMap<String, usize>,
}

impl Media {
    pub(crate) fn of(workbook: &Workbook) -> Media {
        let mut list = vec![];
        let mut index = HashMap::new();
        for ws in &workbook.worksheets {
            for p in &ws.pictures {
                if !is_exportable(ws, p) || index.contains_key(&p.image) {
                    continue;
                }
                let ext = image_format(&ws.images[&p.image]);
                let n = list.len() + 1;
                index.insert(p.image.clone(), n);
                list.push((p.image.clone(), n, ext));
            }
        }
        Media { list, index }
    }

    /// Number and extension of an image.
    pub(crate) fn get(&self, key: &str) -> Option<(usize, &'static str)> {
        self.index.get(key).and_then(|i| self.list.get(i - 1)).map(|(_, n, e)| (*n, *e))
    }

    /// `<Default>` content types for the image extensions in use.
    pub(crate) fn content_types(&self) -> Vec<String> {
        let mut exts: Vec<&str> = self.list.iter().map(|(_, _, e)| *e).collect();
        exts.sort();
        exts.dedup();
        exts.into_iter()
            .filter_map(|e| image_content_type(e).map(|t| format!(r#"<Default Extension="{e}" ContentType="{t}"/>"#)))
            .collect()
    }
}

/// Relationship id of image number `n` in a drawing's rels.
pub(crate) fn image_rel_id(n: usize) -> String {
    format!("rIdImg{n}")
}

/// Drawing rels entry for image number `n`.
pub(crate) fn image_rel_xml(n: usize, ext: &str) -> String {
    format!(
        r#"<Relationship Id="{}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image{n}.{ext}"/>"#,
        image_rel_id(n)
    )
}

fn point(tag: &str, p: &AnchorPoint) -> String {
    format!(
        "<xdr:{tag}><xdr:col>{}</xdr:col><xdr:colOff>{}</xdr:colOff><xdr:row>{}</xdr:row><xdr:rowOff>{}</xdr:rowOff></xdr:{tag}>",
        (p.column - 1).max(0),
        p.column_offset.max(0),
        (p.row - 1).max(0),
        p.row_offset.max(0)
    )
}

/// The `xdr:twoCellAnchor` of a picture (`id`: unique shape id in the drawing).
pub(crate) fn anchor_xml(ws: &Worksheet, p: &Picture, id: usize, media: &Media) -> Option<String> {
    let (n, _) = media.get(&p.image)?;
    let a = export_anchor(ws, p);
    let (x, y) = anchor_position(ws, &a.from);
    let (cx, cy) = if p.in_cell {
        ironcalc_base::pictures::anchor_extent(ws, &a)
    } else {
        picture_extent(ws, p)
    };
    let edit_as = if p.in_cell { PictureEditAs::TwoCell } else { p.edit_as };
    let name = if p.name.is_empty() { format!("Picture {id}") } else { p.name.clone() };
    let descr = if p.descr.is_empty() { String::new() } else { format!(r#" descr="{}""#, escape_xml(&p.descr)) };
    let c = p.crop;
    let src_rect = if c.is_empty() {
        String::new()
    } else {
        let attr = |n: &str, v: i32| if v != 0 { format!(r#" {n}="{v}""#) } else { String::new() };
        format!("<a:srcRect{}{}{}{}/>", attr("l", c.l), attr("t", c.t), attr("r", c.r), attr("b", c.b))
    };
    Some(format!(
        r#"<xdr:twoCellAnchor editAs="{}">{}{}<xdr:pic><xdr:nvPicPr><xdr:cNvPr id="{id}" name="{}"{descr}/><xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr><xdr:blipFill><a:blip xmlns:r="{NS_R}" r:embed="{}"/>{src_rect}<a:stretch><a:fillRect/></a:stretch></xdr:blipFill><xdr:spPr><a:xfrm><a:off x="{}" y="{}"/><a:ext cx="{}" cy="{}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/></xdr:twoCellAnchor>"#,
        edit_as.xml_name(),
        point("from", &a.from),
        point("to", &a.to),
        escape_xml(&name),
        image_rel_id(n),
        x.max(0),
        y.max(0),
        cx.max(1),
        cy.max(1),
    ))
}
