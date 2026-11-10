//! File import/export: open any common spreadsheet format, save CSV.
//! See include/foglio_io.h for the C contract.
//!
//! * .xlsx/.xlsm/.xltx/.xltm -> IronCalc's own importer (full fidelity); calamine fallback (values + formulas).
//! * .xls/.xlt/.xlsb/.ods -> calamine (values + formulas, dates get a date number format).
//! * .csv/.tsv/.txt -> encoding + delimiter sniffing, `csv` crate parser.
//! * anything else -> content sniffing (zip / OLE / text).

use std::collections::{HashMap, HashSet};
use std::ffi::c_char;
use std::fs::File;
use std::io::{BufReader, Read, Write};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::Path;
use std::ptr;

use calamine::{open_workbook, Data, Ods, Reader, Sheets, Xls, Xlsb, Xlsx};
use ironcalc::base::expressions::token::Error as CalcError;
use ironcalc::base::types::CellType;
use ironcalc::base::{Model, UserModel};

use crate::{book_ref, cstr, settings, to_c, write_err, FoglioBook};

const LAST_ROW: u32 = 1_048_576;
const LAST_COLUMN: u32 = 16_384;

const SUPPORTED_EXTENSIONS: &str = "xlsx,xlsm,xltx,xltm,xls,xlt,xlsb,ods,csv,tsv,txt";

// =====================================================================
// C ABI
// =====================================================================

/// Opens any supported spreadsheet file. Returns null and sets *err_out on failure.
///
/// # Safety
/// `path` must be a valid NUL-terminated string; `err_out` must be null or point to writable storage.
#[no_mangle]
pub unsafe extern "C" fn foglio_open_any(path: *const c_char, err_out: *mut *mut c_char) -> *mut FoglioBook {
    let Some(path) = cstr(path) else {
        write_err(err_out, "invalid path".into());
        return ptr::null_mut();
    };
    let result = catch_unwind(AssertUnwindSafe(|| open_any(path)));
    match result {
        Ok(Ok(model)) => FoglioBook::wrap(UserModel::from_model(model)),
        Ok(Err(e)) => {
            write_err(err_out, e);
            ptr::null_mut()
        }
        Err(_) => {
            write_err(err_out, "the engine panicked while reading the file".into());
            ptr::null_mut()
        }
    }
}

/// Writes the formatted values of `sheet`'s used range to `path` as CSV (UTF-8, RFC 4180, CRLF).
/// `delimiter` is an ASCII byte (0 means ','). Returns 0 on success, -1 on failure.
///
/// # Safety
/// `b` must come from this library; `path` must be a valid NUL-terminated string;
/// `err_out` must be null or point to writable storage.
#[no_mangle]
pub unsafe extern "C" fn foglio_save_csv(
    b: *mut FoglioBook,
    sheet: u32,
    path: *const c_char,
    delimiter: u8,
    err_out: *mut *mut c_char,
) -> i32 {
    let Some(b) = book_ref(b) else {
        write_err(err_out, "invalid workbook".into());
        return -1;
    };
    let Some(path) = cstr(path) else {
        write_err(err_out, "invalid path".into());
        return -1;
    };
    let delimiter = if delimiter == 0 { b',' } else { delimiter };
    if !delimiter.is_ascii() || matches!(delimiter, b'"' | b'\r' | b'\n') {
        write_err(err_out, "invalid delimiter".into());
        return -1;
    }
    let result = catch_unwind(AssertUnwindSafe(|| save_csv(b.model.get_model(), sheet, path, delimiter)));
    match result {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => {
            write_err(err_out, e);
            -1
        }
        Err(_) => {
            write_err(err_out, "the engine panicked while saving".into());
            -1
        }
    }
}

/// Comma-separated list of the file extensions foglio_open_any understands (lowercase, no dots).
#[no_mangle]
pub extern "C" fn foglio_supported_extensions() -> *mut c_char {
    to_c(SUPPORTED_EXTENSIONS.to_string())
}

// =====================================================================
// Dispatch
// =====================================================================

#[derive(Clone, Copy, PartialEq, Debug)]
enum Kind {
    Xlsx,
    Xls,
    Xlsb,
    Ods,
    Text,
}

pub(crate) fn open_any(path: &str) -> Result<Model<'static>, String> {
    let ext = Path::new(path)
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_ascii_lowercase())
        .unwrap_or_default();
    let kind = match ext.as_str() {
        "xlsx" | "xlsm" | "xltx" | "xltm" => Kind::Xlsx,
        "xls" | "xlt" => Kind::Xls,
        "xlsb" => Kind::Xlsb,
        "ods" => Kind::Ods,
        "csv" | "tsv" | "txt" | "tab" => Kind::Text,
        _ => sniff(path)?,
    };
    let mut model = match kind {
        Kind::Xlsx => open_xlsx(path)?,
        Kind::Xls => open_calamine(path, kind)?,
        Kind::Xlsb => open_calamine(path, kind)?,
        Kind::Ods => open_calamine(path, kind)?,
        Kind::Text => open_text(path, &ext)?,
    };
    if let Some(stem) = Path::new(path).file_stem().and_then(|s| s.to_str()) {
        model.workbook.name = stem.to_string();
    }
    Ok(model)
}

fn sniff(path: &str) -> Result<Kind, String> {
    let mut head = [0u8; 128];
    let n = File::open(path)
        .and_then(|mut f| f.read(&mut head))
        .map_err(|e| format!("cannot read file: {e}"))?;
    let head = &head[..n];
    if head.starts_with(b"PK\x03\x04") {
        // OpenDocument stores an uncompressed "mimetype" entry first.
        if head.windows(46).any(|w| w == b"application/vnd.oasis.opendocument.spreadsheet") {
            return Ok(Kind::Ods);
        }
        return Ok(Kind::Xlsx); // xlsx/xlsm; xlsb is tried as a fallback in open_xlsx
    }
    if head.starts_with(&[0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) {
        return Ok(Kind::Xls);
    }
    Ok(Kind::Text)
}

/// Benchmark/test hook: load an xlsx through the calamine path (the xls/xlsb/ods code path).
#[doc(hidden)]
pub fn bench_open_with_calamine(path: &str) -> Result<Model<'static>, String> {
    open_calamine(path, Kind::Xlsx)
}

