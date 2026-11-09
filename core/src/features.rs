//! Feature C ABI: comments (notes), data validation, font name, sheet tab colour,
//! hyperlinks and a "pivot-lite" summary. Declared in include/foglio_features.h.

use std::ffi::c_char;
use std::ptr;

use ironcalc::base::cell::CellValue;
use ironcalc::base::data_validation::{DataValidation, DataValidationErrorStyle};
use ironcalc::base::types::{CellType, Color, Link};
use serde_json::{json, Value};

use crate::{area, book, book_ref, cstr, guard, parse_rgb, rc, to_c, write_err, FoglioBook, NO_COLOR};

fn ints_out(v: Vec<i32>, n: usize, out_n: *mut usize) -> *mut i32 {
    if !out_n.is_null() {
        unsafe { *out_n = n };
    }
    let mut v = v.into_boxed_slice();
    let p = v.as_mut_ptr();
    std::mem::forget(v);
    p
}

// ---------- comments ----------

/// The text of the comment of the cell, NULL if there is none.
#[no_mangle]
pub extern "C" fn foglio_comment_get(b: *const FoglioBook, sheet: u32, row: i32, col: i32) -> *mut c_char {
    let Some(b) = book_ref(b) else { return ptr::null_mut() };
    guard(ptr::null_mut(), || match b.model.get_comment(sheet, row, col) {
        Ok(Some(c)) => to_c(c.text),
        _ => ptr::null_mut(),
    })
}

/// The author of the comment of the cell ("" if unknown), NULL if there is no comment.
#[no_mangle]
pub extern "C" fn foglio_comment_author(b: *const FoglioBook, sheet: u32, row: i32, col: i32) -> *mut c_char {
    let Some(b) = book_ref(b) else { return ptr::null_mut() };
    guard(ptr::null_mut(), || match b.model.get_comment(sheet, row, col) {
        Ok(Some(c)) => to_c(c.author_name),
        _ => ptr::null_mut(),
    })
}

/// Sets (replaces) the comment of a cell. NULL or empty text deletes it. Undoable.
#[no_mangle]
pub unsafe extern "C" fn foglio_comment_set(
    b: *mut FoglioBook, sheet: u32, row: i32, col: i32, text: *const c_char, author: *const c_char,
) -> i32 {
    let Some(b) = book(b) else { return -1 };
    let text = cstr(text).unwrap_or("").to_string();
    let author = cstr(author).unwrap_or("").to_string();
    guard(-1, || rc(b.model.set_comment(sheet, row, col, &text, &author)))
}

#[no_mangle]
pub extern "C" fn foglio_comment_delete(b: *mut FoglioBook, sheet: u32, row: i32, col: i32) -> i32 {
    let Some(b) = book(b) else { return -1 };
    guard(-1, || rc(b.model.delete_comment(sheet, row, col)))
}

/// Cells with a comment in the inclusive range: 2 ints (row, col) per cell, sorted.
/// Free with foglio_ints_free(ptr, 2 * n).
#[no_mangle]
pub unsafe extern "C" fn foglio_comment_cells(
    b: *const FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32, out_n: *mut usize,
) -> *mut i32 {
    let Some(b) = book_ref(b) else { return ptr::null_mut() };
    guard(ptr::null_mut(), || {
        let cells = b.model.get_comment_cells(&area(sheet, r0, c0, r1, c1)).unwrap_or_default();
        let v: Vec<i32> = cells.iter().flat_map(|(r, c)| [*r, *c]).collect();
        ints_out(v, cells.len(), out_n)
    })
}

/// All comments of the sheet: [{"row":2,"col":3,"text":"…","author":"…"}, …] sorted by position.
#[no_mangle]
pub extern "C" fn foglio_comments_json(b: *const FoglioBook, sheet: u32) -> *mut c_char {
    let Some(b) = book_ref(b) else { return ptr::null_mut() };
    guard(ptr::null_mut(), || {
        let Ok(comments) = b.model.get_comments(sheet) else { return ptr::null_mut() };
        let mut list: Vec<(i32, i32, Value)> = comments
            .iter()
            .filter_map(|c| {
                let (r, col) = ironcalc::base::data_validation::comment_position(c)?;
                Some((r, col, json!({"row": r, "col": col, "text": c.text, "author": c.author_name})))
            })
            .collect();
        list.sort_by_key(|(r, c, _)| (*r, *c));
        to_c(Value::Array(list.into_iter().map(|x| x.2).collect()).to_string())
    })
}

