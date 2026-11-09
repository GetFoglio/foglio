//! Foglio fork: reads the charts of a worksheet.
//!
//! worksheet rels --drawing--> xl/drawings/drawingN.xml (anchors)
//!   drawing rels --chart--> xl/charts/chartM.xml (DrawingML chart)
//!
//! Pictures in the same drawing part are read by pictures.rs.
//!
//! Tolerant by design: anything unexpected skips that chart (or that part of
//! it) and never fails the load of the workbook.

use std::collections::HashMap;
use std::io::{BufReader, Read, Seek};

use ironcalc_base::charts::{
    advance_anchor, AnchorPoint, Chart, ChartAnchor, ChartKind, ChartSeries, LegendPosition,
};
use ironcalc_base::types::Worksheet;

use super::xml::XmlNode;

pub(super) const REL_NS: &str = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";

pub(super) fn child<'a>(node: &'a XmlNode, name: &str) -> Option<&'a XmlNode> {
    node.children().find(|n| n.has_tag_name(name))
}

pub(super) fn path_child<'a>(node: &'a XmlNode, path: &[&str]) -> Option<&'a XmlNode> {
    let mut n = node;
    for p in path {
        n = child(n, p)?;
    }
    Some(n)
}

fn val<'a>(node: &'a XmlNode, name: &str) -> Option<&'a str> {
    child(node, name)?.attribute("val")
}

fn text_of(node: &XmlNode) -> String {
    node.text().unwrap_or("").to_string()
}

pub(super) fn read_xml<R: Read + Seek>(archive: &mut zip::ZipArchive<R>, path: &str) -> Option<XmlNode> {
    // Part names are case-insensitive in OPC (some generators write "Sheet1.xml" for "sheet1.xml").
    let name = if archive.index_for_name(path).is_some() {
        path.to_string()
    } else {
        (0..archive.len())
            .filter_map(|i| archive.name_for_index(i).and_then(|r| r.ok()).map(|n| n.to_string()))
            .find(|n| n.eq_ignore_ascii_case(path))?
    };
    let file = archive.by_name(&name).ok()?;
    XmlNode::parse(BufReader::new(file)).ok()
}

/// "xl/worksheets/sheet1.xml" -> "xl/worksheets/_rels/sheet1.xml.rels"
fn rels_path(part: &str) -> String {
    match part.rfind('/') {
        Some(i) => format!("{}/_rels/{}.rels", &part[..i], &part[i + 1..]),
        None => format!("_rels/{part}.rels"),
    }
}

/// Resolves a relationship target relative to the part that owns it.
fn resolve(part: &str, target: &str) -> String {
    if let Some(abs) = target.strip_prefix('/') {
        return abs.to_string();
    }
    let mut segments: Vec<&str> = part.split('/').collect();
    segments.pop();
    for s in target.split('/') {
        match s {
            ".." => {
                segments.pop();
            }
            "." | "" => {}
            s => segments.push(s),
        }
    }
    segments.join("/")
}

/// Relationship id -> (type, resolved target)
pub(super) fn load_rels<R: Read + Seek>(archive: &mut zip::ZipArchive<R>, part: &str) -> HashMap<String, (String, String)> {
    let mut out = HashMap::new();
    if let Some(doc) = read_xml(archive, &rels_path(part)) {
        for rel in doc.children().filter(|n| n.has_tag_name("Relationship")) {
            if let (Some(id), Some(t), Some(target)) = (rel.attribute("Id"), rel.attribute("Type"), rel.attribute("Target")) {
                if rel.attribute("TargetMode") == Some("External") {
                    continue;
                }
                out.insert(id.to_string(), (t.to_string(), resolve(part, target)));
            }
        }
    }
    out
}

pub(super) fn anchor_point(node: &XmlNode) -> Option<AnchorPoint> {
    let num = |name: &str| -> Option<i64> { child(node, name)?.text()?.trim().parse::<i64>().ok() };
    Some(AnchorPoint {
        row: num("row")? as i32 + 1,
        column: num("col")? as i32 + 1,
        row_offset: num("rowOff").unwrap_or(0).max(0),
        column_offset: num("colOff").unwrap_or(0).max(0),
    })
}