fn open_xlsx(path: &str) -> Result<Model<'static>, String> {
    let (locale, language, tz) = settings();
    let primary = catch_unwind(|| ironcalc::import::load_from_xlsx(path, locale, tz, language));
    let primary_err = match primary {
        Ok(Ok(mut model)) => {
            model.evaluate();
            return Ok(model);
        }
        Ok(Err(e)) => format!("{e:?}"),
        Err(_) => "engine panicked".to_string(),
    };
    // Fallback: values + formulas through calamine (xlsx, or xlsb with a wrong extension).
    match open_calamine(path, Kind::Xlsx).or_else(|_| open_calamine(path, Kind::Xlsb)) {
        Ok(m) => Ok(m),
        Err(e) => Err(format!("Could not open the workbook ({primary_err}; fallback reader: {e})")),
    }
}

// =====================================================================
// calamine (xls, xlsb, ods, xlsx fallback)
// =====================================================================

/// Lazily created number-format styles.
struct FormatStyles {
    cache: HashMap<&'static str, i32>,
}

impl FormatStyles {
    fn get(&mut self, model: &mut Model, fmt: &'static str) -> i32 {
        if let Some(i) = self.cache.get(fmt) {
            return *i;
        }
        let mut style = model.get_style_for_cell(0, 1, 1).unwrap_or_default();
        style.num_fmt = fmt.to_string();
        style.quote_prefix = false;
        let idx = model.workbook.styles.create_new_style(&style);
        self.cache.insert(fmt, idx);
        idx
    }
}

const FMT_DATE: &str = "dd/mm/yyyy";
const FMT_DATETIME: &str = "dd/mm/yyyy hh:mm";
const FMT_TIME: &str = "hh:mm:ss";
const FMT_DURATION: &str = "[h]:mm:ss";

fn open_calamine(path: &str, kind: Kind) -> Result<Model<'static>, String> {
    let err = |e: &dyn std::fmt::Display| format!("Could not read the file: {e}");
    let mut wb: Sheets<BufReader<File>> = match kind {
        Kind::Xls => Sheets::Xls(open_workbook::<Xls<_>, _>(path).map_err(|e| err(&e))?),
        Kind::Xlsb => Sheets::Xlsb(open_workbook::<Xlsb<_>, _>(path).map_err(|e| err(&e))?),
        Kind::Ods => Sheets::Ods(open_workbook::<Ods<_>, _>(path).map_err(|e| err(&e))?),
        Kind::Xlsx => Sheets::Xlsx(open_workbook::<Xlsx<_>, _>(path).map_err(|e| err(&e))?),
        Kind::Text => return Err("not a workbook".into()),
    };
    let is_ods = kind == Kind::Ods;
    let is_biff = matches!(kind, Kind::Xls | Kind::Xlsb);
    let xti = if kind == Kind::Xls { xls_extern_sheets(path) } else { None };

    // calamine's formulas are in English syntax ("SUM(A1;B1)" would not parse): build the model
    // in English, then switch to the app's locale/language. Formulas are stored in an internal
    // form, so they are shown in the new language afterwards; values are set locale-independently.
    let (locale, language, tz) = settings();
    let mut model = Model::new_empty("Workbook", "en", tz, "en")?;
    let names = wb.sheet_names();
    if names.is_empty() {
        return Err("the workbook has no sheets".into());
    }

    // Sheet names: IronCalc rules (max 31 chars, no []*?:/\, unique case-insensitively).
    let mut used: HashSet<String> = HashSet::new();
    let mut final_names = Vec::with_capacity(names.len());
    for name in &names {
        let n = unique_sheet_name(name, &mut used);
        final_names.push(n);
    }
    model.rename_sheet_by_index(0, &final_names[0])?;
    for n in &final_names[1..] {
        model.add_sheet(n)?;
    }

    let mut styles = FormatStyles { cache: HashMap::new() };
    // Every formula cell with the value cached in the file, to repair failures after evaluation.
    let mut formula_cells: Vec<FormulaCell> = Vec::new();

    for (si, name) in names.iter().enumerate() {
        let sheet = si as u32;
        let values = wb.worksheet_range(name).map_err(|e| err(&e))?;
        let (vr0, vc0) = values.start().unwrap_or((0, 0));
        for (r, c, v) in values.used_cells() {
            let (row, col) = (vr0 + r as u32, vc0 + c as u32);
            if row >= LAST_ROW || col >= LAST_COLUMN {
                continue;
            }
            write_data(&mut model, &mut styles, sheet, row as i32 + 1, col as i32 + 1, v)?;
        }

        // Formulas (calamine returns them without the leading '='). A panic in calamine's
        // formula decompiler must not lose the values we already have.
        let formulas = match catch_unwind(AssertUnwindSafe(|| wb.worksheet_formula(name))) {
            Ok(Ok(f)) => f,
            _ => continue,
        };
        let (fr0, fc0) = formulas.start().unwrap_or((0, 0));
        for (r, c, f) in formulas.used_cells() {
            if f.is_empty() {
                continue;
            }
            let (row, col) = (fr0 + r as u32, fc0 + c as u32);
            if row >= LAST_ROW || col >= LAST_COLUMN {
                continue;
            }
            let text = if is_ods {
                odf_formula_to_excel(f)
            } else if is_biff {
                fix_biff_formula(f.trim_start_matches('='), kind == Kind::Xls, &names, xti.as_deref())
            } else {
                f.trim_start_matches('=').to_string()
            };
            if text.is_empty() {
                continue;
            }
            let cached = values.get_value((row, col)).cloned().unwrap_or(Data::Empty);
            let (row, col) = (row as i32 + 1, col as i32 + 1);
            // calamine's 3D-reference decoding for xls/xlsb is unreliable: check those against
            // the cached result.
            let verify = is_biff && text.contains('!');
            if model.set_user_input(sheet, row, col, format!("={text}")).is_ok() {
                formula_cells.push(FormulaCell { sheet, row, col, cached, verify });
            }
        }
    }

    model.set_language(language)?;
    model.set_locale(locale)?; // also evaluates

    // Formulas IronCalc cannot handle (unsupported functions, syntax it does not parse, ...)
    // evaluate to an error. When the file carried a non-error cached result, show that instead.
    let mut repaired = false;
    for fc in formula_cells {
        let FormulaCell { sheet, row, col, cached, verify } = fc;
        // No usable cached result (some writers store none, or an empty string).
        if matches!(&cached, Data::Empty | Data::Error(_)) || matches!(&cached, Data::String(t) if t.is_empty()) {
            continue;
        }
        let is_error = matches!(model.get_cell_type(sheet, row, col), Ok(CellType::ErrorValue));
        let mismatch = verify && !same_value(&model.get_cell_value_by_index(sheet, row, col), &cached);
        if is_error || mismatch {
            let _ = model.workbook.worksheet_mut(sheet).map(|ws| ws.cell_clear_contents(row, col));
            write_data(&mut model, &mut styles, sheet, row, col, &cached)?;
            repaired = true;
        }
    }
    if repaired {
        model.evaluate();
    }
    Ok(model)
}