// ---------- data validation ----------

/// Applies a validation rule (JSON, see foglio_features.h) to the range, replacing the
/// rules those cells had. Formulas are in user form (workbook language/locale). Undoable.
#[no_mangle]
pub unsafe extern "C" fn foglio_validation_set(
    b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32, rule_json: *const c_char,
    err_out: *mut *mut c_char,
) -> i32 {
    let (Some(b), Some(rule_json)) = (book(b), cstr(rule_json)) else { return -1 };
    let res = guard(Err("engine panicked".to_string()), || {
        let rule: DataValidation = serde_json::from_str(rule_json).map_err(|e| format!("invalid rule: {e}"))?;
        let a = area(sheet, r0, c0, r1, c1);
        let rule = b.model.data_validation_from_user(sheet, (a.row, a.column), rule)?;
        b.model.set_data_validation(&a, rule)
    });
    match res {
        Ok(()) => 0,
        Err(e) => {
            write_err(err_out, e);
            -1
        }
    }
}

/// Removes data validation from the range. Undoable.
#[no_mangle]
pub extern "C" fn foglio_validation_clear(b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32) -> i32 {
    let Some(b) = book(b) else { return -1 };
    guard(-1, || rc(b.model.clear_data_validation(&area(sheet, r0, c0, r1, c1))))
}

/// The rule of the cell as JSON (formulas in user form), NULL if the cell has none.
#[no_mangle]
pub extern "C" fn foglio_validation_get(b: *const FoglioBook, sheet: u32, row: i32, col: i32) -> *mut c_char {
    let Some(b) = book_ref(b) else { return ptr::null_mut() };
    guard(ptr::null_mut(), || match b.model.get_data_validation(sheet, row, col) {
        Ok(Some(rule)) => {
            let user = b.model.data_validation_to_user(sheet, &rule);
            serde_json::to_string(&user).map(to_c).unwrap_or(ptr::null_mut())
        }
        _ => ptr::null_mut(),
    })
}

/// The items of the list validation of the cell as a JSON array of strings (displayed
/// values), NULL if the cell has no list validation.
#[no_mangle]
pub extern "C" fn foglio_validation_list(b: *mut FoglioBook, sheet: u32, row: i32, col: i32) -> *mut c_char {
    let Some(b) = book(b) else { return ptr::null_mut() };
    guard(ptr::null_mut(), || match b.model.get_data_validation_list(sheet, row, col) {
        Ok(Some(items)) => to_c(Value::from(items).to_string()),
        _ => ptr::null_mut(),
    })
}

/// The items of the list validation of the cell as JSON [{"display": "…", "input": "…"}, …]:
/// what the dropdown shows and what to enter in the cell when the item is picked (for a
/// list taken from cells, the source cell's value as it would be typed, not its formatted
/// text). NULL if the cell has no list validation.
#[no_mangle]
pub extern "C" fn foglio_validation_list_items(b: *mut FoglioBook, sheet: u32, row: i32, col: i32) -> *mut c_char {
    let Some(b) = book(b) else { return ptr::null_mut() };
    guard(ptr::null_mut(), || {
        let Ok(Some(items)) = b.model.get_data_validation_list(sheet, row, col) else { return ptr::null_mut() };
        // Only trusted when it lists exactly what the engine shows (otherwise: input = display).
        let raw = list_source_inputs(b, sheet, row, col)
            .filter(|v| v.len() == items.len() && v.iter().zip(&items).all(|((d, _), i)| d == i));
        let out: Vec<Value> = match raw {
            Some(v) => v.into_iter().map(|(d, i)| json!({"display": d, "input": i})).collect(),
            None => items.into_iter().map(|d| json!({"display": d, "input": d})).collect(),
        };
        to_c(Value::Array(out).to_string())
    })
}

