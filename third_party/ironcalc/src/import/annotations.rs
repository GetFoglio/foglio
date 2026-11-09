//! Foglio fork: reading cell comments (xl/commentsN.xml) and data validation
//! (`<dataValidations>` and the x14 `<x14:dataValidations>` extension).

use std::io::{BufReader, Read};

use ironcalc_base::{
    data_validation::{
        DataValidation, DataValidationErrorStyle, DataValidationKind, DataValidationOperator,
    },
    types::Comment,
};

use super::{shared_strings::decode_xlsx_escapes, xml::XmlNode};

/// Resolves the target of a relationship of the part `source` (e.g.
/// `xl/worksheets/sheet1.xml`): `../comments1.xml`, `/xl/comments/comment1.xml`
/// or `comments1.xml`.
pub(super) fn resolve_target(source: &str, target: &str) -> String {
    if let Some(absolute) = target.strip_prefix('/') {
        return absolute.to_string();
    }
    let mut parts: Vec<&str> = source.split('/').collect();
    parts.pop(); // the file name
    for segment in target.split('/') {
        match segment {
            ".." => {
                parts.pop();
            }
            "." | "" => {}
            s => parts.push(s),
        }
    }
    parts.join("/")
}

fn bool_attribute(node: &XmlNode, name: &str, default: bool) -> bool {
    match node.attribute(name) {
        Some(v) => v == "1" || v.eq_ignore_ascii_case("true"),
        None => default,
    }
}

/// The text of a run or rich text element, ignoring phonetic runs.
fn rich_text(node: &XmlNode) -> String {
    let mut out = String::new();
    for child in node.children() {
        if child.has_tag_name("t") {
            out.push_str(&decode_xlsx_escapes(child.text().unwrap_or("")));
        } else if child.has_tag_name("r") {
            out.push_str(&rich_text(child));
        }
    }
    out
}

/// Loads the comments part at `path`. A missing or unreadable part gives no
/// comments rather than failing the whole workbook.
pub(super) fn load_comments<R: Read + std::io::Seek>(
    archive: &mut zip::read::ZipArchive<R>,
    path: &str,
) -> Vec<Comment> {
    let Ok(file) = archive.by_name(path) else {
        return vec![];
    };
    let Ok(doc) = XmlNode::parse(BufReader::new(file)) else {
        return vec![];
    };
    let authors: Vec<String> = doc
        .children()
        .filter(|n| n.has_tag_name("authors"))
        .flat_map(|n| n.children().filter(|a| a.has_tag_name("author")))
        .map(|a| a.text().unwrap_or("").to_string())
        .collect();
    let mut comments = Vec::new();
    for list in doc.children().filter(|n| n.has_tag_name("commentList")) {
        for comment in list.children().filter(|n| n.has_tag_name("comment")) {
            let Some(cell_ref) = comment.attribute("ref") else {
                continue;
            };
            // A range ("A1:B2") is attached to its first cell
            let cell_ref = cell_ref.split(':').next().unwrap_or("").to_string();
            let author_name = comment
                .attribute("authorId")
                .and_then(|id| id.parse::<usize>().ok())
                .and_then(|id| authors.get(id))
                .cloned()
                .unwrap_or_default();
            let Some(text_node) = comment.children().find(|n| n.has_tag_name("text")) else {
                continue;
            };
            // Excel starts the text of a note with a bold run "Author:" and a
            // line break: that is the author, not the text.
            let runs: Vec<&XmlNode> = text_node
                .children()
                .filter(|n| n.has_tag_name("r"))
                .collect();
            let mut text = rich_text(text_node);
            let prefix = format!("{author_name}:");
            if !author_name.is_empty() && runs.first().map(|r| rich_text(r)) == Some(prefix.clone()) {
                if let Some(rest) = text.strip_prefix(&prefix) {
                    let rest = rest.strip_prefix("\r\n").or_else(|| rest.strip_prefix('\n')).unwrap_or(rest);
                    text = rest.to_string();
                }
            }
            comments.push(Comment {
                text: text.replace("\r\n", "\n"),
                author_name,
                author_id: None,
                cell_ref,
            });
        }
    }
    comments
}

fn read_rule(node: &XmlNode, sqref: Option<String>, formula1: Option<String>, formula2: Option<String>) -> Option<DataValidation> {
    let sqref = sqref?;
    if sqref.trim().is_empty() {
        return None;
    }
    let text = |name: &str| node.attribute(name).map(|s| s.to_string()).filter(|s| !s.is_empty());
    Some(DataValidation {
        sqref: sqref.split_whitespace().collect::<Vec<_>>().join(" "),
        kind: DataValidationKind::from_xlsx_name(node.attribute("type").unwrap_or("none")),
        operator: DataValidationOperator::from_xlsx_name(node.attribute("operator").unwrap_or("between")),
        formula1,
        formula2,
        allow_blank: bool_attribute(node, "allowBlank", false),
        // showDropDown="1" *hides* the in-cell arrow
        in_cell_dropdown: !bool_attribute(node, "showDropDown", false),
        show_input_message: bool_attribute(node, "showInputMessage", false),
        show_error_message: bool_attribute(node, "showErrorMessage", false),
        error_style: DataValidationErrorStyle::from_xlsx_name(node.attribute("errorStyle").unwrap_or("stop")),
        error_title: text("errorTitle"),
        error: text("error"),
        prompt_title: text("promptTitle"),
        prompt: text("prompt"),
    })
}