/// Text of `c:tx/c:rich` (paragraphs joined with a space) or of a `c:strRef` cache.
fn rich_text(tx: &XmlNode) -> Option<String> {
    if let Some(rich) = child(tx, "rich") {
        let paragraphs: Vec<String> = rich
            .children()
            .filter(|n| n.has_tag_name("p"))
            .map(|p| p.descendants().filter(|n| n.has_tag_name("t")).map(text_of).collect::<String>())
            .filter(|s| !s.is_empty())
            .collect();
        return Some(paragraphs.join(" "));
    }
    if let Some(sr) = child(tx, "strRef") {
        return path_child(sr, &["strCache", "pt", "v"]).map(text_of);
    }
    child(tx, "v").map(text_of)
}

/// `Some(Some(text))` explicit title, `Some(None)` automatic title, `None` no title.
fn title_of(node: &XmlNode) -> Option<Option<String>> {
    let title = child(node, "title")?;
    Some(child(title, "tx").and_then(rich_text).filter(|t| !t.is_empty()))
}

fn formula_of(node: &XmlNode) -> Option<String> {
    for kind in ["strRef", "numRef", "multiLvlStrRef"] {
        if let Some(f) = path_child(node, &[kind, "f"]) {
            let f = text_of(f).trim().trim_start_matches('=').to_string();
            if !f.is_empty() {
                return Some(f);
            }
        }
    }
    None
}

fn srgb(node: Option<&XmlNode>) -> Option<String> {
    let fill = child(node?, "solidFill")?;
    let c = child(fill, "srgbClr")?.attribute("val")?;
    (c.len() == 6 && c.chars().all(|c| c.is_ascii_hexdigit())).then(|| c.to_uppercase())
}

fn series_of(ser: &XmlNode, line_like: bool) -> Option<ChartSeries> {
    let values_ref = child(ser, "val").or_else(|| child(ser, "yVal")).and_then(formula_of)?;
    let categories_ref = child(ser, "cat").or_else(|| child(ser, "xVal")).and_then(formula_of);
    let (mut name_ref, mut name) = (None, None);
    if let Some(tx) = child(ser, "tx") {
        if let Some(sr) = child(tx, "strRef") {
            name_ref = path_child(sr, &["f"]).map(|f| text_of(f).trim().trim_start_matches('=').to_string());
            name = path_child(sr, &["strCache", "pt", "v"]).map(text_of);
        } else if let Some(v) = child(tx, "v") {
            name = Some(text_of(v));
        }
    }
    let sp = child(ser, "spPr");
    let color = if line_like {
        srgb(sp.and_then(|s| child(s, "ln"))).or_else(|| srgb(sp))
    } else {
        srgb(sp)
    };
    Some(ChartSeries { name_ref, name, categories_ref, values_ref, color })
}

fn axis_title(plot_area: &XmlNode, ax_id: Option<&str>) -> Option<String> {
    let ax_id = ax_id?;
    let axis = plot_area
        .children()
        .find(|n| matches!(n.tag_name(), "catAx" | "valAx" | "dateAx" | "serAx") && val(n, "axId") == Some(ax_id))?;
    let title = child(axis, "title")?;
    child(title, "tx").and_then(rich_text).filter(|t| !t.is_empty()).or(Some("Axis Title".to_string()))
}