/// (displayed, typed) values of the source cells of a list rule that refers to a range
/// ("$A$1:$A$9", "Sheet2!A1:A9", "'O''Brien'!$B$2:$B$5", a defined name of such a range),
/// in the order the engine lists them. None for inline lists and other formulas.
fn list_source_inputs(b: &mut FoglioBook, sheet: u32, row: i32, col: i32) -> Option<Vec<(String, String)>> {
    let rule = b.model.get_data_validation(sheet, row, col).ok()??;
    let mut f = rule.formula1.clone()?.trim().trim_start_matches('=').trim().to_string();
    if ironcalc::base::data_validation::inline_list_items(&f).is_some() {
        return None;
    }
    let mut relative = true;
    if let Some((_, _, def)) = b
        .model
        .get_defined_name_list()
        .into_iter()
        .filter(|(n, s, _)| n.eq_ignore_ascii_case(&f) && (s.is_none() || *s == Some(sheet)))
        .max_by_key(|(_, s, _)| s.is_some())
    {
        f = def.trim().trim_start_matches('=').to_string();
        relative = false;
    }
    // optional sheet part
    let (src_sheet, reference) = match f.rfind('!') {
        Some(i) => {
            let name = f[..i].trim();
            let name = match name.strip_prefix('\'').and_then(|n| n.strip_suffix('\'')) {
                Some(q) => q.replace("''", "'"),
                None => name.to_string(),
            };
            let props = b.model.get_worksheets_properties();
            let idx = props.iter().position(|p| p.name.eq_ignore_ascii_case(&name))?;
            (idx as u32, f[i + 1..].to_string())
        }
        None => (sheet, f.clone()),
    };
    // "A1" or "A1:B5", with optional $; relative parts follow the cell like the engine does
    let anchor = ironcalc::base::data_validation::parse_sqref_rects(&rule.sqref).first().map(|r| (r.0, r.1)).unwrap_or((1, 1));
    let (dr, dc) = if relative { (row - anchor.0, col - anchor.1) } else { (0, 0) };
    let corner = |s: &str| -> Option<(i32, i32)> {
        let s = s.trim();
        let (col_abs, s) = match s.strip_prefix('$') { Some(t) => (true, t), None => (false, s) };
        let letters: String = s.chars().take_while(|c| c.is_ascii_alphabetic()).collect();
        let rest = &s[letters.len()..];
        let (row_abs, digits) = match rest.strip_prefix('$') { Some(t) => (true, t), None => (false, rest) };
        if letters.is_empty() || digits.is_empty() || !digits.chars().all(|c| c.is_ascii_digit()) {
            return None;
        }
        let c = ironcalc::base::expressions::utils::column_to_number(&letters.to_uppercase()).ok()?;
        let r = digits.parse::<i32>().ok()?;
        Some((if row_abs { r } else { r + dr }, if col_abs { c } else { c + dc }))
    };
    let (a, z) = match reference.split_once(':') {
        Some((a, z)) => (corner(a)?, corner(z)?),
        None => {
            let a = corner(&reference)?;
            (a, a)
        }
    };
    let (r0, r1, c0, c1) = (a.0.min(z.0), a.0.max(z.0), a.1.min(z.1), a.1.max(z.1));
    if r0 < 1 || c0 < 1 {
        return None;
    }
    // the engine stops at its item limit; so do we (and the result is then compared)
    let dim = b.model.get_model().workbook.worksheets.get(src_sheet as usize)?.dimension();
    let (r1, c1) = (r1.min(dim.max_row), c1.min(dim.max_column));
    let mut out = Vec::new();
    for r in r0..=r1 {
        for c in c0..=c1 {
            if out.len() > 10_000 {
                return None;
            }
            let display = b.model.get_formatted_cell_value(src_sheet, r, c).unwrap_or_default();
            if display.is_empty() {
                continue;
            }
            let model = b.model.get_model();
            let is_formula = model
                .workbook
                .worksheets
                .get(src_sheet as usize)
                .and_then(|ws| ws.cell(r, c).map(|x| x.get_formula().is_some()))
                .unwrap_or(false);
            let input = if !is_formula {
                b.model.get_cell_content(src_sheet, r, c).unwrap_or_else(|_| display.clone())
            } else {
                match model.get_cell_value_by_index(src_sheet, r, c).unwrap_or(CellValue::None) {
                    CellValue::Number(n) => {
                        let lit = if n.fract() == 0.0 && n.abs() < 1e15 { format!("={}", n as i64) } else { format!("={n}") };
                        b.model.english_formula_to_user(src_sheet, r, c, &lit).trim_start_matches('=').to_string()
                    }
                    CellValue::Boolean(v) => b
                        .model
                        .english_formula_to_user(src_sheet, r, c, if v { "=TRUE" } else { "=FALSE" })
                        .trim_start_matches('=')
                        .to_string(),
                    CellValue::String(s) => literal_text_input(&s),
                    CellValue::None => display.clone(),
                }
            };
            out.push((display, input));
        }
    }
    Some(out)
}