struct FormulaCell {
    sheet: u32,
    row: i32,
    col: i32,
    cached: Data,
    verify: bool,
}

fn same_value(v: &Result<ironcalc::base::cell::CellValue, String>, cached: &Data) -> bool {
    use ironcalc::base::cell::CellValue;
    let close = |a: f64, b: f64| (a - b).abs() <= 1e-9 * a.abs().max(b.abs()).max(1.0);
    match (v, cached) {
        (Ok(CellValue::Number(a)), Data::Float(b)) => close(*a, *b),
        (Ok(CellValue::Number(a)), Data::Int(b)) => close(*a, *b as f64),
        (Ok(CellValue::Number(a)), Data::DateTime(b)) => close(*a, b.as_f64()),
        (Ok(CellValue::String(a)), Data::String(b)) => a == b,
        (Ok(CellValue::Boolean(a)), Data::Bool(b)) => a == b,
        _ => false,
    }
}

// ---------- BIFF (xls / xlsb) formula fix-ups ----------

fn col_to_index(letters: &str) -> u32 {
    letters.bytes().fold(0u32, |acc, b| acc * 26 + (b.to_ascii_uppercase() - b'A' + 1) as u32) - 1
}

fn index_to_col(mut idx: u32) -> String {
    let mut out = Vec::new();
    idx += 1;
    while idx > 0 {
        let r = (idx - 1) % 26;
        out.push(b'A' + r as u8);
        idx = (idx - 1) / 26;
    }
    out.reverse();
    String::from_utf8(out).unwrap_or_default()
}

/// Parses `$?LETTERS$?DIGITS` at the start of `s`.
/// Returns (col_abs, col_index, row_abs, row_text, byte_len).
fn parse_a1(s: &str) -> Option<(bool, u32, bool, &str, usize)> {
    let b = s.as_bytes();
    let mut i = 0;
    let col_abs = b.first() == Some(&b'$');
    if col_abs {
        i += 1;
    }
    let cs = i;
    while i < b.len() && b[i].is_ascii_uppercase() {
        i += 1;
    }
    if i == cs || i - cs > 4 {
        return None;
    }
    let col = col_to_index(&s[cs..i]);
    let row_abs = b.get(i) == Some(&b'$');
    if row_abs {
        i += 1;
    }
    let rs = i;
    while i < b.len() && b[i].is_ascii_digit() {
        i += 1;
    }
    if i == rs {
        return None;
    }
    Some((col_abs, col, row_abs, &s[rs..i], i))
}

/// Repairs cross-sheet references produced by calamine's BIFF formula decompiler:
/// * PtgArea3d (xls/xlsb) and PtgRef3d (xlsb) keep the relative-reference flags in bits 14/15
///   of the column, giving columns past XFD: mask them off and restore relative-ness;
/// * PtgRef3d (xls) shifts the column left by two bits (`col << 2`), with garbage `$` markers;
/// * PtgArea3d (xls) names the sheet at position `ixti` instead of resolving `ixti` through the
///   EXTERNSHEET table: `xti` (ixti -> sheet index, read by [`xls_extern_sheets`]) fixes that;
/// * sheet names that need quoting ("My Sheet!A1") are quoted.
pub(crate) fn fix_biff_formula(f: &str, is_xls: bool, sheet_names: &[String], xti: Option<&[i16]>) -> String {
    let mut out = String::with_capacity(f.len() + 8);
    let mut i = 0;
    let bytes = f.as_bytes();
    while i < f.len() {
        let ch = bytes[i];
        if ch == b'"' {
            // copy string literal
            let start = i;
            i += 1;
            while i < f.len() {
                if bytes[i] == b'"' {
                    if bytes.get(i + 1) == Some(&b'"') {
                        i += 2;
                        continue;
                    }
                    break;
                }
                i += 1;
            }
            i = (i + 1).min(f.len());
            out.push_str(&f[start..i]);
            continue;
        }
        if ch != b'!' {
            let len = f[i..].chars().next().map(|c| c.len_utf8()).unwrap_or(1);
            out.push_str(&f[i..i + len]);
            i += len;
            continue;
        }
        // '!': which sheet name precedes it (calamine writes names unquoted)?
        let sheet_idx = if out.ends_with('\'') {
            None
        } else {
            sheet_names
                .iter()
                .enumerate()
                .filter(|(_, n)| out.ends_with(n.as_str()))
                .max_by_key(|(_, n)| n.len())
                .map(|(k, _)| k)
        };
        i += 1;
        let rest = &f[i..];
        let parsed = parse_a1(rest);
        let area2 = parsed.and_then(|(_, _, _, _, len)| rest[len..].strip_prefix(':').and_then(parse_a1));

        if let Some(k) = sheet_idx {
            let mut target = k;
            if is_xls && area2.is_some() {
                if let Some(t) = xti.and_then(|x| x.get(k)).filter(|t| **t >= 0) {
                    target = *t as usize;
                }
            }
            let name = sheet_names.get(target).unwrap_or(&sheet_names[k]);
            out.truncate(out.len() - sheet_names[k].len());
            let needs_quotes = !name.chars().all(|c| c.is_alphanumeric() || c == '_' || c == '.')
                || name.starts_with(|c: char| c.is_ascii_digit());
            if needs_quotes {
                out.push('\'');
                out.push_str(&name.replace('\'', "''"));
                out.push('\'');
            } else {
                out.push_str(name);
            }
        }
        out.push('!');

        let Some((ca, col, ra, row, len)) = parsed else { continue };
        let fix = |col_abs: bool, col: u32, row_abs: bool, row: &str| -> String {
            if col >= 0x4000 {
                // flags in the column: bit 14 = column relative, bit 15 = row relative
                let rel_col = col & 0x4000 != 0;
                let rel_row = col & 0x8000 != 0;
                format!(
                    "{}{}{}{}",
                    if rel_col { "" } else { "$" },
                    index_to_col(col & 0x3FFF),
                    if rel_row { "" } else { "$" },
                    row
                )
            } else {
                format!("{}{}{}{}", if col_abs { "$" } else { "" }, index_to_col(col), if row_abs { "$" } else { "" }, row)
            }
        };
        match area2 {
            Some((ca2, col2, ra2, row2, len2)) => {
                out.push_str(&fix(ca, col, ra, row));
                out.push(':');
                out.push_str(&fix(ca2, col2, ra2, row2));
                i += len + 1 + len2;
            }
            None if is_xls => {
                // xls PtgRef3d: column was shifted left by 2; '$' markers are meaningless.
                if col % 4 == 0 {
                    out.push_str(&format!("{}{}", index_to_col(col / 4), row));
                } else {
                    out.push_str(&rest[..len]);
                }
                i += len;
            }
            None => {
                out.push_str(&fix(ca, col, ra, row));
                i += len;
            }
        }
    }
    out
}

