//! Foglio fork: writing cell comments (notes), data validation and the sheet
//! tab colour.
//!
//! Comments are written the way Excel writes notes: a comments part
//! `xl/commentsN.xml` and a legacy VML drawing `xl/drawings/vmlDrawingN.vml`
//! (the yellow boxes, hidden until the cell is hovered), both related from the
//! sheet, which references the VML with `<legacyDrawing r:id="…"/>`. `N` is
//! the sheet number. The relationship ids are fixed names so that they do not
//! collide with the numbered hyperlink relationships.

use std::io::{Seek, Write};

use ironcalc_base::{
    data_validation::{comment_position, DataValidation, DataValidationKind},
    types::{Color, Workbook, Worksheet},
    Model,
};

use crate::error::XlsxError;

use super::{escape::escape_xml, xml_constants::XML_DECLARATION};

const COMMENTS_REL_ID: &str = "rIdFoglioComments1";
const VML_REL_ID: &str = "rIdFoglioVml1";

/// `<sheetPr><tabColor …/></sheetPr>` (first child of `<worksheet>`), or "".
pub(crate) fn sheet_pr_element(worksheet: &Worksheet) -> String {
    let color = match &worksheet.color {
        Color::Rgb(rgb) => format!(r#"<tabColor rgb="FF{}"/>"#, rgb.trim_start_matches('#').to_uppercase()),
        Color::Theme(index, tint) => {
            if *tint == 0.0 {
                format!(r#"<tabColor theme="{index}"/>"#)
            } else {
                format!(r#"<tabColor theme="{index}" tint="{tint}"/>"#)
            }
        }
        Color::None => return String::new(),
    };
    format!("<sheetPr>{color}</sheetPr>")
}

fn rule_xml(dv: &DataValidation) -> String {
    let mut attributes = vec![];
    if dv.kind != DataValidationKind::Any {
        attributes.push(format!(r#"type="{}""#, dv.kind.xlsx_name()));
    }
    if dv.error_style.xlsx_name() != "stop" {
        attributes.push(format!(r#"errorStyle="{}""#, dv.error_style.xlsx_name()));
    }
    if dv.kind.uses_operator() && dv.operator.xlsx_name() != "between" {
        attributes.push(format!(r#"operator="{}""#, dv.operator.xlsx_name()));
    }
    if dv.allow_blank {
        attributes.push(r#"allowBlank="1""#.to_string());
    }
    // showDropDown="1" hides the in-cell arrow
    if dv.kind == DataValidationKind::List && !dv.in_cell_dropdown {
        attributes.push(r#"showDropDown="1""#.to_string());
    }
    if dv.show_input_message {
        attributes.push(r#"showInputMessage="1""#.to_string());
    }
    if dv.show_error_message {
        attributes.push(r#"showErrorMessage="1""#.to_string());
    }
    // Excel limits: titles 32 characters, messages 255
    let mut text_attribute = |name: &str, value: &Option<String>, max: usize| {
        if let Some(v) = value {
            if !v.is_empty() {
                let v: String = v.chars().take(max).collect();
                attributes.push(format!(r#"{name}="{}""#, escape_xml(&v)));
            }
        }
    };
    text_attribute("errorTitle", &dv.error_title, 32);
    text_attribute("error", &dv.error, 255);
    text_attribute("promptTitle", &dv.prompt_title, 32);
    text_attribute("prompt", &dv.prompt, 255);
    attributes.push(format!(r#"sqref="{}""#, escape_xml(&dv.sqref)));
    let mut formulas = String::new();
    if let Some(f) = &dv.formula1 {
        formulas.push_str(&format!("<formula1>{}</formula1>", escape_xml(f)));
    }
    if dv.kind.uses_operator() && dv.operator.is_range() {
        if let Some(f) = &dv.formula2 {
            formulas.push_str(&format!("<formula2>{}</formula2>", escape_xml(f)));
        }
    }
    format!("<dataValidation {}>{formulas}</dataValidation>", attributes.join(" "))
}

/// `<dataValidations>` (after `<conditionalFormatting>`, before `<hyperlinks>`), or "".
pub(crate) fn data_validations_element(worksheet: &Worksheet) -> String {
    let rules: Vec<String> = worksheet
        .data_validations
        .iter()
        // Excel rejects a rule without its formulas
        .filter(|dv| !dv.sqref.trim().is_empty())
        .filter(|dv| dv.kind == DataValidationKind::Any || dv.formula1.is_some())
        .filter(|dv| !(dv.kind.uses_operator() && dv.operator.is_range()) || dv.formula2.is_some())
        .map(rule_xml)
        .collect();
    if rules.is_empty() {
        return String::new();
    }
    format!(
        r#"<dataValidations count="{}">{}</dataValidations>"#,
        rules.len(),
        rules.join("")
    )
}

/// `<legacyDrawing>` (after `<drawing>`, before `<extLst>`), or "".
pub(crate) fn legacy_drawing_element(worksheet: &Worksheet) -> String {
    if worksheet.comments.is_empty() {
        String::new()
    } else {
        format!(r#"<legacyDrawing r:id="{VML_REL_ID}"/>"#)
    }
}

/// Adds the comments and VML relationships to the sheet rels (creating them if needed).
pub(crate) fn merge_sheet_rels(
    rels: Option<String>,
    sheet_index: usize,
    worksheet: &Worksheet,
) -> Option<String> {
    if worksheet.comments.is_empty() {
        return rels;
    }
    let n = sheet_index + 1;
    let new = format!(
        r#"<Relationship Id="{COMMENTS_REL_ID}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments" Target="../comments{n}.xml"/><Relationship Id="{VML_REL_ID}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/vmlDrawing" Target="../drawings/vmlDrawing{n}.vml"/>"#
    );
    Some(match rels {
        Some(xml) if xml.contains("</Relationships>") => {
            xml.replacen("</Relationships>", &format!("{new}</Relationships>"), 1)
        }
        _ => format!(
            r#"{XML_DECLARATION}
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">{new}</Relationships>"#
        ),
    })
}

/// Content types of the comments parts and of VML.
pub(crate) fn content_types(workbook: &Workbook) -> Vec<String> {
    let mut out = vec![];
    for (index, worksheet) in workbook.worksheets.iter().enumerate() {
        if !worksheet.comments.is_empty() {
            out.push(format!(
                r#"<Override PartName="/xl/comments{}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.comments+xml"/>"#,
                index + 1
            ));
        }
    }
    if !out.is_empty() {
        out.insert(
            0,
            r#"<Default Extension="vml" ContentType="application/vnd.openxmlformats-officedocument.vmlDrawing"/>"#
                .to_string(),
        );
    }
    out
}

fn comments_xml(worksheet: &Worksheet) -> String {
    let mut authors: Vec<&str> = vec![];
    let mut list = String::new();
    for comment in &worksheet.comments {
        let author = comment.author_name.as_str();
        let author_id = match authors.iter().position(|a| *a == author) {
            Some(i) => i,
            None => {
                authors.push(author);
                authors.len() - 1
            }
        };
        // One run, formatted like Excel's notes (Tahoma 9)
        list.push_str(&format!(
            r#"<comment ref="{}" authorId="{author_id}"><text><r><rPr><sz val="9"/><color indexed="81"/><rFont val="Tahoma"/><family val="2"/></rPr><t xml:space="preserve">{}</t></r></text></comment>"#,
            escape_xml(&comment.cell_ref),
            escape_xml(&comment.text)
        ));
    }
    let authors: String = authors
        .iter()
        .map(|a| format!("<author>{}</author>", escape_xml(a)))
        .collect();
    format!(
        r#"{XML_DECLARATION}
<comments xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><authors>{authors}</authors><commentList>{list}</commentList></comments>"#
    )
}

fn vml_xml(worksheet: &Worksheet, sheet_index: usize) -> String {
    // Each drawing gets its own block of 1024 shape ids.
    let block = sheet_index + 1;
    let mut shapes = String::new();
    for (i, comment) in worksheet.comments.iter().enumerate() {
        let Some((row, column)) = comment_position(comment) else {
            continue;
        };
        // 0-based, like the anchor; the box sits to the right of the cell
        let (r, c) = (row - 1, column - 1);
        let top = (r - 1).max(0);
        let anchor = format!("{}, 15, {}, 10, {}, 15, {}, 4", c + 1, top, c + 3, top + 4);
        shapes.push_str(&format!(
            r##"<v:shape id="_x0000_s{id}" type="#_x0000_t202" style='position:absolute;margin-left:59.25pt;margin-top:1.5pt;width:108pt;height:59.25pt;z-index:{z};visibility:hidden' fillcolor="#ffffe1" o:insetmode="auto"><v:fill color2="#ffffe1"/><v:shadow on="t" color="black" obscured="t"/><v:path o:connecttype="none"/><v:textbox style='mso-direction-alt:auto'><div style='text-align:left'></div></v:textbox><x:ClientData ObjectType="Note"><x:MoveWithCells/><x:SizeWithCells/><x:Anchor>{anchor}</x:Anchor><x:AutoFill>False</x:AutoFill><x:Row>{r}</x:Row><x:Column>{c}</x:Column></x:ClientData></v:shape>"##,
            id = block * 1024 + i + 1,
            z = i + 1,
        ));
    }
    format!(
        r##"<xml xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel"><o:shapelayout v:ext="edit"><o:idmap v:ext="edit" data="{block}"/></o:shapelayout><v:shapetype id="_x0000_t202" coordsize="21600,21600" o:spt="202" path="m,l,21600r21600,l21600,xe"><v:stroke joinstyle="miter"/><v:path gradientshapeok="t" o:connecttype="rect"/></v:shapetype>{shapes}</xml>"##
    )
}

/// Writes the comments and VML parts of every sheet with comments.
pub(crate) fn write_parts<W: Write + Seek>(
    zip: &mut zip::ZipWriter<W>,
    model: &Model,
    options: zip::write::SimpleFileOptions,
) -> Result<(), XlsxError> {
    for (index, worksheet) in model.workbook.worksheets.iter().enumerate() {
        if worksheet.comments.is_empty() {
            continue;
        }
        let n = index + 1;
        zip.start_file(format!("xl/comments{n}.xml"), options)?;
        zip.write_all(comments_xml(worksheet).as_bytes())?;
        // No directory entry: the charts may have added "xl/drawings/" already.
        zip.start_file(format!("xl/drawings/vmlDrawing{n}.vml"), options)?;
        zip.write_all(vml_xml(worksheet, index).as_bytes())?;
    }
    Ok(())
}