/// Text to type so that it stays text (a leading apostrophe when it could read as a number,
/// date, boolean or formula).
fn literal_text_input(s: &str) -> String {
    let t = s.trim();
    let first = t.chars().next();
    let risky = matches!(first, Some('=' | '+' | '-' | '\'' | '@'))
        || first.is_some_and(|c| c.is_ascii_digit() || c == '.' || c == ',')
        || ["TRUE", "FALSE", "VERO", "FALSO", "WAHR", "FALSCH", "VERDADERO", "VRAI", "FAUX"].contains(&t.to_uppercase().as_str());
    if risky { format!("'{s}") } else { s.to_string() }
}

/// Checks what the user is about to enter in the cell. 0 valid; otherwise the alert to
/// show: 1 stop, 2 warning, 3 information, with the rule's title and message (possibly
/// empty) in *title_out / *message_out (if not NULL; free with foglio_string_free).
#[no_mangle]
pub unsafe extern "C" fn foglio_validation_check(
    b: *mut FoglioBook, sheet: u32, row: i32, col: i32, input: *const c_char, title_out: *mut *mut c_char,
    message_out: *mut *mut c_char,
) -> i32 {
    let Some(b) = book(b) else { return 0 };
    let input = cstr(input).unwrap_or("").to_string();
    let result = guard(None, || b.model.validate_input(sheet, row, col, &input).ok());
    let Some(result) = result else { return 0 };
    let code = match result.error_style {
        None => return 0,
        Some(DataValidationErrorStyle::Stop) => 1,
        Some(DataValidationErrorStyle::Warning) => 2,
        Some(DataValidationErrorStyle::Information) => 3,
    };
    write_err(title_out, result.title);
    write_err(message_out, result.message);
    code
}

// ---------- font name ----------

/// The font name of the cell ("Calibri", "Arial", …).
#[no_mangle]
pub extern "C" fn foglio_font_name_at(b: *mut FoglioBook, sheet: u32, row: i32, col: i32) -> *mut c_char {
    let Some(b) = book(b) else { return ptr::null_mut() };
    guard(ptr::null_mut(), || match b.model.get_cell_style(sheet, row, col) {
        Ok(st) => to_c(st.font.name),
        Err(_) => ptr::null_mut(),
    })
}

// ---------- sheet tab colour ----------

/// 0xRRGGBB (theme colours resolved) or FOGLIO_NO_COLOR.
#[no_mangle]
pub extern "C" fn foglio_sheet_color(b: *const FoglioBook, sheet: u32) -> u32 {
    let Some(b) = book_ref(b) else { return NO_COLOR };
    guard(NO_COLOR, || {
        let model = b.model.get_model();
        match model.workbook.worksheets.get(sheet as usize).map(|w| &w.color) {
            Some(Color::None) | None => NO_COLOR,
            Some(c) => parse_rgb(&c.to_rgb(&model.workbook.theme)),
        }
    })
}

/// Sets the tab colour (0xRRGGBB), FOGLIO_NO_COLOR removes it. Undoable.
#[no_mangle]
pub extern "C" fn foglio_set_sheet_color(b: *mut FoglioBook, sheet: u32, rgb: u32) -> i32 {
    let Some(b) = book(b) else { return -1 };
    let color = if rgb == NO_COLOR { Color::None } else { Color::Rgb(format!("#{:06X}", rgb & 0xFF_FFFF)) };
    guard(-1, || rc(b.model.set_sheet_color(sheet, &color)))
}