/// Reads the BIFF8 EXTERNSHEET table of an .xls file: for each XTI index, the sheet index it
/// points to (-1/-2 for external or deleted references). None if unavailable.
pub(crate) fn xls_extern_sheets(path: &str) -> Option<Vec<i16>> {
    let mut comp = cfb::open(path).ok()?;
    let mut stream = comp
        .open_stream("/Workbook")
        .or_else(|_| comp.open_stream("/Book"))
        .ok()?;
    let mut data = Vec::new();
    stream.read_to_end(&mut data).ok()?;
    let rd = |b: &[u8], at: usize| -> Option<u16> { Some(u16::from_le_bytes([*b.get(at)?, *b.get(at + 1)?])) };

    let mut pos = 0;
    let mut payload: Option<Vec<u8>> = None;
    let mut first = true;
    while pos + 4 <= data.len() {
        let typ = rd(&data, pos)?;
        let len = rd(&data, pos + 2)? as usize;
        let body = data.get(pos + 4..pos + 4 + len)?;
        pos += 4 + len;
        if first {
            // BOF: only BIFF8 (version 0x0600) has an XTI table
            if typ != 0x0809 || rd(body, 0)? != 0x0600 {
                return None;
            }
            first = false;
            continue;
        }
        match typ {
            0x0017 if payload.is_none() => payload = Some(body.to_vec()),
            0x003C => {
                if let Some(p) = payload.as_mut() {
                    if p.len() < 2 + 6 * rd(p, 0)? as usize {
                        p.extend_from_slice(body); // CONTINUE of a long EXTERNSHEET
                    }
                }
            }
            0x000A => break, // end of the workbook globals
            _ => {
                if let Some(p) = &payload {
                    if p.len() >= 2 + 6 * rd(p, 0)? as usize {
                        break;
                    }
                }
            }
        }
    }
    let p = payload?;
    let n = rd(&p, 0)? as usize;
    let mut out = Vec::with_capacity(n);
    for k in 0..n {
        let base = 2 + 6 * k;
        out.push(rd(&p, base + 2)? as i16);
    }
    Some(out)
}

fn unique_sheet_name(name: &str, used: &mut HashSet<String>) -> String {
    let invalid = ['\\', '/', '*', '?', ':', '[', ']'];
    let mut base: String = name
        .chars()
        .map(|c| if invalid.contains(&c) { '_' } else { c })
        .take(31)
        .collect();
    if base.trim().is_empty() {
        base = "Sheet".to_string();
    }
    let mut candidate = base.clone();
    let mut i = 2;
    while used.contains(&candidate.to_uppercase()) {
        let suffix = format!(" ({i})");
        let keep = 31usize.saturating_sub(suffix.chars().count());
        candidate = format!("{}{}", base.chars().take(keep).collect::<String>(), suffix);
        i += 1;
    }
    used.insert(candidate.to_uppercase());
    candidate
}

fn write_data(
    model: &mut Model,
    styles: &mut FormatStyles,
    sheet: u32,
    row: i32,
    col: i32,
    v: &Data,
) -> Result<(), String> {
    match v {
        Data::Empty => {}
        Data::Int(i) => {
            model.workbook.worksheet_mut(sheet)?.set_cell_with_number(row, col, *i as f64, 0)?;
        }
        Data::Float(f) => {
            if f.is_finite() {
                model.workbook.worksheet_mut(sheet)?.set_cell_with_number(row, col, *f, 0)?;
            }
        }
        Data::Bool(b) => {
            model.workbook.worksheet_mut(sheet)?.set_cell_with_boolean(row, col, *b, 0)?;
        }
        Data::String(s) => {
            if !s.is_empty() {
                model.update_cell_with_text(sheet, row, col, s)?;
            }
        }
        Data::Error(e) => {
            let err = match e {
                calamine::CellErrorType::Div0 => CalcError::DIV,
                calamine::CellErrorType::NA => CalcError::NA,
                calamine::CellErrorType::Name => CalcError::NAME,
                calamine::CellErrorType::Null => CalcError::NULL,
                calamine::CellErrorType::Num => CalcError::NUM,
                calamine::CellErrorType::Ref => CalcError::REF,
                calamine::CellErrorType::Value => CalcError::VALUE,
                _ => CalcError::ERROR,
            };
            model.workbook.worksheet_mut(sheet)?.set_cell_with_error(row, col, err, 0)?;
        }
        Data::DateTime(dt) => {
            let raw = dt.as_f64();
            let (serial, fmt) = if dt.is_duration() {
                (raw, if raw < 1.0 { FMT_TIME } else { FMT_DURATION })
            } else if raw < 1.0 {
                (raw, FMT_TIME) // time of day only: identical in the 1900 and 1904 systems
            } else {
                // Recompute from components so 1904-based workbooks land on the right day.
                let (y, mo, d, h, mi, s, ms) = dt.to_ymd_hms_milli();
                let day = excel_serial_from_ymd(y as i64, mo as u32, d as u32);
                let secs = h as f64 * 3600.0 + mi as f64 * 60.0 + s as f64 + ms as f64 / 1000.0;
                let fmt = if secs == 0.0 { FMT_DATE } else { FMT_DATETIME };
                (day + secs / 86400.0, fmt)
            };
            let st = styles.get(model, fmt);
            model.workbook.worksheet_mut(sheet)?.set_cell_with_number(row, col, serial, st)?;
        }
        Data::DateTimeIso(s) => match parse_iso_datetime(s) {
            Some((serial, has_time)) => {
                let st = styles.get(model, if has_time { FMT_DATETIME } else { FMT_DATE });
                model.workbook.worksheet_mut(sheet)?.set_cell_with_number(row, col, serial, st)?;
            }
            None => model.update_cell_with_text(sheet, row, col, s)?,
        },
        Data::DurationIso(s) => match parse_iso_duration(s) {
            Some(days) => {
                let st = styles.get(model, if days < 1.0 { FMT_TIME } else { FMT_DURATION });
                model.workbook.worksheet_mut(sheet)?.set_cell_with_number(row, col, days, st)?;
            }
            None => model.update_cell_with_text(sheet, row, col, s)?,
        },
    }
    Ok(())
}

// ---------- dates ----------

/// Days since 1970-01-01 of a proleptic Gregorian date (H. Hinnant's algorithm).
fn days_from_civil(y: i64, m: u32, d: u32) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let m = m as i64;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d as i64 - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