/// Parses a chart part. `None` if it holds nothing Foglio can draw.
fn parse_chart(doc: &XmlNode, name: String, anchor: ChartAnchor, z: i32) -> Option<Chart> {
    let chart = child(doc, "chart")?;
    let plot_area = child(chart, "plotArea")?;
    let mut kind = None;
    let mut series = Vec::new();
    let mut axis_ids: Vec<String> = Vec::new();
    for group in plot_area.children() {
        let tag = group.tag_name();
        let k = match tag {
            "barChart" | "bar3DChart" => {
                let horizontal = val(group, "barDir") == Some("bar");
                let stacked = matches!(val(group, "grouping"), Some("stacked") | Some("percentStacked"));
                match (horizontal, stacked) {
                    (false, false) => ChartKind::Column,
                    (false, true) => ChartKind::ColumnStacked,
                    (true, false) => ChartKind::Bar,
                    (true, true) => ChartKind::BarStacked,
                }
            }
            "lineChart" | "line3DChart" | "stockChart" | "radarChart" => {
                // Markers are on unless the group or every series turns them off.
                let group_marker = val(group, "marker") != Some("0");
                let series_markers = group
                    .children()
                    .filter(|s| s.has_tag_name("ser"))
                    .any(|s| path_child(s, &["marker", "symbol"]).and_then(|m| m.attribute("val")) != Some("none"));
                if tag == "lineChart" && group_marker && series_markers {
                    ChartKind::LineMarkers
                } else {
                    ChartKind::Line
                }
            }
            "pieChart" | "pie3DChart" | "ofPieChart" => ChartKind::Pie,
            "doughnutChart" => ChartKind::Doughnut,
            "areaChart" | "area3DChart" => {
                if matches!(val(group, "grouping"), Some("stacked") | Some("percentStacked")) {
                    ChartKind::AreaStacked
                } else {
                    ChartKind::Area
                }
            }
            "scatterChart" | "bubbleChart" => ChartKind::Scatter,
            "surfaceChart" | "surface3DChart" => ChartKind::Column,
            _ => continue,
        };
        // Combination charts: the first group decides the type, all series are kept.
        if kind.is_none() {
            kind = Some(k);
            axis_ids = group
                .children()
                .filter(|n| n.has_tag_name("axId"))
                .filter_map(|n| n.attribute("val").map(str::to_string))
                .collect();
        }
        let line_like = matches!(k, ChartKind::Line | ChartKind::LineMarkers | ChartKind::Scatter);
        let mut sers: Vec<(i64, ChartSeries)> = group
            .children()
            .filter(|s| s.has_tag_name("ser"))
            .filter_map(|s| {
                let order = val(s, "order").and_then(|o| o.parse().ok()).unwrap_or(0);
                series_of(s, line_like).map(|x| (order, x))
            })
            .collect();
        sers.sort_by_key(|(o, _)| *o);
        series.extend(sers.into_iter().map(|(_, s)| s));
    }
    let kind = kind?;
    if series.is_empty() {
        return None;
    }
    // Title: explicit text, or automatic (the series name when there is one series).
    let auto_deleted = val(chart, "autoTitleDeleted") == Some("1");
    let title = match title_of(chart) {
        Some(Some(t)) => Some(t),
        Some(None) => Some(String::new()),
        None if !auto_deleted && series.len() == 1 => Some(String::new()),
        None => None,
    }
    .map(|t| {
        if t.is_empty() {
            series[0].name.clone().unwrap_or_else(|| "Chart Title".to_string())
        } else {
            t
        }
    });
    let legend = match child(chart, "legend") {
        None => LegendPosition::None,
        Some(l) => match val(l, "legendPos") {
            Some("r") | Some("tr") => LegendPosition::Right,
            Some("t") => LegendPosition::Top,
            Some("l") => LegendPosition::Left,
            Some("b") => LegendPosition::Bottom,
            _ => LegendPosition::Right,
        },
    };
    // Axis titles: the category axis (X of scatter) is the one at the bottom
    // (left for horizontal bars); the value axis the other one.
    let (mut cat_title, mut val_title) = (None, None);
    if kind.has_axes() && axis_ids.len() >= 2 {
        let pos = |id: &str| {
            plot_area
                .children()
                .find(|n| val(n, "axId") == Some(id) && n.tag_name().ends_with("Ax"))
                .map(|n| (n.tag_name().to_string(), val(n, "axPos").unwrap_or("b").to_string()))
        };
        let (a, b) = (axis_ids[0].as_str(), axis_ids[1].as_str());
        // By convention the first axis id is the category (X) axis.
        let a_is_cat = match (pos(a), pos(b), kind) {
            (Some((_, pa)), Some((_, pb)), ChartKind::Scatter) => {
                !((pa == "l" || pa == "r") && (pb == "b" || pb == "t"))
            }
            (Some((ta, _)), Some((tb, _)), _) => !(ta == "valAx" && tb != "valAx"),
            _ => true,
        };
        let (c, v) = if a_is_cat { (a, b) } else { (b, a) };
        cat_title = axis_title(plot_area, Some(c));
        val_title = axis_title(plot_area, Some(v));
    }
    Some(Chart {
        name,
        kind,
        title,
        series,
        legend,
        category_axis_title: cat_title,
        value_axis_title: val_title,
        anchor,
        z,
    })
}