// ---------- hyperlinks ----------

fn link_address(link: &Link) -> (String, Option<String>) {
    match link {
        Link::External { target, tooltip } => (target.clone(), tooltip.clone()),
        Link::Internal { location, tooltip } => (format!("#{location}"), tooltip.clone()),
    }
}

/// The link of the cell as JSON {"address":"https://…" | "#Sheet2!A1","tooltip":null|"…",
/// "dynamic":false}, NULL if none. "dynamic" links come from HYPERLINK() formulas.
#[no_mangle]
pub extern "C" fn foglio_link_get(b: *const FoglioBook, sheet: u32, row: i32, col: i32) -> *mut c_char {
    let Some(b) = book_ref(b) else { return ptr::null_mut() };
    guard(ptr::null_mut(), || {
        // Called on every hover: a direct map lookup; only formula cells can carry a dynamic
        // (HYPERLINK) link, and only for those the full list is built.
        let is_formula = || {
            b.model
                .get_model()
                .workbook
                .worksheets
                .get(sheet as usize)
                .and_then(|ws| ws.cell(row, col).map(|c| c.get_formula().is_some()))
                .unwrap_or(false)
        };
        let found = match b.model.get_cell_link(sheet, row, col) {
            Ok(Some(link)) => Some((link, false)),
            _ if is_formula() => b
                .model
                .get_links_list(sheet)
                .ok()
                .and_then(|l| l.into_iter().find(|v| v.row == row && v.column == col))
                .map(|v| (v.link, v.dynamic)),
            _ => None,
        };
        match found {
            Some((link, dynamic)) => {
                let (address, tooltip) = link_address(&link);
                to_c(json!({"address": address, "tooltip": tooltip, "dynamic": dynamic}).to_string())
            }
            None => ptr::null_mut(),
        }
    })
}

/// Attaches a link to the cell. address: URL / mailto: / file path, or "#Sheet2!A1" for a
/// place in this workbook. display (may be NULL/empty): becomes the cell text. tooltip may
/// be NULL. A new link also gets the link style. One undo step.
#[no_mangle]
pub unsafe extern "C" fn foglio_link_set(
    b: *mut FoglioBook, sheet: u32, row: i32, col: i32, address: *const c_char, display: *const c_char,
    tooltip: *const c_char,
) -> i32 {
    let (Some(b), Some(address)) = (book(b), cstr(address)) else { return -1 };
    let address = address.trim();
    if address.is_empty() || address == "#" {
        return -1;
    }
    let tooltip = cstr(tooltip).filter(|s| !s.is_empty()).map(str::to_string);
    let display = cstr(display).filter(|s| !s.is_empty());
    let link = match address.strip_prefix('#') {
        Some(location) => Link::Internal { location: location.to_string(), tooltip },
        None => Link::External { target: address.to_string(), tooltip },
    };
    let r = guard(-1, || rc(b.model.set_cell_link(sheet, row, col, link, display)));
    b.style_cache.clear();
    r
}

/// Removes the link of the cell (text and style stay). Undoable.
#[no_mangle]
pub extern "C" fn foglio_link_remove(b: *mut FoglioBook, sheet: u32, row: i32, col: i32) -> i32 {
    let Some(b) = book(b) else { return -1 };
    guard(-1, || rc(b.model.delete_cell_link(sheet, row, col)))
}

// ---------- summarize (pivot-lite) ----------

const AGG_FUNCTIONS: [&str; 5] = ["SUMIFS", "COUNTIFS", "AVERAGEIFS", "MINIFS", "MAXIFS"];