/// Excel (1900 system) serial number of a date, including Excel's fictitious 1900-02-29.
fn excel_serial_from_ymd(y: i64, m: u32, d: u32) -> f64 {
    if (y, m, d) == (1900, 2, 29) {
        return 60.0;
    }
    let serial = days_from_civil(y, m, d) - days_from_civil(1899, 12, 30);
    (if serial < 61 { serial - 1 } else { serial }) as f64
}

/// "2024-01-15" or "2024-01-15T10:30:00[.fff][Z]" -> (serial, has_time)
fn parse_iso_datetime(s: &str) -> Option<(f64, bool)> {
    let s = s.trim().trim_end_matches('Z');
    let (date, time) = match s.split_once(['T', ' ']) {
        Some((d, t)) => (d, Some(t)),
        None => (s, None),
    };
    let mut it = date.split('-');
    let y: i64 = it.next()?.parse().ok()?;
    let m: u32 = it.next()?.parse().ok()?;
    let d: u32 = it.next()?.parse().ok()?;
    if it.next().is_some() || !(1..=12).contains(&m) || !(1..=31).contains(&d) {
        return None;
    }
    let mut serial = excel_serial_from_ymd(y, m, d);
    let mut has_time = false;
    if let Some(t) = time {
        let mut parts = t.split(':');
        let h: f64 = parts.next()?.parse().ok()?;
        let mi: f64 = parts.next().unwrap_or("0").parse().ok()?;
        let sec: f64 = parts.next().unwrap_or("0").parse().ok()?;
        let secs = h * 3600.0 + mi * 60.0 + sec;
        has_time = secs != 0.0;
        serial += secs / 86400.0;
    }
    Some((serial, has_time))
}

/// ISO 8601 duration ("PT12H30M00S", "P1DT2H") -> days.
fn parse_iso_duration(s: &str) -> Option<f64> {
    let s = s.trim();
    let (neg, s) = match s.strip_prefix('-') {
        Some(r) => (true, r),
        None => (false, s),
    };
    let s = s.strip_prefix('P')?;
    let mut days = 0.0;
    let mut in_time = false;
    let mut num = String::new();
    for ch in s.chars() {
        match ch {
            'T' => in_time = true,
            '0'..='9' | '.' | ',' => num.push(if ch == ',' { '.' } else { ch }),
            _ => {
                let v: f64 = num.parse().ok()?;
                num.clear();
                days += match (ch, in_time) {
                    ('Y', false) => v * 365.0,
                    ('M', false) => v * 30.0,
                    ('W', false) => v * 7.0,
                    ('D', false) => v,
                    ('H', true) => v / 24.0,
                    ('M', true) => v / 1440.0,
                    ('S', true) => v / 86400.0,
                    _ => return None,
                };
            }
        }
    }
    if !num.is_empty() {
        return None;
    }
    Some(if neg { -days } else { days })
}

// ---------- OpenFormula (ODS) -> Excel syntax ----------

/// Converts an ODF formula such as `of:=SUM([.A1:.B2];['Other Sheet'.C3])`
/// to Excel syntax (`SUM(A1:B2,'Other Sheet'!C3)`), without the leading '='.
pub(crate) fn odf_formula_to_excel(f: &str) -> String {
    let mut s = f.trim();
    for prefix in ["of:", "oooc:", "msoxl:"] {
        if let Some(r) = s.strip_prefix(prefix) {
            s = r;
            break;
        }
    }
    let s = s.strip_prefix('=').unwrap_or(s);
    let chars: Vec<char> = s.chars().collect();
    let mut out = String::with_capacity(s.len());
    let mut i = 0;
    let mut brace_depth = 0;
    while i < chars.len() {
        let ch = chars[i];
        match ch {
            '"' => {
                // string literal, "" escapes
                out.push(ch);
                i += 1;
                while i < chars.len() {
                    out.push(chars[i]);
                    if chars[i] == '"' {
                        if i + 1 < chars.len() && chars[i + 1] == '"' {
                            out.push('"');
                            i += 2;
                            continue;
                        }
                        break;
                    }
                    i += 1;
                }
                i += 1;
            }
            '[' => {
                let mut j = i + 1;
                let mut in_quote = false;
                while j < chars.len() {
                    match chars[j] {
                        '\'' => in_quote = !in_quote,
                        ']' if !in_quote => break,
                        _ => {}
                    }
                    j += 1;
                }
                let inner: String = chars[i + 1..j.min(chars.len())].iter().collect();
                out.push_str(&odf_reference(&inner));
                i = j + 1;
            }
            '{' => {
                brace_depth += 1;
                out.push(ch);
                i += 1;
            }
            '}' => {
                brace_depth -= 1;
                out.push(ch);
                i += 1;
            }
            ';' => {
                out.push(',');
                i += 1;
            }
            '|' if brace_depth > 0 => {
                out.push(';');
                i += 1;
            }
            '~' => {
                out.push(',');
                i += 1;
            }
            _ => {
                out.push(ch);
                i += 1;
            }
        }
    }
    out
}

fn odf_reference(inner: &str) -> String {
    // split on ':' outside quotes
    let mut parts = Vec::new();
    let mut cur = String::new();
    let mut in_quote = false;
    for ch in inner.chars() {
        match ch {
            '\'' => {
                in_quote = !in_quote;
                cur.push(ch);
            }
            ':' if !in_quote => parts.push(std::mem::take(&mut cur)),
            _ => cur.push(ch),
        }
    }
    parts.push(cur);

    let mut out = String::new();
    let mut first_sheet: Option<String> = None;
    for (k, part) in parts.iter().enumerate() {
        // last '.' outside quotes separates sheet from cell
        let mut split_at = None;
        let mut q = false;
        for (idx, ch) in part.char_indices() {
            match ch {
                '\'' => q = !q,
                '.' if !q => split_at = Some(idx),
                _ => {}
            }
        }
        let (sheet, cell) = match split_at {
            Some(idx) => (&part[..idx], &part[idx + 1..]),
            None => ("", part.as_str()),
        };
        let sheet = sheet.trim_start_matches('$');
        let sheet = if sheet.is_empty() {
            None
        } else if sheet.starts_with('\'')
            || (sheet.chars().all(|c| c.is_alphanumeric() || c == '_') && !sheet.starts_with(|c: char| c.is_ascii_digit()))
        {
            Some(sheet.to_string())
        } else {
            Some(format!("'{}'", sheet.replace('\'', "''")))
        };
        if cell.contains("#REF!") {
            return "#REF!".to_string();
        }
        if k > 0 {
            out.push(':');
        }
        match (&sheet, k) {
            (Some(s), 0) => {
                out.push_str(s);
                out.push('!');
                first_sheet = Some(s.clone());
            }
            (Some(s), _) if Some(s) != first_sheet.as_ref() => {
                out.push_str(s);
                out.push('!');
            }
            _ => {}
        }
        out.push_str(cell);
    }
    out
}

