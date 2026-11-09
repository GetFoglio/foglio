//! Integration tests for the file import/export C ABI (src/io.rs).
//! Run `cargo test --release -- --nocapture` to see the load-time measurements.

use std::ffi::{c_char, CStr, CString};
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::RwLock;
use std::time::Instant;

use foglio_core::io::{foglio_open_any, foglio_save_csv, foglio_supported_extensions};
use foglio_core::{
    foglio_free, foglio_set_locale, foglio_get_formatted, foglio_get_input, foglio_set_input, foglio_sheet_count, foglio_sheet_name,
    foglio_string_free, FoglioBook,
};

// ---------- helpers ----------

/// The locale is process-wide: ordinary opens share the lock, the locale test takes it exclusively.
static LOCALE_LOCK: RwLock<()> = RwLock::new(());

fn fixture(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures").join(name)
}

fn tmp_dir() -> PathBuf {
    let d = std::env::temp_dir().join(format!("foglio-io-tests-{}", std::process::id()));
    std::fs::create_dir_all(&d).unwrap();
    d
}

fn take(s: *mut c_char) -> String {
    assert!(!s.is_null());
    let out = unsafe { CStr::from_ptr(s) }.to_str().unwrap().to_string();
    unsafe { foglio_string_free(s) };
    out
}

struct Book(*mut FoglioBook);

impl Drop for Book {
    fn drop(&mut self) {
        unsafe { foglio_free(self.0) };
    }
}

impl Book {
    fn open(path: &Path) -> Book {
        Self::try_open(path).unwrap_or_else(|e| panic!("open {}: {e}", path.display()))
    }
    fn try_open(path: &Path) -> Result<Book, String> {
        let _g = LOCALE_LOCK.read().unwrap_or_else(|e| e.into_inner());
        Self::try_open_unlocked(path)
    }
    fn try_open_unlocked(path: &Path) -> Result<Book, String> {
        let c = CString::new(path.to_str().unwrap()).unwrap();
        let mut err: *mut c_char = ptr::null_mut();
        let b = unsafe { foglio_open_any(c.as_ptr(), &mut err) };
        if b.is_null() {
            Err(if err.is_null() { "unknown error".into() } else { take(err) })
        } else {
            Ok(Book(b))
        }
    }
    /// Formatted value (what the user sees). Rows/cols 1-based.
    fn val(&self, sheet: u32, row: i32, col: i32) -> String {
        take(foglio_get_formatted(self.0, sheet, row, col))
    }
    fn input(&self, sheet: u32, row: i32, col: i32) -> String {
        take(foglio_get_input(self.0, sheet, row, col))
    }
    fn sheets(&self) -> Vec<String> {
        (0..foglio_sheet_count(self.0)).map(|i| take(foglio_sheet_name(self.0, i))).collect()
    }
    fn save_csv(&self, sheet: u32, path: &Path, delim: u8) {
        let c = CString::new(path.to_str().unwrap()).unwrap();
        let mut err: *mut c_char = ptr::null_mut();
        let rc = unsafe { foglio_save_csv(self.0, sheet, c.as_ptr(), delim, &mut err) };
        assert_eq!(rc, 0, "save_csv failed: {}", if err.is_null() { String::new() } else { take(err) });
    }
}

fn write_xlsx(path: &Path) {
    use rust_xlsxwriter::{ExcelDateTime, Format, Formula, Workbook};
    let mut wb = Workbook::new();
    let ws = wb.add_worksheet().set_name("Data").unwrap();
    ws.write(0, 0, "Name").unwrap();
    ws.write(0, 1, "Value").unwrap();
    ws.write(1, 0, "Alpha").unwrap();
    ws.write(1, 1, 10).unwrap();
    ws.write(2, 0, "Città").unwrap();
    ws.write(2, 1, 2.5).unwrap();
    ws.write(3, 0, "Total").unwrap();
    ws.write_formula(3, 1, Formula::new("=SUM(B2:B3)").set_result("12.5")).unwrap();
    let date_fmt = Format::new().set_num_format("dd/mm/yyyy");
    ws.write_datetime_with_format(1, 2, ExcelDateTime::from_ymd(2024, 1, 15).unwrap(), &date_fmt).unwrap();
    let ws2 = wb.add_worksheet().set_name("Second").unwrap();
    ws2.write_formula(0, 0, "=Data!B4*2").unwrap();
    wb.save(path).unwrap();
}