fn ext_of(node: &XmlNode) -> Option<(i64, i64)> {
    let ext = child(node, "ext")?;
    Some((ext.attribute("cx")?.parse().ok()?, ext.attribute("cy")?.parse().ok()?))
}

/// Two-cell anchor of `xdr:twoCellAnchor`, `xdr:oneCellAnchor` (from + size) or
/// `xdr:absoluteAnchor` (position + size).
fn anchor_of(ws: &Worksheet, anchor: &XmlNode) -> Option<ChartAnchor> {
    match anchor.tag_name() {
        "twoCellAnchor" => Some(ChartAnchor {
            from: child(anchor, "from").and_then(anchor_point)?,
            to: child(anchor, "to").and_then(anchor_point)?,
        }),
        "oneCellAnchor" => {
            let from = child(anchor, "from").and_then(anchor_point)?;
            let (cx, cy) = ext_of(anchor)?;
            Some(ChartAnchor { from, to: advance_anchor(ws, from, cx, cy) })
        }
        "absoluteAnchor" => {
            let pos = child(anchor, "pos")?;
            let x: i64 = pos.attribute("x")?.parse().ok()?;
            let y: i64 = pos.attribute("y")?.parse().ok()?;
            let (cx, cy) = ext_of(anchor)?;
            let origin = AnchorPoint { row: 1, column: 1, row_offset: 0, column_offset: 0 };
            let from = advance_anchor(ws, origin, x.max(0), y.max(0));
            Some(ChartAnchor { from, to: advance_anchor(ws, from, cx, cy) })
        }
        _ => None,
    }
}