// =====================================================================
// CSV / TSV / TXT
// =====================================================================

fn open_text(path: &str, ext: &str) -> Result<Model<'static>, String> {
    let bytes = std::fs::read(path).map_err(|e| format!("cannot read file: {e}"))?;
    let text = decode_text(&bytes);
    let delimiter = detect_delimiter(&text, ext);
    let (locale, language, tz) = settings();
    // Use the app's locale, so dates and the like are read the way the user writes them;
    // plain numbers are parsed here with the file's own convention and set directly.
    let mut model = Model::new_empty("Workbook", locale, tz, language)?;
    load_csv_text(&mut model, 0, &text, delimiter)?;
    model.evaluate();
    Ok(model)
}

/// UTF-8 (with/without BOM), UTF-16 LE/BE (BOM, or BOM-less LE/BE by zero-byte pattern), else Windows-1252.
pub(crate) fn decode_text(bytes: &[u8]) -> String {
    if let Some((enc, bom_len)) = encoding_rs::Encoding::for_bom(bytes) {
        let (s, _) = enc.decode_without_bom_handling(&bytes[bom_len..]);
        return s.into_owned();
    }
    if let Ok(s) = std::str::from_utf8(bytes) {
        return s.to_string();
    }
    // BOM-less UTF-16: lots of NUL bytes in odd (LE) or even (BE) positions.
    let sample = &bytes[..bytes.len().min(4096)];
    if sample.len() >= 4 {
        let half = sample.len() / 2;
        let odd_zero = sample.iter().skip(1).step_by(2).filter(|b| **b == 0).count();
        let even_zero = sample.iter().step_by(2).filter(|b| **b == 0).count();
        if odd_zero * 10 > half * 3 && even_zero * 10 < half {
            return encoding_rs::UTF_16LE.decode_without_bom_handling(bytes).0.into_owned();
        }
        if even_zero * 10 > half * 3 && odd_zero * 10 < half {
            return encoding_rs::UTF_16BE.decode_without_bom_handling(bytes).0.into_owned();
        }
    }
    encoding_rs::WINDOWS_1252.decode_without_bom_handling(bytes).0.into_owned()
}

/// Picks the delimiter whose per-record count (outside quotes) is the most consistent
/// over the first records.
pub(crate) fn detect_delimiter(text: &str, ext: &str) -> u8 {
    const CANDIDATES: [u8; 4] = *b",;\t|";
    const MAX_RECORDS: usize = 50;
    let mut counts: Vec<[usize; 4]> = Vec::new();
    let mut cur = [0usize; 4];
    let mut in_quotes = false;
    let mut nonempty = false;
    for &b in text.as_bytes().iter().take(256 * 1024) {
        if b == b'"' {
            in_quotes = !in_quotes;
            nonempty = true;
            continue;
        }
        if in_quotes {
            continue;
        }
        if b == b'\n' {
            if nonempty {
                counts.push(cur);
            }
            cur = [0; 4];
            nonempty = false;
            if counts.len() >= MAX_RECORDS {
                break;
            }
            continue;
        }
        if b != b'\r' {
            nonempty = true;
        }
        if let Some(k) = CANDIDATES.iter().position(|c| *c == b) {
            cur[k] += 1;
        }
    }
    if nonempty && counts.len() < MAX_RECORDS {
        counts.push(cur);
    }

    let default = if ext == "tsv" || ext == "tab" { b'\t' } else { b',' };
    if counts.is_empty() {
        return default;
    }
    // score = (records matching the modal count, modal count); prefer the extension's default on ties
    let mut best: Option<(usize, usize, u8)> = None;
    for (k, &cand) in CANDIDATES.iter().enumerate() {
        let mut freq: HashMap<usize, usize> = HashMap::new();
        for c in &counts {
            if c[k] > 0 {
                *freq.entry(c[k]).or_default() += 1;
            }
        }
        let Some((&mode, &matches)) = freq.iter().max_by_key(|(n, f)| (**f, **n)) else { continue };
        let better = match best {
            None => true,
            Some((bm, bmode, bc)) => {
                (matches, mode) > (bm, bmode) || ((matches, mode) == (bm, bmode) && cand == default && bc != default)
            }
        };
        if better {
            best = Some((matches, mode, cand));
        }
    }
    best.map(|b| b.2).unwrap_or(default)
}

/// Parses a plain number written with the file's convention (`decimal_comma`: "1.234,56",
/// otherwise "1,234.56"), with optional sign, exponent (dot convention only) and '%'.
/// Returns (value, is_percent, decimals). Thousands groups must be well formed.
pub(crate) fn parse_file_number(s: &str, decimal_comma: bool) -> Option<(f64, bool, usize)> {
    let (dec, group) = if decimal_comma { (',', '.') } else { ('.', ',') };
    let s = s.trim();
    let (neg, rest) = match s.as_bytes().first() {
        Some(b'-') => (true, &s[1..]),
        Some(b'+') => (false, &s[1..]),
        _ => (false, s),
    };
    let (body, pct) = match rest.strip_suffix('%') {
        Some(b) => (b.trim_end(), true),
        None => (rest, false),
    };
    // exponent (only meaningful without grouping)
    let (mant, exp) = match body.find(['e', 'E']) {
        Some(k) if !decimal_comma => {
            let e = &body[k + 1..];
            let digits = e.strip_prefix(['+', '-']).unwrap_or(e);
            if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
                return None;
            }
            (&body[..k], Some(e))
        }
        _ => (body, None),
    };
    let (int_part, frac) = match mant.split_once(dec) {
        Some((i, f)) => (i, Some(f)),
        None => (mant, None),
    };
    if let Some(f) = frac {
        if !f.bytes().all(|b| b.is_ascii_digit()) || (f.is_empty() && int_part.is_empty()) {
            return None;
        }
    }
    if int_part.is_empty() && frac.is_none() {
        return None;
    }
    let groups: Vec<&str> = int_part.split(group).collect();
    if !groups.iter().all(|g| g.bytes().all(|b| b.is_ascii_digit())) {
        return None;
    }
    if groups.len() > 1
        && (exp.is_some() || groups[0].is_empty() || groups[0].len() > 3 || groups[1..].iter().any(|g| g.len() != 3))
    {
        return None;
    }
    let mut norm = String::with_capacity(s.len());
    if neg {
        norm.push('-');
    }
    norm.push_str(&groups.concat());
    if norm.is_empty() || norm == "-" {
        norm.push('0');
    }
    let decimals = frac.map(|f| f.len()).unwrap_or(0);
    if let Some(f) = frac {
        norm.push('.');
        norm.push_str(f);
    }
    if let Some(e) = exp {
        norm.push('e');
        norm.push_str(e);
    }
    let v: f64 = norm.parse().ok()?;
    if !v.is_finite() {
        return None;
    }
    Some((if pct { v / 100.0 } else { v }, pct, decimals))
}