// ---------- workbooks ----------

#[test]
fn supported_extensions_list() {
    let s = take(foglio_supported_extensions());
    for ext in ["xlsx", "xlsm", "xls", "xlsb", "ods", "csv", "tsv", "txt"] {
        assert!(s.split(',').any(|e| e == ext), "{ext} missing from {s}");
    }
}

#[test]
fn opens_xlsx_via_ironcalc() {
    let path = tmp_dir().join("sample.xlsx");
    write_xlsx(&path);
    let b = Book::open(&path);
    assert_eq!(b.sheets(), vec!["Data", "Second"]);
    assert_eq!(b.val(0, 3, 1), "Città");
    assert_eq!(b.input(0, 4, 2), "=SUM(B2:B3)");
    assert_eq!(b.val(0, 4, 2), "12.5");
    assert_eq!(b.val(0, 2, 3), "15/01/2024");
    assert_eq!(b.val(1, 1, 1), "25");
    // the formula is live
    let v = CString::new("20").unwrap();
    assert_eq!(unsafe { foglio_set_input(b.0, 0, 2, 2, v.as_ptr()) }, 0);
    assert_eq!(b.val(0, 4, 2), "22.5");
}

#[test]
fn opens_xls() {
    let b = Book::open(&fixture("sample.xls"));
    assert_eq!(b.sheets(), vec!["Data", "Second", "My Sheet"]);
    assert_eq!(b.val(0, 1, 1), "Name");
    assert_eq!(b.val(0, 3, 1), "Città");
    assert_eq!(b.val(0, 2, 2), "10");
    assert_eq!(b.input(0, 4, 2), "=SUM(B2:B3)");
    assert_eq!(b.val(0, 4, 2), "12.5");
    assert_eq!(b.val(0, 2, 3), "15/01/2024");
    assert_eq!(b.val(0, 2, 4), "TRUE");
    assert_eq!(b.input(1, 1, 1), "=Data!B4*2");
    assert_eq!(b.val(1, 1, 1), "25");
    assert_eq!(b.val(1, 2, 1), "plain");
    // cross-sheet area and a sheet name that needs quoting
    assert_eq!(b.input(1, 3, 1), "=SUM(Data!B2:B3)");
    assert_eq!(b.val(1, 3, 1), "12.5");
    assert_eq!(b.input(1, 4, 1), "='My Sheet'!A1+1");
    assert_eq!(b.val(1, 4, 1), "6");
}

#[test]
fn opens_ods() {
    let b = Book::open(&fixture("sample.ods"));
    assert_eq!(b.sheets(), vec!["Data", "Second Sheet"]);
    assert_eq!(b.val(0, 3, 1), "Città");
    assert_eq!(b.input(0, 4, 2), "=SUM(B2:B3)");
    assert_eq!(b.val(0, 4, 2), "12.5");
    assert_eq!(b.input(0, 5, 2), "=IF(B4>1,B4*2,0)");
    assert_eq!(b.val(0, 5, 2), "25");
    assert_eq!(b.val(0, 5, 1), "Semi; colon");
    assert_eq!(b.val(0, 2, 3), "15/01/2024");
    assert_eq!(b.val(0, 2, 4), "TRUE");
    assert_eq!(b.input(1, 1, 1), "=Data!B4*2");
    assert_eq!(b.val(1, 1, 1), "25");
}

