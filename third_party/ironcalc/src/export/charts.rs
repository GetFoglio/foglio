//! Foglio fork: writes the charts of the workbook.
//!
//! For every sheet with charts or pictures (Foglio fork: pictures, see pictures.rs):
//! * `xl/drawings/drawing{S}.xml` (S = sheet number) with one
//!   `xdr:twoCellAnchor` per chart, and its rels pointing to the charts,
//! * `xl/charts/chart{N}.xml` (N numbered across the workbook),
//! * a `drawing` relationship (id [`DRAWING_REL_ID`]) in the sheet rels and
//!   `<drawing r:id="..."/>` in the worksheet,
//! * content-type overrides for all of them.
//!
//! The chart parts follow the minimal structure Excel writes (ECMA-376
//! DrawingML charts, element order as in the schema) with formula references
//! and value caches, so viewers that do not recalculate show the data too.

use std::io::{Seek, Write};

use ironcalc_base::{
    cell::CellValue,
    charts::{Chart, ChartKind, ChartRef, ChartSeries, LegendPosition},
    pictures::{drawing_order, DrawingObject},
    types::Worksheet,
    Model,
};

use super::escape::escape_xml;
use super::pictures;
use super::xml_constants::XML_DECLARATION;
use crate::error::XlsxError;

/// Relationship id of the drawing in the sheet rels. Fixed (there is at most
/// one drawing per sheet) and distinct from the numbered ids other parts use.
pub(crate) const DRAWING_REL_ID: &str = "rIdFoglioDrawing1";

const NS_C: &str = "http://schemas.openxmlformats.org/drawingml/2006/chart";
const NS_A: &str = "http://schemas.openxmlformats.org/drawingml/2006/main";
const NS_R: &str = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
const NS_XDR: &str = "http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing";

/// (sheet index, index in the sheet, workbook-wide chart number)
fn chart_numbers(model: &Model) -> Vec<(usize, usize, usize)> {
    let mut out = Vec::new();
    let mut n = 0;
    for (s, ws) in model.workbook.worksheets.iter().enumerate() {
        for i in 0..ws.charts.len() {
            n += 1;
            out.push((s, i, n));
        }
    }
    out
}

/// Foglio fork (pictures): a sheet has a drawing part if it has charts or pictures.
fn has_drawing(ws: &Worksheet) -> bool {
    !ws.charts.is_empty() || ws.pictures.iter().any(|p| pictures::is_exportable(ws, p))
}

/// `[Content_Types].xml` entries for drawings, charts and images.
pub(crate) fn content_types(workbook: &ironcalc_base::types::Workbook) -> Vec<String> {
    let mut out = pictures::Media::of(workbook).content_types();
    let mut n = 0;
    for (s, ws) in workbook.worksheets.iter().enumerate() {
        if !has_drawing(ws) {
            continue;
        }
        out.push(format!(
            r#"<Override PartName="/xl/drawings/drawing{}.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>"#,
            s + 1
        ));
        for _ in &ws.charts {
            n += 1;
            out.push(format!(
                r#"<Override PartName="/xl/charts/chart{n}.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>"#
            ));
        }
    }
    out
}