/// (aggregate label template, "Total", default sheet name) in the workbook language
fn summary_labels(language: &str, agg: usize) -> (String, &'static str, &'static str) {
    let (aggs, total, name): ([&str; 5], &str, &str) = match language {
        "it" => (["Somma di", "Conteggio di", "Media di", "Min di", "Max di"], "Totale", "Riepilogo"),
        "de" => (["Summe von", "Anzahl von", "Mittelwert von", "Min. von", "Max. von"], "Gesamtergebnis", "Zusammenfassung"),
        "es" => (["Suma de", "Cuenta de", "Promedio de", "Mín. de", "Máx. de"], "Total general", "Resumen"),
        "fr" => (["Somme de", "Nombre de", "Moyenne de", "Min. de", "Max. de"], "Total général", "Synthèse"),
        _ => (["Sum of", "Count of", "Average of", "Min of", "Max of"], "Total", "Summary"),
    };
    (aggs[agg].to_string(), total, name)
}

fn col_name(c: i32) -> String {
    ironcalc::base::expressions::utils::number_to_column(c).unwrap_or_default()
}

#[derive(Clone)]
enum Key {
    Number(f64),
    Text(String),
    Bool(bool),
}

/// A criteria for *IFS matching `text` exactly: wildcards and leading comparison
/// operators are escaped. None if the plain cell reference works.
fn literal_criteria(text: &str) -> Option<String> {
    let special = text.contains(['*', '?', '~']) || text.starts_with(['<', '>', '=']);
    if !special {
        return None;
    }
    let escaped: String = text
        .chars()
        .flat_map(|c| if matches!(c, '*' | '?' | '~') { vec!['~', c] } else { vec![c] })
        .collect();
    Some(format!("\"={}\"", escaped.replace('"', "\"\"")))
}

fn unique_sheet_name(b: &FoglioBook, base: &str) -> String {
    let names: Vec<String> = b.model.get_worksheets_properties().iter().map(|p| p.name.to_lowercase()).collect();
    let clean: String = base.chars().filter(|c| !"\\/*?:[]".contains(*c)).collect();
    let clean = clean.trim();
    let clean = if clean.is_empty() { "Summary" } else { clean };
    let fit = |s: &str, suffix: &str| -> String {
        let room = 31 - suffix.chars().count();
        format!("{}{suffix}", s.chars().take(room).collect::<String>())
    };
    let first = fit(clean, "");
    if !names.contains(&first.to_lowercase()) {
        return first;
    }
    (2..)
        .map(|i| fit(clean, &format!(" ({i})")))
        .find(|n| !names.contains(&n.to_lowercase()))
        .unwrap_or_default()
}