#[test]
fn sniffs_unknown_extensions() {
    let d = tmp_dir();
    let xls = d.join("legacy.dat");
    std::fs::copy(fixture("sample.xls"), &xls).unwrap();
    assert_eq!(Book::open(&xls).val(0, 4, 2), "12.5");

    let xlsx = d.join("modern.bin");
    write_xlsx(&xlsx);
    assert_eq!(Book::open(&xlsx).val(0, 4, 2), "12.5");

    let ods = d.join("calc.data");
    std::fs::copy(fixture("sample.ods"), &ods).unwrap();
    assert_eq!(Book::open(&ods).val(0, 4, 2), "12.5");

    let csv = d.join("export.unknown");
    std::fs::copy(fixture("comma.csv"), &csv).unwrap();
    assert_eq!(Book::open(&csv).val(0, 2, 1), "Apple");
}

#[test]
fn upper_case_extension() {
    let p = tmp_dir().join("UPPER.XLS");
    std::fs::copy(fixture("sample.xls"), &p).unwrap();
    assert_eq!(Book::open(&p).val(0, 4, 2), "12.5");
}

#[test]
fn reports_errors() {
    let e = Book::try_open(Path::new("/nonexistent/file.xlsx")).err().unwrap();
    assert!(!e.is_empty());
    let bad = tmp_dir().join("broken.xls");
    std::fs::write(&bad, b"definitely not an OLE file").unwrap();
    assert!(Book::try_open(&bad).is_err());
    let mut err: *mut c_char = ptr::null_mut();
    assert!(unsafe { foglio_open_any(ptr::null(), &mut err) }.is_null());
    assert_eq!(take(err), "invalid path");
}

// ---------- CSV ----------

#[test]
fn csv_comma_quotes_and_formula_safety() {
    let b = Book::open(&fixture("comma.csv"));
    assert_eq!(b.sheets().len(), 1);
    assert_eq!(b.val(0, 1, 4), "note");
    assert_eq!(b.val(0, 2, 1), "Apple");
    assert_eq!(b.val(0, 2, 2), "3");
    assert_eq!(b.val(0, 2, 3), "1.5");
    assert_eq!(b.val(0, 2, 4), "red, round");
    assert_eq!(b.val(0, 3, 4), "says \"hi\"");
    // "=1+1" must stay text, not be evaluated
    assert_eq!(b.val(0, 4, 2), "=1+1");
    assert!(!b.input(0, 4, 2).starts_with('='), "{}", b.input(0, 4, 2));
    assert_eq!(b.val(0, 4, 3), "-2");
    assert_eq!(b.val(0, 4, 4), "multi\nline");
}

#[test]
fn csv_minus_text_is_not_a_formula() {
    let p = tmp_dir().join("minus.csv");
    std::fs::write(&p, "-A1,+foo,-5,@SUM(1)\n1,2,3,4\n").unwrap();
    let b = Book::open(&p);
    assert_eq!(b.val(0, 1, 1), "-A1");
    assert_eq!(b.val(0, 1, 2), "+foo");
    assert_eq!(b.val(0, 1, 3), "-5");
    assert_eq!(b.val(0, 1, 4), "@SUM(1)");
}

#[test]
fn csv_semicolon_decimal_comma() {
    let b = Book::open(&fixture("semicolon_eu.csv"));
    assert_eq!(b.val(0, 1, 1), "Prodotto"); // BOM stripped
    assert_eq!(b.val(0, 1, 2), "Quantità");
    assert_eq!(b.val(0, 2, 1), "Caffè");
    assert_eq!(b.val(0, 2, 3), "3.5");
    assert_eq!(b.input(0, 3, 2), "1234.56");
    assert_eq!(b.input(0, 3, 4), "0.125");
    assert_eq!(b.val(0, 3, 3), "1000"); // the file uses decimal commas, so '.' groups thousands
    assert_eq!(b.val(0, 2, 4), "7");
    assert!(b.val(0, 3, 4).ends_with('%'), "{}", b.val(0, 3, 4));
    // text with commas is never mangled
    assert_eq!(b.val(0, 4, 2), "abc,def");
    assert_eq!(b.val(0, 4, 4), "1,5,6");
}