/// Characters of a "number-like" field: one that must not reach the locale-dependent parser
/// when it is not a valid number in the file's convention (e.g. "1,5" in a US file).
fn looks_numeric(s: &str) -> bool {
    let s = s.trim();
    s.bytes().any(|b| b.is_ascii_digit())
        && s.bytes().all(|b| b.is_ascii_digit() || matches!(b, b'.' | b',' | b'-' | b'+' | b'%' | b' '))
}

/// Decides whether the file writes decimals with a comma, from its numeric fields.
/// ',' files: never. ';' files: comma unless only unambiguous dot decimals are found.
/// Tab/pipe files: dot unless only decimal commas are found.
fn file_uses_decimal_comma(text: &str, delimiter: u8) -> bool {
    if delimiter == b',' {
        return false;
    }
    let mut comma_evidence = false;
    let mut dot_evidence = false;
    let mut rdr = csv::ReaderBuilder::new()
        .delimiter(delimiter)
        .has_headers(false)
        .flexible(true)
        .from_reader(text.as_bytes());
    for rec in rdr.records().take(5000).flatten() {
        for f in rec.iter() {
            let f = f.trim();
            if !looks_numeric(f) {
                continue;
            }
            let has_comma = f.contains(',');
            let has_dot = f.contains('.');
            if has_comma && parse_file_number(f, true).is_some() {
                comma_evidence = true;
            }
            if has_dot && parse_file_number(f, false).is_some() {
                // "1.234" could be a thousands group; anything else is a dot decimal
                let frac = f.trim_end_matches('%').rsplit('.').next().unwrap_or("");
                let int = f.trim_start_matches(['-', '+']).split('.').next().unwrap_or("");
                let unambiguous = has_comma || frac.len() != 3 || int.len() > 3 || f.matches('.').count() > 1;
                if unambiguous && (!has_comma || parse_file_number(f, true).is_none()) {
                    dot_evidence = true;
                }
            }
        }
        if comma_evidence && dot_evidence {
            break;
        }
    }
    match (comma_evidence, dot_evidence) {
        (true, false) => true,
        (false, true) => false,
        _ => delimiter == b';',
    }
}

pub(crate) fn load_csv_text(model: &mut Model, sheet: u32, text: &str, delimiter: u8) -> Result<(), String> {
    let decimal_comma = file_uses_decimal_comma(text, delimiter);
    let mut styles = FormatStyles { cache: HashMap::new() };
    let mut rdr = csv::ReaderBuilder::new()
        .delimiter(delimiter)
        .has_headers(false)
        .flexible(true)
        .from_reader(text.as_bytes());
    let mut record = csv::StringRecord::new();
    let mut row: i32 = 0;
    loop {
        match rdr.read_record(&mut record) {
            Ok(true) => {}
            Ok(false) => break,
            Err(e) => return Err(format!("CSV parse error: {e}")),
        }
        row += 1;
        if row as u32 > LAST_ROW {
            break;
        }
        for (ci, field) in record.iter().enumerate() {
            if field.is_empty() || ci as u32 >= LAST_COLUMN {
                continue;
            }
            let col = ci as i32 + 1;
            set_csv_value(model, &mut styles, sheet, row, col, field, decimal_comma)?;
        }
    }
    Ok(())
}

fn set_csv_value(
    model: &mut Model,
    styles: &mut FormatStyles,
    sheet: u32,
    row: i32,
    col: i32,
    field: &str,
    decimal_comma: bool,
) -> Result<(), String> {
    // Never evaluate formulas coming from a text file: keep them as literal text.
    if field.starts_with(['=', '\'']) {
        return model.update_cell_with_text(sheet, row, col, field);
    }
    // Plain numbers: parsed with the file's convention, stored without going through the
    // locale-dependent input parser.
    if let Some((v, pct, decimals)) = parse_file_number(field, decimal_comma) {
        let style = if pct { styles.get(model, if decimals == 0 { "0%" } else { "0.00%" }) } else { 0 };
        return model.workbook.worksheet_mut(sheet)?.set_cell_with_number(row, col, v, style);
    }
    if looks_numeric(field) {
        // e.g. "1,5" in a US file or "1,5,6": not a number in this file, keep it verbatim
        return model.update_cell_with_text(sheet, row, col, field);
    }
    // Dates, currencies, booleans, text: like typing it in the app's locale.
    model.set_user_input(sheet, row, col, field.to_string())?;
    // IronCalc also treats "+..." / "-..." non-numbers as formulas: undo that.
    if field.starts_with(['+', '-']) {
        let is_formula = model
            .workbook
            .worksheet(sheet)?
            .cell(row, col)
            .map(|c| c.has_formula())
            .unwrap_or(false);
        if is_formula {
            let ws = model.workbook.worksheet_mut(sheet)?;
            ws.cell_clear_contents(row, col)?;
            ws.set_cell_style(row, col, 0)?;
            model.update_cell_with_text(sheet, row, col, field)?;
        }
    }
    Ok(())
}

// ---------- CSV export ----------

fn save_csv(model: &Model, sheet: u32, path: &str, delimiter: u8) -> Result<(), String> {
    let ws = model.workbook.worksheet(sheet)?;
    // Formatted, non-empty values by row.
    let mut rows: Vec<(i32, Vec<(i32, String)>)> = Vec::new();
    let mut max_col = 0;
    for row in ws.sheet_data.rows() {
        let mut cells = Vec::new();
        for col in ws.sheet_data.columns_in_row(row) {
            let v = model.get_formatted_cell_value(sheet, row, col)?;
            if !v.is_empty() {
                max_col = max_col.max(col);
                cells.push((col, v));
            }
        }
        if !cells.is_empty() {
            rows.push((row, cells));
        }
    }

    let mut out: Vec<u8> = Vec::with_capacity(rows.len() * 32 + 3);
    // UTF-8 BOM: without it Excel (especially on Mac) reads accented text as Mac Roman.
    out.extend_from_slice(&[0xEF, 0xBB, 0xBF]);
    let d = delimiter as char;
    let mut next_row = 1;
    for (row, cells) in rows {
        while next_row < row {
            write_empty_row(&mut out, max_col, d);
            next_row += 1;
        }
        let mut col = 1;
        for (c, v) in cells {
            while col < c {
                out.push(delimiter);
                col += 1;
            }
            write_field(&mut out, &v, d);
            if c < max_col {
                out.push(delimiter);
            }
            col = c + 1;
        }
        while col < max_col {
            out.push(delimiter);
            col += 1;
        }
        out.extend_from_slice(b"\r\n");
        next_row = row + 1;
    }

    // Write to a temp file and atomically replace.
    let tmp = format!("{path}.foglio-tmp");
    let write = || -> std::io::Result<()> {
        let mut f = File::create(&tmp)?;
        f.write_all(&out)?;
        f.sync_all()?;
        std::fs::rename(&tmp, path)
    };
    write().map_err(|e| {
        let _ = std::fs::remove_file(&tmp);
        format!("cannot write file: {e}")
    })
}