/// The charts and pictures of the worksheet `ws` stored at `sheet_path`
/// (e.g. "xl/worksheets/sheet1.xml"), in `ws.charts` / `ws.pictures` (Foglio
/// fork: pictures share the drawing part with charts, see pictures.rs). The
/// position of an anchor in the drawing is the object's stacking order (`z`).
pub(super) fn load_sheet_drawings<R: Read + Seek>(
    archive: &mut zip::ZipArchive<R>,
    sheet_path: &str,
    ws: &mut Worksheet,
) {
    let sheet_rels = load_rels(archive, sheet_path);
    let mut drawings: Vec<String> = sheet_rels
        .iter()
        .filter(|(_, (t, _))| t.ends_with("/drawing"))
        .map(|(_, (_, target))| target.clone())
        .collect();
    drawings.sort();
    let mut z = -1;
    for drawing_path in drawings {
        let Some(drawing) = read_xml(archive, &drawing_path) else { continue };
        let drawing_rels = load_rels(archive, &drawing_path);
        // mc:AlternateContent: the anchor of the first choice that has one, else the fallback.
        let anchors: Vec<&XmlNode> = drawing
            .children()
            .flat_map(|n| -> Vec<&XmlNode> {
                if !n.has_tag_name("AlternateContent") {
                    return vec![n];
                }
                let is_anchor = |a: &&XmlNode| a.tag_name().ends_with("Anchor");
                n.children()
                    .filter(|c| c.has_tag_name("Choice"))
                    .chain(n.children().filter(|c| c.has_tag_name("Fallback")))
                    .map(|c| c.children().filter(is_anchor).collect::<Vec<_>>())
                    .find(|v| !v.is_empty())
                    .unwrap_or_default()
            })
            .collect();
        for anchor in anchors {
            z += 1;
            if child(anchor, "pic").is_some() {
                if let Some(p) = super::pictures::parse_picture(archive, ws, anchor, &drawing_rels, z) {
                    ws.pictures.push(p);
                }
                continue;
            }
            let Some(chart_anchor) = anchor_of(ws, anchor) else { continue };
            let Some(frame) = child(anchor, "graphicFrame") else { continue };
            let name = path_child(frame, &["nvGraphicFramePr", "cNvPr"])
                .and_then(|n| n.attribute("name"))
                .unwrap_or("")
                .to_string();
            let Some(chart_ref) = frame.descendants().find(|n| n.has_tag_name("chart")) else { continue };
            let Some(rid) = chart_ref.attribute_ns(REL_NS, "id") else { continue };
            let Some((t, chart_path)) = drawing_rels.get(rid) else { continue };
            if !t.ends_with("/chart") {
                continue;
            }
            let Some(doc) = read_xml(archive, chart_path) else { continue };
            if let Some(c) = parse_chart(&doc, name, chart_anchor, z) {
                ws.charts.push(c);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::resolve;
    use std::io::{Cursor, Read, Write};

    use ironcalc_base::charts::{Chart, ChartAnchor, ChartKind, ChartSeries};
    use ironcalc_base::UserModel;

    /// A saved workbook with two charts whose parts are then replaced by garbage
    /// and by an unknown chart type: the workbook still loads, without them.
    #[test]
    fn broken_chart_parts_do_not_fail_the_load() {
        let mut model = UserModel::new_empty("t", "en", "UTC", "en").unwrap();
        model.set_user_input(0, 1, 1, "5").unwrap();
        let chart = |kind| Chart {
            kind,
            series: vec![ChartSeries { values_ref: "Sheet1!$A$1:$A$3".into(), ..Default::default() }],
            anchor: ChartAnchor::default(),
            ..Default::default()
        };
        model.add_chart(0, chart(ChartKind::Column)).unwrap();
        model.add_chart(0, chart(ChartKind::Line)).unwrap();
        model.add_chart(0, chart(ChartKind::Pie)).unwrap();
        let bytes = crate::export::save_xlsx_to_writer(model.get_model(), Cursor::new(Vec::new())).unwrap().into_inner();

        let reload = |bytes: &[u8]| crate::import::load_from_xlsx_bytes(bytes, "t", "en", "UTC").unwrap();
        assert_eq!(reload(&bytes).worksheets[0].charts.len(), 3);

        let mut zin = zip::ZipArchive::new(Cursor::new(bytes)).unwrap();
        let mut zout = zip::ZipWriter::new(Cursor::new(Vec::new()));
        for i in 0..zin.len() {
            let mut f = zin.by_index(i).unwrap();
            let name = f.name().unwrap().to_string();
            let mut data = Vec::new();
            f.read_to_end(&mut data).unwrap();
            if name == "xl/charts/chart1.xml" {
                data = b"<not really xml".to_vec();
            } else if name == "xl/charts/chart2.xml" {
                data = String::from_utf8(data).unwrap().replace("lineChart", "fancyNewChart").into_bytes();
            }
            zout.start_file(name, zip::write::SimpleFileOptions::default()).unwrap();
            zout.write_all(&data).unwrap();
        }
        let broken = zout.finish().unwrap().into_inner();
        let wb = reload(&broken);
        assert_eq!(wb.worksheets[0].charts.len(), 1);
        assert_eq!(wb.worksheets[0].charts[0].kind, ChartKind::Pie);
    }

    #[test]
    fn resolves_targets() {
        assert_eq!(resolve("xl/worksheets/sheet1.xml", "../drawings/drawing1.xml"), "xl/drawings/drawing1.xml");
        assert_eq!(resolve("xl/drawings/drawing1.xml", "../charts/chart1.xml"), "xl/charts/chart1.xml");
        assert_eq!(resolve("xl/drawings/drawing1.xml", "/xl/charts/chart9.xml"), "xl/charts/chart9.xml");
    }
}