/// `<drawing r:id="..."/>` for the worksheet part, or "" without charts and pictures.
pub(crate) fn drawing_element(worksheet: &Worksheet) -> String {
    if !has_drawing(worksheet) {
        String::new()
    } else {
        format!(r#"<drawing r:id="{DRAWING_REL_ID}"/>"#)
    }
}

/// Adds the drawing relationship to the sheet rels (creating them if needed).
pub(crate) fn merge_sheet_rels(rels: Option<String>, sheet_index: usize, worksheet: &Worksheet) -> Option<String> {
    if !has_drawing(worksheet) {
        return rels;
    }
    let rel = format!(
        r#"<Relationship Id="{DRAWING_REL_ID}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing{}.xml"/>"#,
        sheet_index + 1
    );
    Some(match rels {
        Some(xml) if xml.contains("</Relationships>") => xml.replacen("</Relationships>", &format!("{rel}</Relationships>"), 1),
        _ => format!(
            r#"{XML_DECLARATION}
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">{rel}</Relationships>"#
        ),
    })
}

/// Writes the drawing, chart and media parts.
pub(crate) fn write_parts<W: Write + Seek>(
    zip: &mut zip::ZipWriter<W>,
    model: &Model,
    options: zip::write::SimpleFileOptions,
) -> Result<(), XlsxError> {
    let workbook = &model.workbook;
    if !workbook.worksheets.iter().any(has_drawing) {
        return Ok(());
    }
    let numbers = chart_numbers(model);
    let media = pictures::Media::of(workbook);
    zip.add_directory("xl/drawings", options)?;
    zip.add_directory("xl/drawings/_rels", options)?;
    if !numbers.is_empty() {
        zip.add_directory("xl/charts", options)?;
    }
    for (s, ws) in workbook.worksheets.iter().enumerate() {
        if !has_drawing(ws) {
            continue;
        }
        let mine: Vec<(usize, usize)> = numbers.iter().filter(|(si, _, _)| *si == s).map(|(_, i, n)| (*i, *n)).collect();
        zip.start_file(format!("xl/drawings/drawing{}.xml", s + 1), options)?;
        zip.write_all(drawing_xml(ws, &mine, &media).as_bytes())?;
        zip.start_file(format!("xl/drawings/_rels/drawing{}.xml.rels", s + 1), options)?;
        zip.write_all(drawing_rels_xml(ws, &mine, &media).as_bytes())?;
        for (i, n) in mine {
            zip.start_file(format!("xl/charts/chart{n}.xml"), options)?;
            zip.write_all(chart_xml(model, &ws.charts[i]).as_bytes())?;
        }
    }
    // Images: already compressed, stored as they are.
    if !media.list.is_empty() {
        zip.add_directory("xl/media", options)?;
        let stored = options.compression_method(zip::CompressionMethod::Stored);
        for (key, n, ext) in &media.list {
            let Some(bytes) = workbook.worksheets.iter().find_map(|w| w.images.get(key)) else { continue };
            zip.start_file(format!("xl/media/image{n}.{ext}"), stored)?;
            zip.write_all(bytes)?;
        }
    }
    Ok(())
}

fn drawing_rels_xml(ws: &Worksheet, charts: &[(usize, usize)], media: &pictures::Media) -> String {
    let mut rels: String = charts
        .iter()
        .map(|(i, n)| {
            format!(
                r#"<Relationship Id="rId{}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="../charts/chart{n}.xml"/>"#,
                i + 1
            )
        })
        .collect();
    // One relationship per image (pictures showing the same image share it).
    let mut images: Vec<(usize, &str)> = ws.pictures.iter().filter_map(|p| media.get(&p.image)).collect();
    images.sort();
    images.dedup();
    for (n, ext) in images {
        rels.push_str(&pictures::image_rel_xml(n, ext));
    }
    format!(
        r#"{XML_DECLARATION}
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">{rels}</Relationships>"#
    )
}

fn chart_anchor_xml(chart: &Chart, id: usize, rel: usize) -> String {
    let a = &chart.anchor;
    let point = |tag: &str, p: &ironcalc_base::charts::AnchorPoint| {
        format!(
            "<xdr:{tag}><xdr:col>{}</xdr:col><xdr:colOff>{}</xdr:colOff><xdr:row>{}</xdr:row><xdr:rowOff>{}</xdr:rowOff></xdr:{tag}>",
            (p.column - 1).max(0),
            p.column_offset.max(0),
            (p.row - 1).max(0),
            p.row_offset.max(0)
        )
    };
    let name = if chart.name.is_empty() { format!("Chart {id}") } else { chart.name.clone() };
    format!(
        r#"<xdr:twoCellAnchor>{}{}<xdr:graphicFrame macro=""><xdr:nvGraphicFramePr><xdr:cNvPr id="{id}" name="{}"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr><xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm><a:graphic><a:graphicData uri="{NS_C}"><c:chart xmlns:c="{NS_C}" xmlns:r="{NS_R}" r:id="rId{rel}"/></a:graphicData></a:graphic></xdr:graphicFrame><xdr:clientData/></xdr:twoCellAnchor>"#,
        point("from", &a.from),
        point("to", &a.to),
        escape_xml(&name),
    )
}

/// The drawing part: charts and pictures from back to front (Foglio fork:
/// pictures, see pictures.rs and `ironcalc_base::pictures::drawing_order`).
fn drawing_xml(ws: &Worksheet, charts: &[(usize, usize)], media: &pictures::Media) -> String {
    let mut anchors = String::new();
    let mut id = 2;
    let mut groups_done = std::collections::HashSet::new();
    let order = drawing_order(ws);
    for object in &order {
        match *object {
            DrawingObject::Chart(i) => {
                if charts.iter().any(|(ci, _)| *ci == i) {
                    anchors.push_str(&chart_anchor_xml(&ws.charts[i], id, i + 1));
                }
                id += 1;
            }
            DrawingObject::Picture(i) => {
                let p = &ws.pictures[i];
                // Foglio fork: grouped pictures go out as one group, where its first member is in the stack.
                if p.group != 0 {
                    if !groups_done.insert(p.group) {
                        continue;
                    }
                    let members: Vec<&ironcalc_base::pictures::Picture> = order
                        .iter()
                        .filter_map(|o| match *o {
                            DrawingObject::Picture(j) if ws.pictures[j].group == p.group => Some(&ws.pictures[j]),
                            _ => None,
                        })
                        .collect();
                    if members.len() > 1 {
                        if let Some(xml) = pictures::group_anchor_xml(ws, &members, &mut id, media) {
                            anchors.push_str(&xml);
                        }
                        continue;
                    }
                }
                if let Some(xml) = pictures::anchor_xml(ws, p, id, media) {
                    anchors.push_str(&xml);
                }
                id += 1;
            }
        }
    }
    format!(r#"{XML_DECLARATION}
<xdr:wsDr xmlns:xdr="{NS_XDR}" xmlns:a="{NS_A}">{anchors}</xdr:wsDr>"#)
}

// ---------------------------------------------------------------------------
// Chart part
// ---------------------------------------------------------------------------

/// Cached values of a reference: (index, value) of the non-empty cells and the count.
enum Cache {
    Numbers(Vec<(usize, f64)>, usize, String),
    Texts(Vec<(usize, String)>, usize),
}

fn cache_of(model: &Model, formula: &str, numeric: bool) -> Option<Cache> {
    let r = ChartRef::parse(formula)?;
    let sheet = model.workbook.worksheets.iter().position(|w| w.name == r.sheet)? as u32;
    let ws = &model.workbook.worksheets[sheet as usize];
    let dim = ws.dimension();
    let r = ChartRef {
        row2: r.row2.min(dim.max_row.max(r.row1)),
        column2: r.column2.min(dim.max_column.max(r.column1)),
        ..r
    };
    if r.len() > 100_000 {
        return None;
    }
    let cells: Vec<(i32, i32)> = r.cells().collect();
    let count = cells.len();
    let values: Vec<CellValue> = cells
        .iter()
        .map(|(row, col)| model.get_cell_value_by_index(sheet, *row, *col).unwrap_or(CellValue::None))
        .collect();
    let all_numbers = values.iter().all(|v| matches!(v, CellValue::Number(_) | CellValue::None))
        && values.iter().any(|v| matches!(v, CellValue::Number(_)));
    if numeric || all_numbers {
        let format = cells
            .first()
            .and_then(|(row, col)| model.get_style_for_cell(sheet, *row, *col).ok())
            .map(|s| s.num_fmt)
            .unwrap_or_else(|| "General".to_string());
        let format = if format.eq_ignore_ascii_case("general") { "General".to_string() } else { format };
        let pts = values
            .iter()
            .enumerate()
            .filter_map(|(i, v)| match v {
                CellValue::Number(n) => Some((i, *n)),
                _ => None,
            })
            .collect();
        Some(Cache::Numbers(pts, count, format))
    } else {
        let pts = cells
            .iter()
            .enumerate()
            .filter_map(|(i, (row, col))| {
                let t = model.get_formatted_cell_value(sheet, *row, *col).unwrap_or_default();
                (!t.is_empty()).then_some((i, t))
            })
            .collect();
        Some(Cache::Texts(pts, count))
    }
}

fn number_text(n: f64) -> String {
    if n.is_finite() {
        format!("{n}")
    } else {
        "0".to_string()
    }
}

/// `<c:numRef>` / `<c:strRef>` with formula and cache.
fn data_ref(model: &Model, formula: &str, numeric: bool) -> String {
    let f = escape_xml(formula.trim_start_matches('='));
    match cache_of(model, formula, numeric) {
        Some(Cache::Numbers(pts, count, format)) => {
            let pts: String = pts
                .iter()
                .map(|(i, n)| format!(r#"<c:pt idx="{i}"><c:v>{}</c:v></c:pt>"#, number_text(*n)))
                .collect();
            format!(
                r#"<c:numRef><c:f>{f}</c:f><c:numCache><c:formatCode>{}</c:formatCode><c:ptCount val="{count}"/>{pts}</c:numCache></c:numRef>"#,
                escape_xml(&format)
            )
        }
        Some(Cache::Texts(pts, count)) => {
            let pts: String = pts
                .iter()
                .map(|(i, t)| format!(r#"<c:pt idx="{i}"><c:v>{}</c:v></c:pt>"#, escape_xml(t)))
                .collect();
            format!(r#"<c:strRef><c:f>{f}</c:f><c:strCache><c:ptCount val="{count}"/>{pts}</c:strCache></c:strRef>"#)
        }
        None if numeric => format!("<c:numRef><c:f>{f}</c:f></c:numRef>"),
        None => format!("<c:strRef><c:f>{f}</c:f></c:strRef>"),
    }
}

fn series_tx(model: &Model, s: &ChartSeries, index: usize) -> String {
    if let Some(f) = &s.name_ref {
        if ChartRef::parse(f).is_some() {
            let name = model.chart_series_name(s, index);
            return format!(
                r#"<c:tx><c:strRef><c:f>{}</c:f><c:strCache><c:ptCount val="1"/><c:pt idx="0"><c:v>{}</c:v></c:pt></c:strCache></c:strRef></c:tx>"#,
                escape_xml(f.trim_start_matches('=')),
                escape_xml(&name)
            );
        }
    }
    match &s.name {
        Some(n) if !n.is_empty() => format!("<c:tx><c:v>{}</c:v></c:tx>", escape_xml(n)),
        _ => String::new(),
    }
}

fn rich(text: &str, size: u32, bold: bool) -> String {
    let b = if bold { "1" } else { "0" };
    let paragraphs: String = text
        .split('\n')
        .map(|line| {
            format!(
                r#"<a:p><a:pPr><a:defRPr sz="{size}" b="{b}"/></a:pPr><a:r><a:rPr lang="en-US" sz="{size}" b="{b}"/><a:t>{}</a:t></a:r></a:p>"#,
                escape_xml(line)
            )
        })
        .collect();
    format!(r#"<c:tx><c:rich><a:bodyPr rot="0" spcFirstLastPara="1" vertOverflow="ellipsis" wrap="square" anchor="ctr" anchorCtr="1"/><a:lstStyle/>{paragraphs}</c:rich></c:tx>"#)
}

fn title(text: &str, size: u32, bold: bool) -> String {
    format!(r#"<c:title>{}<c:overlay val="0"/></c:title>"#, rich(text, size, bold))
}

fn axis_title(text: &str, vertical: bool) -> String {
    let r = rich(text, 1000, true);
    let r = if vertical { r.replacen(r#"<a:bodyPr rot="0""#, r#"<a:bodyPr rot="-5400000""#, 1) } else { r };
    format!(r#"<c:title>{r}<c:overlay val="0"/></c:title>"#)
}

const GRAY_LINE: &str = r#"<a:ln w="9525" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:srgbClr val="D9D9D9"/></a:solidFill><a:round/></a:ln>"#;
const AXIS_TEXT: &str = r#"<c:txPr><a:bodyPr rot="-60000000" vert="horz"/><a:lstStyle/><a:p><a:pPr><a:defRPr sz="900"><a:solidFill><a:srgbClr val="595959"/></a:solidFill></a:defRPr></a:pPr><a:endParaRPr lang="en-US"/></a:p></c:txPr>"#;

fn series_sppr(kind: ChartKind, color: Option<&str>) -> String {
    // Pie slices get the theme colours one by one (varyColors).
    let color = if matches!(kind, ChartKind::Pie | ChartKind::Doughnut) { None } else { color };
    let Some(c) = color else {
        // Without spPr Excel uses the theme accents; scatter needs "no line".
        return if kind == ChartKind::Scatter {
            r#"<c:spPr><a:ln w="25400" cap="rnd"><a:noFill/><a:round/></a:ln></c:spPr>"#.to_string()
        } else {
            String::new()
        };
    };
    match kind {
        ChartKind::Line | ChartKind::LineMarkers => format!(
            r#"<c:spPr><a:ln w="28575" cap="rnd"><a:solidFill><a:srgbClr val="{c}"/></a:solidFill><a:round/></a:ln></c:spPr>"#
        ),
        ChartKind::Scatter => r#"<c:spPr><a:ln w="25400" cap="rnd"><a:noFill/><a:round/></a:ln></c:spPr>"#.to_string(),
        _ => format!(r#"<c:spPr><a:solidFill><a:srgbClr val="{c}"/></a:solidFill></c:spPr>"#),
    }
}

fn marker(kind: ChartKind, color: Option<&str>) -> String {
    match kind {
        ChartKind::Line => r#"<c:marker><c:symbol val="none"/></c:marker>"#.to_string(),
        ChartKind::LineMarkers | ChartKind::Scatter => {
            let fill = color
                .map(|c| {
                    format!(
                        r#"<c:spPr><a:solidFill><a:srgbClr val="{c}"/></a:solidFill><a:ln w="9525"><a:solidFill><a:srgbClr val="{c}"/></a:solidFill></a:ln></c:spPr>"#
                    )
                })
                .unwrap_or_default();
            format!(r#"<c:marker><c:symbol val="circle"/><c:size val="5"/>{fill}</c:marker>"#)
        }
        _ => String::new(),
    }
}

fn series_xml(model: &Model, chart: &Chart, i: usize, s: &ChartSeries) -> String {
    let kind = chart.kind;
    let color = s.color.as_deref().filter(|c| c.len() == 6 && c.chars().all(|c| c.is_ascii_hexdigit()));
    let mut x = format!(r#"<c:ser><c:idx val="{i}"/><c:order val="{i}"/>"#);
    x.push_str(&series_tx(model, s, i));
    x.push_str(&series_sppr(kind, color));
    match kind {
        ChartKind::Column | ChartKind::ColumnStacked | ChartKind::Bar | ChartKind::BarStacked => {
            x.push_str(r#"<c:invertIfNegative val="0"/>"#)
        }
        ChartKind::Line | ChartKind::LineMarkers | ChartKind::Scatter => x.push_str(&marker(kind, color)),
        _ => {}
    }
    if kind == ChartKind::Scatter {
        if let Some(f) = &s.categories_ref {
            x.push_str(&format!("<c:xVal>{}</c:xVal>", data_ref(model, f, false)));
        }
        x.push_str(&format!("<c:yVal>{}</c:yVal>", data_ref(model, &s.values_ref, true)));
        x.push_str(r#"<c:smooth val="0"/>"#);
    } else {
        if let Some(f) = &s.categories_ref {
            x.push_str(&format!("<c:cat>{}</c:cat>", data_ref(model, f, false)));
        }
        x.push_str(&format!("<c:val>{}</c:val>", data_ref(model, &s.values_ref, true)));
        if matches!(kind, ChartKind::Line | ChartKind::LineMarkers) {
            x.push_str(r#"<c:smooth val="0"/>"#);
        }
    }
    x.push_str("</c:ser>");
    x
}

const AX_CAT: u32 = 500_000_001;
const AX_VAL: u32 = 500_000_002;

fn axes_xml(chart: &Chart) -> String {
    let kind = chart.kind;
    let horizontal = matches!(kind, ChartKind::Bar | ChartKind::BarStacked);
    let (cat_pos, val_pos) = if horizontal { ("l", "b") } else { ("b", "l") };
    let cat_title = chart
        .category_axis_title
        .as_deref()
        .filter(|t| !t.is_empty())
        .map(|t| axis_title(t, horizontal))
        .unwrap_or_default();
    let val_title = chart
        .value_axis_title
        .as_deref()
        .filter(|t| !t.is_empty())
        .map(|t| axis_title(t, !horizontal))
        .unwrap_or_default();
    let cross_between = if matches!(kind, ChartKind::Area | ChartKind::AreaStacked | ChartKind::Scatter) {
        "midCat"
    } else {
        "between"
    };
    let gridlines = format!("<c:majorGridlines><c:spPr>{GRAY_LINE}</c:spPr></c:majorGridlines>");
    let val_ax = |id: u32, cross: u32, pos: &str, title: &str, grid: &str| {
        format!(
            r#"<c:valAx><c:axId val="{id}"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="{pos}"/>{grid}{title}<c:numFmt formatCode="General" sourceLinked="1"/><c:majorTickMark val="none"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/><c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr>{AXIS_TEXT}<c:crossAx val="{cross}"/><c:crosses val="autoZero"/><c:crossBetween val="{cross_between}"/></c:valAx>"#
        )
    };
    if kind == ChartKind::Scatter {
        // Two value axes: X at the bottom, Y on the left (X listed first).
        let x_axis = val_ax(AX_CAT, AX_VAL, "b", &cat_title, "").replacen(
            r#"<c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr>"#,
            &format!("<c:spPr><a:noFill/>{GRAY_LINE}</c:spPr>"),
            1,
        );
        return format!("{x_axis}{}", val_ax(AX_VAL, AX_CAT, "l", &val_title, &gridlines));
    }
    let cat_ax = format!(
        r#"<c:catAx><c:axId val="{AX_CAT}"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="{cat_pos}"/>{cat_title}<c:numFmt formatCode="General" sourceLinked="1"/><c:majorTickMark val="none"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/><c:spPr><a:noFill/>{GRAY_LINE}</c:spPr>{AXIS_TEXT}<c:crossAx val="{AX_VAL}"/><c:crosses val="autoZero"/><c:auto val="1"/><c:lblAlgn val="ctr"/><c:lblOffset val="100"/><c:noMultiLvlLbl val="0"/></c:catAx>"#
    );
    let val = val_ax(AX_VAL, AX_CAT, val_pos, &val_title, &gridlines);
    format!("{cat_ax}{val}")
}

/// The DrawingML chart part for `chart`.
pub(crate) fn chart_xml(model: &Model, chart: &Chart) -> String {
    let kind = chart.kind;
    let series: String = chart.series.iter().enumerate().map(|(i, s)| series_xml(model, chart, i, s)).collect();
    let ax_ids = format!(r#"<c:axId val="{AX_CAT}"/><c:axId val="{AX_VAL}"/>"#);
    let group = match kind {
        ChartKind::Column | ChartKind::ColumnStacked | ChartKind::Bar | ChartKind::BarStacked => {
            let dir = if matches!(kind, ChartKind::Bar | ChartKind::BarStacked) { "bar" } else { "col" };
            let stacked = matches!(kind, ChartKind::ColumnStacked | ChartKind::BarStacked);
            let (grouping, overlap, gap) = if stacked { ("stacked", 100, 150) } else { ("clustered", -27, 219) };
            format!(
                r#"<c:barChart><c:barDir val="{dir}"/><c:grouping val="{grouping}"/><c:varyColors val="0"/>{series}<c:gapWidth val="{gap}"/><c:overlap val="{overlap}"/>{ax_ids}</c:barChart>"#
            )
        }
        ChartKind::Line | ChartKind::LineMarkers => format!(
            r#"<c:lineChart><c:grouping val="standard"/><c:varyColors val="0"/>{series}<c:marker val="1"/>{ax_ids}</c:lineChart>"#
        ),
        ChartKind::Area | ChartKind::AreaStacked => {
            let grouping = if kind == ChartKind::AreaStacked { "stacked" } else { "standard" };
            format!(r#"<c:areaChart><c:grouping val="{grouping}"/><c:varyColors val="0"/>{series}{ax_ids}</c:areaChart>"#)
        }
        ChartKind::Pie => format!(r#"<c:pieChart><c:varyColors val="1"/>{series}<c:firstSliceAng val="0"/></c:pieChart>"#),
        ChartKind::Doughnut => format!(
            r#"<c:doughnutChart><c:varyColors val="1"/>{series}<c:firstSliceAng val="0"/><c:holeSize val="50"/></c:doughnutChart>"#
        ),
        ChartKind::Scatter => format!(
            r#"<c:scatterChart><c:scatterStyle val="lineMarker"/><c:varyColors val="0"/>{series}{ax_ids}</c:scatterChart>"#
        ),
    };
    let axes = if kind.has_axes() { axes_xml(chart) } else { String::new() };
    let (title_xml, auto_deleted) = match chart.title.as_deref() {
        Some(t) if !t.is_empty() => (title(t, 1400, false), "0"),
        _ => (String::new(), "1"),
    };
    let legend = match chart.legend {
        LegendPosition::None => String::new(),
        p => {
            let pos = match p {
                LegendPosition::Right => "r",
                LegendPosition::Top => "t",
                LegendPosition::Left => "l",
                _ => "b",
            };
            format!(r#"<c:legend><c:legendPos val="{pos}"/><c:overlay val="0"/>{AXIS_TEXT}</c:legend>"#)
        }
    };
    format!(
        r#"{XML_DECLARATION}
<c:chartSpace xmlns:c="{NS_C}" xmlns:a="{NS_A}" xmlns:r="{NS_R}"><c:date1904 val="0"/><c:lang val="en-US"/><c:roundedCorners val="0"/><c:chart>{title_xml}<c:autoTitleDeleted val="{auto_deleted}"/><c:plotArea><c:layout/>{group}{axes}<c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr></c:plotArea>{legend}<c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart><c:spPr><a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill><a:ln w="9525" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:srgbClr val="D9D9D9"/></a:solidFill><a:round/></a:ln></c:spPr><c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr/></a:pPr><a:endParaRPr lang="en-US"/></a:p></c:txPr></c:chartSpace>"#
    )
}
