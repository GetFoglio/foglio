//! Macro-enabled workbooks (.xlsm / .xltm): the VBA project is never run or edited, but it is
//! kept. Saving writes the workbook with IronCalc's xlsx exporter, then copies the VBA parts of
//! the file the workbook was opened from into the new package and restores the code names
//! (`workbookPr/@codeName`, `sheetPr/@codeName`) that tie the VBA document modules
//! (ThisWorkbook, Sheet1, ...) to the workbook and its sheets. See include/foglio_io.h.

use std::collections::HashMap;
use std::ffi::c_char;
use std::fs::File;
use std::io::{Read, Write};
use std::panic::{catch_unwind, AssertUnwindSafe};

use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, ZipArchive, ZipWriter};

use crate::{book, cstr, write_err, FoglioBook};

const VBA_REL_TYPE: &str = "http://schemas.microsoft.com/office/2006/relationships/vbaProject";
const VBA_CONTENT_TYPE: &str = "application/vnd.ms-office.vbaProject";
const XLSX_MAIN: &str = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml";
const XLSM_MAIN: &str = "application/vnd.ms-excel.sheet.macroEnabled.main+xml";

/// What a saved .xlsm needs from the original file.
#[derive(Debug, Default)]
pub struct MacroParts {
    /// `xl/vbaProject.bin`, its signatures and their relationships, verbatim.
    files: Vec<(String, Vec<u8>)>,
    /// `<Override>` elements of the source `[Content_Types].xml` for those parts.
    overrides: Vec<String>,
    workbook_code_name: Option<String>,
    /// `fileVersion/@codeName`: the GUID Excel gives the VBA project.
    project_guid: Option<String>,
    /// Sheet name -> VBA code name.
    sheet_code_names: HashMap<String, String>,
}

fn read_entry(zip: &mut ZipArchive<File>, name: &str) -> Option<Vec<u8>> {
    let mut f = zip.by_name(name).ok()?;
    let mut buf = Vec::new();
    f.read_to_end(&mut buf).ok()?;
    Some(buf)
}

fn read_text(zip: &mut ZipArchive<File>, name: &str) -> Option<String> {
    read_entry(zip, name).and_then(|b| String::from_utf8(b).ok())
}

/// Value of attribute `attr` in the first `<tag ...>` element of `xml`.
fn attr_of(xml: &str, tag: &str, attr: &str) -> Option<String> {
    let start = find_tag(xml, tag)?;
    let end = start + xml[start..].find('>')?;
    attr_in(&xml[start..end], attr)
}

fn attr_in(element: &str, attr: &str) -> Option<String> {
    let needle = format!(" {attr}=\"");
    let i = element.find(&needle)? + needle.len();
    let j = element[i..].find('"')?;
    Some(element[i..i + j].to_string())
}

/// Byte offset of the first `<tag` followed by a space, `>` or `/`.
fn find_tag(xml: &str, tag: &str) -> Option<usize> {
    let open = format!("<{tag}");
    let mut from = 0;
    while let Some(i) = xml[from..].find(&open) {
        let at = from + i;
        match xml[at + open.len()..].chars().next() {
            Some(' ') | Some('>') | Some('/') | Some('\n') | Some('\r') | Some('\t') => return Some(at),
            _ => from = at + open.len(),
        }
    }
    None
}

/// All `<tag .../>` or `<tag ...>` start elements of `xml`, as strings.
fn elements<'a>(xml: &'a str, tag: &str) -> Vec<&'a str> {
    let mut out = Vec::new();
    let mut from = 0;
    while let Some(i) = find_tag(&xml[from..], tag) {
        let at = from + i;
        let Some(len) = xml[at..].find('>') else { break };
        out.push(&xml[at..at + len + 1]);
        from = at + len + 1;
    }
    out
}

/// Sheet name -> part path inside the package (e.g. "xl/worksheets/sheet1.xml").
fn sheet_parts(workbook: &str, rels: &str) -> Vec<(String, String)> {
    let targets: HashMap<String, String> = elements(rels, "Relationship")
        .into_iter()
        .filter_map(|r| Some((attr_in(r, "Id")?, attr_in(r, "Target")?)))
        .collect();
    elements(workbook, "sheet")
        .into_iter()
        .filter_map(|s| {
            let name = unescape(&attr_in(s, "name")?);
            let target = targets.get(&attr_in(s, "r:id")?)?;
            let path = match target.strip_prefix('/') {
                Some(abs) => abs.to_string(),
                None => format!("xl/{target}"),
            };
            Some((name, path))
        })
        .collect()
}