fn summarize(
    b: &mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32, group_col: i32, value_col: i32, agg: i32,
    name: Option<&str>,
) -> Result<u32, String> {
    let (r0, r1) = (r0.min(r1), r0.max(r1));
    let (c0, c1) = (c0.min(c1), c0.max(c1));
    if !(0..5).contains(&agg) {
        return Err("invalid aggregation".into());
    }
    let agg = agg as usize;
    if r1 <= r0 {
        return Err("the range needs a header row and at least one row of data".into());
    }
    if !(c0..=c1).contains(&group_col) || !(c0..=c1).contains(&value_col) {
        return Err("the columns must be inside the range".into());
    }
    let props = b.model.get_worksheets_properties();
    let source_name = props.get(sheet as usize).ok_or("invalid sheet")?.name.clone();
    let language = b.model.get_language();
    let header = |b: &FoglioBook, c: i32| {
        let h = b.model.get_formatted_cell_value(sheet, r0, c).unwrap_or_default();
        if h.trim().is_empty() { col_name(c) } else { h }
    };
    let group_header = header(b, group_col);
    let value_header = header(b, value_col);

    // distinct keys, case-insensitive like the *IFS criteria
    let mut keys: Vec<Key> = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for r in r0 + 1..=r1 {
        let value = b.model.get_model().get_cell_value_by_index(sheet, r, group_col).unwrap_or(CellValue::None);
        let (id, key) = match value {
            CellValue::None => continue,
            CellValue::String(s) if s.is_empty() => continue,
            CellValue::String(s) => (format!("s{}", s.to_lowercase()), Key::Text(s)),
            CellValue::Number(n) => (format!("n{n}"), Key::Number(n)),
            CellValue::Boolean(v) => (format!("b{v}"), Key::Bool(v)),
        };
        if seen.insert(id) {
            keys.push(key);
        }
    }
    if keys.is_empty() {
        return Err("the group column has no values".into());
    }
    let rank = |k: &Key| match k {
        Key::Number(_) => 0,
        Key::Text(_) => 1,
        Key::Bool(_) => 2,
    };
    keys.sort_by(|a, b| {
        rank(a).cmp(&rank(b)).then_with(|| match (a, b) {
            (Key::Number(x), Key::Number(y)) => x.total_cmp(y),
            (Key::Text(x), Key::Text(y)) => x.to_lowercase().cmp(&y.to_lowercase()),
            (Key::Bool(x), Key::Bool(y)) => x.cmp(y),
            _ => std::cmp::Ordering::Equal,
        })
    });

    let quoted = format!("'{}'", source_name.replace('\'', "''"));
    let src = |c: i32| format!("{quoted}!${0}${1}:${0}${2}", col_name(c), r0 + 1, r1);
    let (keys_ref, values_ref) = (src(group_col), src(value_col));
    let (agg_label, total_label, default_name) = summary_labels(&language, agg);
    let target_name = unique_sheet_name(b, name.filter(|n| !n.trim().is_empty()).unwrap_or(default_name));
    // source formats for the key and value columns
    let key_fmt = b.model.get_cell_style(sheet, r0 + 1, group_col).map(|s| s.num_fmt).unwrap_or_default();
    let value_fmt = b.model.get_cell_style(sheet, r0 + 1, value_col).map(|s| s.num_fmt).unwrap_or_default();

    b.model.begin_history_group();
    let created = std::cell::Cell::new(false);
    let result = (|| -> Result<u32, String> {
        b.model.new_sheet()?;
        created.set(true);
        let target = b.model.get_worksheets_properties().len() as u32 - 1;
        b.model.rename_sheet(target, &target_name)?;
        b.model.pause_evaluation();
        let set_text = |b: &mut FoglioBook, r: i32, c: i32, text: &str| -> Result<(), String> {
            b.model.set_user_input(target, r, c, text)?;
            if text.is_empty() || matches!(b.model.get_cell_type(target, r, c), Ok(CellType::Text)) {
                return Ok(());
            }
            // it was read as a number, date, boolean, formula…: keep it as text
            b.model.set_user_input(target, r, c, &format!("'{text}"))
        };
        let set_formula = |b: &mut FoglioBook, r: i32, c: i32, english: &str| -> Result<(), String> {
            let user = b.model.english_formula_to_user(target, r, c, english);
            b.model.set_user_input(target, r, c, &user)
        };
        set_text(b, 1, 1, &group_header)?;
        set_text(b, 1, 2, &format!("{agg_label} {value_header}"))?;
        let n = keys.len() as i32;
        for (i, key) in keys.iter().enumerate() {
            let row = i as i32 + 2;
            let criteria = match key {
                Key::Number(v) => {
                    // a number literal in the workbook locale ("1,5" in Italian)
                    let lit = b.model.english_formula_to_user(target, row, 1, &format!("={v}"));
                    b.model.set_user_input(target, row, 1, lit.trim_start_matches('='))?;
                    format!("$A{row}")
                }
                Key::Bool(v) => {
                    b.model.set_user_input(target, row, 1, if *v { "TRUE" } else { "FALSE" })?;
                    format!("$A{row}")
                }
                Key::Text(s) => {
                    set_text(b, row, 1, s)?;
                    literal_criteria(s).unwrap_or(format!("$A{row}"))
                }
            };
            let f = AGG_FUNCTIONS[agg];
            let formula = if agg == 1 {
                format!("={f}({keys_ref},{criteria})")
            } else {
                format!("={f}({values_ref},{keys_ref},{criteria})")
            };
            set_formula(b, row, 2, &formula)?;
        }
        let total_row = n + 2;
        set_text(b, total_row, 1, total_label)?;
        let total = match agg {
            0 | 1 => format!("=SUM(B2:B{})", n + 1),
            2 => format!("=AVERAGEIFS({values_ref},{keys_ref},\"<>\")"),
            3 => format!("=MIN(B2:B{})", n + 1),
            _ => format!("=MAX(B2:B{})", n + 1),
        };
        set_formula(b, total_row, 2, &total)?;
        b.model.resume_evaluation();
        b.model.evaluate();
        // formatting
        let bold = |b: &mut FoglioBook, r: i32| b.model.update_range_style(&area(target, r, 1, r, 2), "font.b", "true");
        bold(b, 1)?;
        bold(b, total_row)?;
        if !key_fmt.is_empty() && key_fmt != "general" {
            b.model.update_range_style(&area(target, 2, 1, n + 1, 1), "num_fmt", &key_fmt)?;
        }
        if agg != 1 && !value_fmt.is_empty() && value_fmt != "general" {
            b.model.update_range_style(&area(target, 2, 2, total_row, 2), "num_fmt", &value_fmt)?;
        }
        Ok(target)
    })();
    b.model.resume_evaluation();
    b.model.end_history_group();
    b.style_cache.clear();
    if result.is_err() && created.get() {
        // leave nothing behind (the group is one undo step)
        let _ = b.model.undo();
    }
    result
}