fn formula_text(node: &XmlNode, name: &str) -> Option<String> {
    let f = node.children().find(|n| n.has_tag_name(name))?;
    // x14: <x14:formula1><xm:f>Sheet2!$A$1:$A$3</xm:f></x14:formula1>
    let text = match f.children().find(|n| n.has_tag_name("f")) {
        Some(inner) => inner.text().unwrap_or(""),
        None => f.text().unwrap_or(""),
    };
    let text = text.trim().trim_start_matches('=');
    if text.is_empty() {
        None
    } else {
        Some(text.to_string())
    }
}

/// Reads `<dataValidations>` and the x14 extension of a worksheet.
pub(super) fn load_data_validations(ws: &XmlNode) -> Vec<DataValidation> {
    let mut rules = Vec::new();
    for list in ws.children().filter(|n| n.has_tag_name("dataValidations")) {
        for node in list.children().filter(|n| n.has_tag_name("dataValidation")) {
            let sqref = node.attribute("sqref").map(|s| s.to_string());
            if let Some(rule) = read_rule(
                node,
                sqref,
                formula_text(node, "formula1"),
                formula_text(node, "formula2"),
            ) {
                rules.push(rule);
            }
        }
    }
    // <extLst><ext uri="{CCE6A557-97BC-4b89-ADB6-D9C93CAAB3DF}"><x14:dataValidations>
    //   <x14:dataValidation type="list"><x14:formula1><xm:f>…</xm:f></x14:formula1>
    //   <xm:sqref>A1:A5</xm:sqref></x14:dataValidation>
    for ext_list in ws.children().filter(|n| n.has_tag_name("extLst")) {
        for list in ext_list
            .descendants()
            .filter(|n| n.has_tag_name("dataValidations"))
        {
            for node in list.children().filter(|n| n.has_tag_name("dataValidation")) {
                let sqref = node
                    .children()
                    .find(|n| n.has_tag_name("sqref"))
                    .and_then(|n| n.text())
                    .map(|s| s.to_string());
                if let Some(rule) = read_rule(
                    node,
                    sqref,
                    formula_text(node, "formula1"),
                    formula_text(node, "formula2"),
                ) {
                    rules.push(rule);
                }
            }
        }
    }
    rules
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolve_targets() {
        let s = "xl/worksheets/sheet1.xml";
        assert_eq!(resolve_target(s, "../comments1.xml"), "xl/comments1.xml");
        assert_eq!(
            resolve_target(s, "/xl/comments/comment1.xml"),
            "xl/comments/comment1.xml"
        );
        assert_eq!(resolve_target(s, "c.xml"), "xl/worksheets/c.xml");
    }

    #[test]
    fn data_validations() {
        let xml = r#"<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:x14="http://schemas.microsoft.com/office/spreadsheetml/2009/9/main" xmlns:xm="http://schemas.microsoft.com/office/excel/2006/main">
<dataValidations count="2">
<dataValidation type="list" allowBlank="1" showInputMessage="1" showErrorMessage="1" errorStyle="warning" promptTitle="P" prompt="Pick" sqref="A1:A5 C1"><formula1>"a,b,c"</formula1></dataValidation>
<dataValidation type="whole" operator="greaterThan" showDropDown="1" sqref="B1"><formula1>10</formula1></dataValidation>
</dataValidations>
<extLst><ext uri="{CCE6A557-97BC-4b89-ADB6-D9C93CAAB3DF}"><x14:dataValidations count="1"><x14:dataValidation type="list" allowBlank="1"><x14:formula1><xm:f>Sheet2!$A$1:$A$3</xm:f></x14:formula1><xm:sqref>D1:D4</xm:sqref></x14:dataValidation></x14:dataValidations></ext></extLst>
</worksheet>"#;
        let ws = XmlNode::parse_str(xml).unwrap();
        let rules = load_data_validations(&ws);
        assert_eq!(rules.len(), 3);
        assert_eq!(rules[0].kind, DataValidationKind::List);
        assert_eq!(rules[0].sqref, "A1:A5 C1");
        assert_eq!(rules[0].formula1.as_deref(), Some("\"a,b,c\""));
        assert_eq!(rules[0].error_style, DataValidationErrorStyle::Warning);
        assert!(rules[0].in_cell_dropdown);
        assert_eq!(rules[0].prompt.as_deref(), Some("Pick"));
        assert_eq!(rules[1].operator, DataValidationOperator::GreaterThan);
        assert!(!rules[1].in_cell_dropdown);
        assert!(!rules[1].allow_blank);
        assert_eq!(rules[2].sqref, "D1:D4");
        assert_eq!(rules[2].formula1.as_deref(), Some("Sheet2!$A$1:$A$3"));
    }
}