#[test]
fn csv_tab_separated() {
    let b = Book::open(&fixture("tabs.tsv"));
    assert_eq!(b.val(0, 2, 3), "3");
    assert_eq!(b.val(0, 3, 1), "x,y");
    assert_eq!(b.val(0, 3, 2), "z;w");
    assert_eq!(b.val(0, 3, 3), "4.5");
}

#[test]
fn csv_pipe_txt() {
    let b = Book::open(&fixture("pipes.txt"));
    assert_eq!(b.val(0, 2, 2), "Ann");
    assert_eq!(b.val(0, 2, 3), "9.5");
}

#[test]
fn csv_utf16_bom() {
    let b = Book::open(&fixture("utf16.csv"));
    assert_eq!(b.val(0, 1, 1), "città");
    assert_eq!(b.val(0, 2, 1), "Zürich");
    assert_eq!(b.val(0, 2, 2), "42");
    assert_eq!(b.val(0, 3, 1), "東京");
}

#[test]
fn csv_windows_1252() {
    let b = Book::open(&fixture("cp1252.csv"));
    assert_eq!(b.val(0, 2, 1), "perché");
    assert_eq!(b.val(0, 3, 1), "Café €");
    assert_eq!(b.val(0, 3, 2), "10");
}

#[test]
fn save_csv_round_trip() {
    let b = Book::open(&fixture("sample.xls"));
    let out = tmp_dir().join("out.csv");
    b.save_csv(0, &out, b',');
    let text = std::fs::read_to_string(&out).unwrap();
    let text = text.strip_prefix('\u{FEFF}').expect("CSV starts with a UTF-8 BOM");
    let lines: Vec<&str> = text.split("\r\n").collect();
    assert_eq!(lines[0], "Name,Value,When,Flag");
    assert_eq!(lines[1], "Alpha,10,15/01/2024,TRUE");
    assert_eq!(lines[2], "Città,2.5,,");
    assert_eq!(lines[3], "Total,12.5,,");

    // quoting + semicolon delimiter, then re-open
    let c = Book::open(&fixture("comma.csv"));
    let out2 = tmp_dir().join("out2.csv");
    c.save_csv(0, &out2, b';');
    let text = std::fs::read_to_string(&out2).unwrap();
    assert!(text.contains("\"says \"\"hi\"\"\""), "{text}");
    assert!(text.contains("\"multi\nline\""), "{text}");
    let r = Book::open(&out2);
    assert_eq!(r.val(0, 2, 4), "red, round");
    assert_eq!(r.val(0, 3, 4), "says \"hi\"");
    assert_eq!(r.val(0, 4, 2), "=1+1");

    // invalid sheet
    let mut err: *mut c_char = ptr::null_mut();
    let p = CString::new(out.to_str().unwrap()).unwrap();
    assert_eq!(unsafe { foglio_save_csv(b.0, 9, p.as_ptr(), b',', &mut err) }, -1);
    assert!(!take(err).is_empty());
}

// ---------- locale ----------