/// Creates a summary sheet of a table (see foglio_features.h). Returns the index of the
/// new sheet, or -1 (message in *err_out). One undo step.
#[no_mangle]
pub unsafe extern "C" fn foglio_summarize(
    b: *mut FoglioBook, sheet: u32, r0: i32, c0: i32, r1: i32, c1: i32, group_col: i32, value_col: i32, agg: i32,
    target_name: *const c_char, err_out: *mut *mut c_char,
) -> i32 {
    let Some(b) = book(b) else { return -1 };
    let name = cstr(target_name);
    let res = guard(Err("engine panicked".to_string()), || {
        summarize(b, sheet, r0, c0, r1, c1, group_col, value_col, agg, name)
    });
    match res {
        Ok(i) => i as i32,
        Err(e) => {
            write_err(err_out, e);
            -1
        }
    }
}

// ---------- sheet view: zoom, AutoFilter (Foglio fork) ----------

/// The zoom saved for the sheet, in percent (0 = not set).
#[no_mangle]
pub extern "C" fn foglio_sheet_zoom(b: *const FoglioBook, sheet: u32) -> u32 {
    let Some(b) = book_ref(b) else { return 0 };
    guard(0, || b.model.get_model().workbook.worksheets.get(sheet as usize).map_or(0, |w| w.zoom as u32))
}

/// Stores the sheet's zoom (10–400 %, 0 = default); saved to `.xlsx`. Not undoable.
#[no_mangle]
pub extern "C" fn foglio_set_sheet_zoom(b: *mut FoglioBook, sheet: u32, zoom: u32) -> i32 {
    let Some(b) = book(b) else { return -1 };
    let zoom = if zoom == 0 { 0 } else { zoom.clamp(10, 400) as u16 };
    guard(-1, || rc(b.model.set_sheet_zoom(sheet, zoom)))
}

/// The sheet's AutoFilter as JSON `{"range":"A1:L40","columns":[{"col_id":2,"values":["x"],"blank":false}]}`,
/// NULL when there is none.
#[no_mangle]
pub extern "C" fn foglio_autofilter_get(b: *const FoglioBook, sheet: u32) -> *mut c_char {
    let Some(b) = book_ref(b) else { return ptr::null_mut() };
    guard(ptr::null_mut(), || {
        match b.model.get_model().workbook.worksheets.get(sheet as usize).and_then(|w| w.auto_filter.as_ref()) {
            Some(af) => serde_json::to_string(af).map(to_c).unwrap_or(ptr::null_mut()),
            None => ptr::null_mut(),
        }
    })
}

/// Sets the sheet's AutoFilter from JSON (same shape as `foglio_autofilter_get`); NULL or "" removes it.
#[no_mangle]
pub unsafe extern "C" fn foglio_autofilter_set(b: *mut FoglioBook, sheet: u32, json: *const c_char) -> i32 {
    let Some(b) = book(b) else { return -1 };
    let text = cstr(json).unwrap_or("").trim().to_string();
    guard(-1, || {
        let af = if text.is_empty() {
            None
        } else {
            match serde_json::from_str::<ironcalc::base::types::AutoFilter>(&text) {
                Ok(af) => Some(af),
                Err(_) => return -1,
            }
        };
        rc(b.model.set_auto_filter(sheet, af))
    })
}