fn write_empty_row(out: &mut Vec<u8>, max_col: i32, d: char) {
    for _ in 1..max_col {
        out.push(d as u8);
    }
    out.extend_from_slice(b"\r\n");
}

fn write_field(out: &mut Vec<u8>, v: &str, d: char) {
    if v.contains([d, '"', '\r', '\n']) {
        out.push(b'"');
        out.extend_from_slice(v.replace('"', "\"\"").as_bytes());
        out.push(b'"');
    } else {
        out.extend_from_slice(v.as_bytes());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn file_numbers() {
        let p = |s, c| parse_file_number(s, c).map(|(v, pct, _)| (v, pct));
        assert_eq!(p("3,5", true), Some((3.5, false)));
        assert_eq!(p("1.234,56", true), Some((1234.56, false)));
        assert_eq!(p("-12,5%", true), Some((-0.125, true)));
        assert_eq!(p("1.234.567", true), Some((1234567.0, false)));
        assert_eq!(p("1.234", true), Some((1234.0, false)));
        assert_eq!(p("1,5,6", true), None);
        assert_eq!(p("abc,def", true), None);
        assert_eq!(p("12.34,5", true), None);
        assert_eq!(p("007", true), Some((7.0, false)));
        assert_eq!(p("1,234.5", false), Some((1234.5, false)));
        assert_eq!(p("1.5e3", false), Some((1500.0, false)));
        assert_eq!(p(".5", false), Some((0.5, false)));
        assert_eq!(p("1,5", false), None);
        assert_eq!(p("-", false), None);
        assert_eq!(p("1 000", false), None);
        assert!(looks_numeric("1,5") && !looks_numeric("1/2/2024") && !looks_numeric("abc"));
    }

    #[test]
    fn decimal_convention() {
        assert!(file_uses_decimal_comma("a;b\n3,5;1.234\n", b';'));
        assert!(!file_uses_decimal_comma("a;b\n3.5;2.25\n", b';'));
        assert!(file_uses_decimal_comma("a;b\n1.000;2\n", b';'));
        assert!(!file_uses_decimal_comma("a\tb\n3.5\t1\n", b'\t'));
        assert!(file_uses_decimal_comma("a\tb\n3,5\t1\n", b'\t'));
        assert!(!file_uses_decimal_comma("a,b\n\"3,5\",1\n", b','));
    }

    #[test]
    fn odf_formulas() {
        assert_eq!(odf_formula_to_excel("of:=SUM([.B2:.B3])"), "SUM(B2:B3)");
        assert_eq!(odf_formula_to_excel("of:=IF([.B4]>1;[.B4]*2;0)"), "IF(B4>1,B4*2,0)");
        assert_eq!(odf_formula_to_excel("of:=[$Data.B4]*2"), "Data!B4*2");
        assert_eq!(odf_formula_to_excel("of:=['My Sheet'.A1]&\"a;b\""), "'My Sheet'!A1&\"a;b\"");
        assert_eq!(odf_formula_to_excel("of:=SUM([Data.A1:Data.B2])"), "SUM(Data!A1:B2)");
        assert_eq!(odf_formula_to_excel("of:={1;2|3;4}"), "{1,2;3,4}");
    }

    #[test]
    fn biff_fixups() {
        let names = vec!["Data".to_string(), "My Sheet".to_string()];
        // xls PtgRef3d: B4 relative was rendered as E$4
        assert_eq!(fix_biff_formula("Data!E$4*2", true, &names, None), "Data!B4*2");
        // relative-flagged area columns past XFD
        let c = index_to_col(0xC000 | 1);
        let f = format!("SUM(Data!${c}$2:${c}$3)");
        assert_eq!(fix_biff_formula(&f, true, &names, None), "SUM(Data!B2:B3)");
        assert_eq!(fix_biff_formula("SUM(Data!$B$2:$B$3)", true, &names, None), "SUM(Data!$B$2:$B$3)");
        assert_eq!(fix_biff_formula("My Sheet!$A$1+\"x!y\"", false, &names, None), "'My Sheet'!$A$1+\"x!y\"");
        // xls PtgArea3d names sheets[ixti]; XTI 0 -> sheet 1 ("My Sheet")
        assert_eq!(fix_biff_formula("SUM(Data!$A$1:$A$2)", true, &names, Some(&[1, 0])), "SUM('My Sheet'!$A$1:$A$2)");
        assert_eq!(index_to_col(0), "A");
        assert_eq!(index_to_col(16383), "XFD");
        assert_eq!(col_to_index("XFD"), 16383);
    }

    #[test]
    fn serials() {
        assert_eq!(excel_serial_from_ymd(1900, 1, 1), 1.0);
        assert_eq!(excel_serial_from_ymd(1900, 2, 28), 59.0);
        assert_eq!(excel_serial_from_ymd(1900, 3, 1), 61.0);
        assert_eq!(excel_serial_from_ymd(2024, 1, 15), 45306.0);
        assert_eq!(parse_iso_datetime("2024-01-15T12:00:00"), Some((45306.5, true)));
        assert_eq!(parse_iso_duration("PT12H00M00S"), Some(0.5));
    }

    #[test]
    fn delimiters() {
        assert_eq!(detect_delimiter("a,b,c\n1,2,3\n", "csv"), b',');
        assert_eq!(detect_delimiter("a;b;c\n1,5;2;3\n", "csv"), b';');
        assert_eq!(detect_delimiter("a\tb\n\"x,y\"\t2\n", "txt"), b'\t');
        assert_eq!(detect_delimiter("a|b|c\n1|2|3\n", "txt"), b'|');
        assert_eq!(detect_delimiter("single\n", "tsv"), b'\t');
    }
}