#[test]
fn italian_locale() {
    let _g = LOCALE_LOCK.write().unwrap_or_else(|e| e.into_inner());
    let set = |l: &str, lang: &str, tz: &str| {
        let (l, lang, tz) = (CString::new(l).unwrap(), CString::new(lang).unwrap(), CString::new(tz).unwrap());
        unsafe { foglio_set_locale(l.as_ptr(), lang.as_ptr(), tz.as_ptr()) };
    };
    set("it", "it", "Europe/Rome");
    let result = std::panic::catch_unwind(|| {
        let open = |p: &Path| Book::try_open_unlocked(p).unwrap();
        // US-style CSV: 1.5 is one and a half, whatever the locale
        let b = open(&fixture("comma.csv"));
        assert_eq!(b.input(0, 2, 3), "1,5");
        assert_eq!(b.val(0, 2, 3), "1,5");
        assert_eq!(b.val(0, 4, 2), "=1+1");
        // European CSV
        let b = open(&fixture("semicolon_eu.csv"));
        assert_eq!(b.val(0, 2, 3), "3,5");
        assert_eq!(b.input(0, 3, 2), "1234,56");
        // dates follow the app's locale (dd/mm/yyyy in Italy)
        let p = tmp_dir().join("it_dates.csv");
        std::fs::write(&p, "data;valore\n15/01/2024;2,5\n").unwrap();
        let b = open(&p);
        assert_eq!(b.val(0, 2, 1), "15/01/2024");
        assert!(b.input(0, 2, 1).contains("2024"), "{}", b.input(0, 2, 1));
        assert_eq!(b.val(0, 2, 2), "2,5");
        // xls / ods: English formulas from the file, shown in Italian
        let b = open(&fixture("sample.xls"));
        assert_eq!(b.val(0, 4, 2), "12,5");
        assert_eq!(b.input(0, 4, 2), "=SOMMA(B2:B3)");
        assert_eq!(b.val(1, 1, 1), "25");
        let b = open(&fixture("sample.ods"));
        assert_eq!(b.input(0, 5, 2), "=SE(B4>1;B4*2;0)");
        assert_eq!(b.val(0, 5, 2), "25");
        // xlsx through IronCalc
        let x = tmp_dir().join("it.xlsx");
        write_xlsx(&x);
        let b = open(&x);
        assert_eq!(b.val(0, 4, 2), "12,5");
        assert_eq!(b.input(0, 4, 2), "=SOMMA(B2:B3)");
    });
    set("en", "en", "UTC");
    if let Err(e) = result {
        std::panic::resume_unwind(e);
    }
}

// ---------- performance ----------

const PERF_ROWS: usize = 10_000;
const PERF_COLS: usize = 10;

#[test]
fn load_time_100k_csv() {
    let p = tmp_dir().join("big.csv");
    let mut s = String::with_capacity(PERF_ROWS * PERF_COLS * 8);
    for r in 0..PERF_ROWS {
        for c in 0..PERF_COLS {
            if c > 0 {
                s.push(',');
            }
            if c == 0 {
                s.push_str(&format!("item {r}"));
            } else {
                s.push_str(&format!("{}.{}", r * c, c));
            }
        }
        s.push('\n');
    }
    std::fs::write(&p, s).unwrap();
    let t = Instant::now();
    let b = Book::open(&p);
    let el = t.elapsed();
    println!("LOAD 100k-cell CSV ({} bytes): {:?}", std::fs::metadata(&p).unwrap().len(), el);
    assert_eq!(b.val(0, PERF_ROWS as i32, 1), format!("item {}", PERF_ROWS - 1));
}

#[test]
fn load_time_100k_xlsx() {
    use rust_xlsxwriter::Workbook;
    let p = tmp_dir().join("big.xlsx");
    let mut wb = Workbook::new();
    let ws = wb.add_worksheet();
    for r in 0..PERF_ROWS as u32 {
        ws.write(r, 0, format!("item {r}")).unwrap();
        for c in 1..PERF_COLS as u16 - 1 {
            ws.write(r, c, (r as f64) * c as f64 + 0.5).unwrap();
        }
        ws.write_formula(r, PERF_COLS as u16 - 1, format!("=SUM(B{0}:I{0})", r + 1).as_str()).unwrap();
    }
    wb.save(&p).unwrap();
    let t = Instant::now();
    let b = Book::open(&p);
    let el = t.elapsed();
    println!("LOAD 100k-cell XLSX ({} bytes, 10k formulas): {:?}", std::fs::metadata(&p).unwrap().len(), el);
    assert_eq!(b.val(0, 1, 10), "4"); // 0.5 * 8 for row 0

    // Same file through the calamine path (used for xls/xlsb/ods and as the xlsx fallback).
    let t = Instant::now();
    let m = foglio_core::io::bench_open_with_calamine(p.to_str().unwrap()).unwrap();
    println!("LOAD 100k-cell XLSX via calamine path: {:?}", t.elapsed());
    drop(m);
}