fn unescape(s: &str) -> String {
    s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&apos;", "'").replace("&amp;", "&")
}

fn escape(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;")
}

/// Reads the VBA project of `path`. `Ok(None)` if the file has no macros.
pub fn read_macro_parts(path: &str) -> Result<Option<MacroParts>, String> {
    let file = File::open(path).map_err(|e| e.to_string())?;
    let mut zip = ZipArchive::new(file).map_err(|e| e.to_string())?;
    let names: Vec<String> = zip.file_names().filter_map(|n| n.ok().map(|n| n.into_owned())).collect();
    let vba: Vec<String> = names
        .iter()
        .filter(|n| n.starts_with("xl/vbaProject") || n.starts_with("xl/_rels/vbaProject"))
        .cloned()
        .collect();
    if !vba.iter().any(|n| n == "xl/vbaProject.bin") {
        return Ok(None);
    }
    let mut parts = MacroParts::default();
    for n in &vba {
        let data = read_entry(&mut zip, n).ok_or_else(|| format!("cannot read {n}"))?;
        parts.files.push((n.clone(), data));
    }
    if let Some(ct) = read_text(&mut zip, "[Content_Types].xml") {
        parts.overrides = elements(&ct, "Override")
            .into_iter()
            .filter(|o| attr_in(o, "PartName").is_some_and(|p| p.starts_with("/xl/vbaProject")))
            .map(|o| if o.ends_with("/>") { o.to_string() } else { format!("{}/>", o.trim_end_matches('>')) })
            .collect();
    }
    let workbook = read_text(&mut zip, "xl/workbook.xml").unwrap_or_default();
    let rels = read_text(&mut zip, "xl/_rels/workbook.xml.rels").unwrap_or_default();
    parts.workbook_code_name = attr_of(&workbook, "workbookPr", "codeName");
    parts.project_guid = attr_of(&workbook, "fileVersion", "codeName");
    for (name, part) in sheet_parts(&workbook, &rels) {
        if let Some(sheet) = read_text(&mut zip, &part) {
            if let Some(code) = attr_of(&sheet, "sheetPr", "codeName") {
                parts.sheet_code_names.insert(name, code);
            }
        }
    }
    Ok(Some(parts))
}

/// Adds `codeName="…"` to the first `<tag>` element, or inserts `<tag codeName="…"/>` with `insert`.
fn set_code_name(xml: &str, tag: &str, code: &str, insert: impl FnOnce(&str, String) -> Option<String>) -> String {
    let attr = format!(" codeName=\"{}\"", escape(code));
    if let Some(start) = find_tag(xml, tag) {
        let el_end = start + xml[start..].find('>').unwrap_or(0);
        if attr_in(&xml[start..el_end], "codeName").is_some() {
            return xml.to_string();
        }
        let at = start + tag.len() + 1;
        return format!("{}{}{}", &xml[..at], attr, &xml[at..]);
    }
    insert(xml, format!("<{tag}{attr}/>")).unwrap_or_else(|| xml.to_string())
}

/// Element inserted right after the opening `<root ...>` tag (sheetPr must be the first child).
fn insert_after_root(xml: &str, root: &str, el: String) -> Option<String> {
    let start = find_tag(xml, root)?;
    let end = start + xml[start..].find('>')? + 1;
    Some(format!("{}{}{}", &xml[..end], el, &xml[end..]))
}

/// Element inserted before the first of `before` found (schema order of CT_Workbook).
fn insert_before(xml: &str, before: &[&str], el: String) -> Option<String> {
    let at = before.iter().filter_map(|t| find_tag(xml, t)).min()?;
    Some(format!("{}{}{}", &xml[..at], el, &xml[at..]))
}

/// Rewrites the xlsx package at `xlsx` into a macro-enabled package at `out`.
pub fn write_xlsm(xlsx: &str, macros: &MacroParts, out: &str) -> Result<(), String> {
    let mut zip = ZipArchive::new(File::open(xlsx).map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
    let workbook = read_text(&mut zip, "xl/workbook.xml").ok_or("workbook.xml missing")?;
    let rels = read_text(&mut zip, "xl/_rels/workbook.xml.rels").ok_or("workbook.xml.rels missing")?;
    let types = read_text(&mut zip, "[Content_Types].xml").ok_or("[Content_Types].xml missing")?;

    let mut replaced: HashMap<String, Vec<u8>> = HashMap::new();
    // Content types: macro-enabled main part, .bin default, signature overrides.
    let mut ct = types.replace(XLSX_MAIN, XLSM_MAIN);
    let mut extra = String::new();
    if !ct.contains("Extension=\"bin\"") {
        extra.push_str(&format!("<Default Extension=\"bin\" ContentType=\"{VBA_CONTENT_TYPE}\"/>"));
    }
    for o in &macros.overrides {
        if let Some(p) = attr_in(o, "PartName") {
            if !ct.contains(&format!("PartName=\"{p}\"")) {
                extra.push_str(o);
            }
        }
    }
    if let Some(i) = ct.rfind("</Types>") {
        ct.insert_str(i, &extra);
    }
    replaced.insert("[Content_Types].xml".into(), ct.into_bytes());

    // Workbook relationship to the VBA project.
    if !rels.contains(VBA_REL_TYPE) {
        let mut n = 1;
        while rels.contains(&format!("Id=\"rId{n}\"")) {
            n += 1;
        }
        let rel = format!("<Relationship Id=\"rId{n}\" Type=\"{VBA_REL_TYPE}\" Target=\"vbaProject.bin\"/>");
        let i = rels.rfind("</Relationships>").ok_or("bad workbook.xml.rels")?;
        replaced.insert("xl/_rels/workbook.xml.rels".into(), format!("{}{}{}", &rels[..i], rel, &rels[i..]).into_bytes());
    }

    // Code names (fileVersion is the first child of <workbook>, workbookPr comes after it).
    let mut wb = workbook.clone();
    if let Some(guid) = &macros.project_guid {
        wb = set_code_name(&wb, "fileVersion", guid, |x, el| insert_after_root(x, "workbook", el));
    }
    if let Some(code) = &macros.workbook_code_name {
        wb = set_code_name(&wb, "workbookPr", code, |x, el| {
            insert_before(x, &["workbookProtection", "bookViews", "sheets"], el)
        });
    }
    if wb != workbook {
        replaced.insert("xl/workbook.xml".into(), wb.into_bytes());
    }
    for (name, part) in sheet_parts(&workbook, &rels) {
        let Some(code) = macros.sheet_code_names.get(&name) else { continue };
        let Some(sheet) = read_text(&mut zip, &part) else { continue };
        let new = set_code_name(&sheet, "sheetPr", code, |x, el| insert_after_root(x, "worksheet", el));
        replaced.insert(part, new.into_bytes());
    }

    let mut w = ZipWriter::new(File::create(out).map_err(|e| e.to_string())?);
    let opts = SimpleFileOptions::default().compression_method(CompressionMethod::Deflated);
    for i in 0..zip.len() {
        let entry = zip.by_index_raw(i).map_err(|e| e.to_string())?;
        let name = entry.name().map_err(|e| e.to_string())?.into_owned();
        if let Some(data) = replaced.get(&name) {
            drop(entry);
            w.start_file(name.as_str(), opts).map_err(|e| e.to_string())?;
            w.write_all(data).map_err(|e| e.to_string())?;
        } else {
            w.raw_copy_file(entry).map_err(|e| e.to_string())?;
        }
    }
    for (name, data) in &macros.files {
        if zip.index_for_name(name).is_none() {
            w.start_file(name.as_str(), opts).map_err(|e| e.to_string())?;
            w.write_all(data).map_err(|e| e.to_string())?;
        }
    }
    w.finish().map_err(|e| e.to_string())?;
    Ok(())
}

// =====================================================================
// C ABI
// =====================================================================

/// 1 if `path` is a zip package with a VBA project (`xl/vbaProject.bin`), else 0.
///
/// # Safety
/// `path` must be a valid NUL-terminated string.
#[no_mangle]
pub unsafe extern "C" fn foglio_has_macros(path: *const c_char) -> i32 {
    let Some(path) = cstr(path) else { return 0 };
    match catch_unwind(|| read_macro_parts(path)) {
        Ok(Ok(Some(_))) => 1,
        _ => 0,
    }
}

/// Saves the workbook as .xlsm at `path`, keeping the VBA project of `macro_source`
/// (the macro-enabled file the workbook was opened from). Replaced atomically.
/// Returns 0 on success, -1 on failure (message in *err_out).
///
/// # Safety
/// `b` must come from this library; `path` and `macro_source` must be valid NUL-terminated
/// strings; `err_out` must be null or point to writable storage.
#[no_mangle]
pub unsafe extern "C" fn foglio_save_xlsm(
    b: *mut FoglioBook,
    path: *const c_char,
    macro_source: *const c_char,
    err_out: *mut *mut c_char,
) -> i32 {
    let (Some(b), Some(path), Some(src)) = (book(b), cstr(path), cstr(macro_source)) else {
        write_err(err_out, "invalid arguments".into());
        return -1;
    };
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<(), String> {
        let macros = read_macro_parts(src)?.ok_or("the original file has no macros")?;
        let tmp_xlsx = format!("{path}.foglio-tmp.xlsx");
        let tmp_xlsm = format!("{path}.foglio-tmp.xlsm");
        let _ = std::fs::remove_file(&tmp_xlsx);
        let _ = std::fs::remove_file(&tmp_xlsm);
        let saved = ironcalc::export::save_to_xlsx(b.model.get_model(), &tmp_xlsx).map_err(|e| format!("{e:?}"));
        let res = saved.and_then(|_| write_xlsm(&tmp_xlsx, &macros, &tmp_xlsm));
        let _ = std::fs::remove_file(&tmp_xlsx);
        match res {
            Ok(()) => std::fs::rename(&tmp_xlsm, path).map_err(|e| e.to_string()),
            Err(e) => {
                let _ = std::fs::remove_file(&tmp_xlsm);
                Err(e)
            }
        }
    }));
    match result {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => {
            write_err(err_out, e);
            -1
        }
        Err(_) => {
            write_err(err_out, "engine panicked while saving".into());
            -1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn code_name_added_to_existing_or_new_element() {
        let s = r#"<worksheet xmlns="x"><sheetPr><tabColor rgb="FF0000"/></sheetPr><sheetData/></worksheet>"#;
        let out = set_code_name(s, "sheetPr", "Foglio1", |x, el| insert_after_root(x, "worksheet", el));
        assert!(out.contains(r#"<sheetPr codeName="Foglio1"><tabColor"#), "{out}");
        let s = r#"<worksheet xmlns="x"><dimension ref="A1"/></worksheet>"#;
        let out = set_code_name(s, "sheetPr", "Sheet1", |x, el| insert_after_root(x, "worksheet", el));
        assert!(out.contains(r#"<worksheet xmlns="x"><sheetPr codeName="Sheet1"/><dimension"#), "{out}");
        // <sheetPr> must not match <sheetProtection>.
        let s = r#"<worksheet><sheetProtection sheet="1"/></worksheet>"#;
        let out = set_code_name(s, "sheetPr", "S", |x, el| insert_after_root(x, "worksheet", el));
        assert!(out.starts_with(r#"<worksheet><sheetPr codeName="S"/><sheetProtection"#), "{out}");
    }

    #[test]
    fn workbook_pr_goes_before_book_views() {
        let s = r#"<workbook><bookViews><workbookView/></bookViews><sheets/></workbook>"#;
        let out = set_code_name(s, "workbookPr", "ThisWorkbook", |x, el| {
            insert_before(x, &["workbookProtection", "bookViews", "sheets"], el)
        });
        assert_eq!(out, r#"<workbook><workbookPr codeName="ThisWorkbook"/><bookViews><workbookView/></bookViews><sheets/></workbook>"#);
        let out = set_code_name(&out, "fileVersion", "{GUID}", |x, el| insert_after_root(x, "workbook", el));
        assert!(out.starts_with(r#"<workbook><fileVersion codeName="{GUID}"/><workbookPr"#), "{out}");
    }
}
