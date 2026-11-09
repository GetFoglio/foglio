//! Diagnose why a file does not open: `cargo run --release --example probe -- file.xlsx`
fn main() {
    let path = std::env::args().nth(1).expect("path");
    match std::panic::catch_unwind(|| foglio_core::io::bench_open_with_calamine(&path)) {
        Ok(Ok(_)) => println!("calamine xlsx: OK"),
        Ok(Err(e)) => println!("calamine xlsx: {e}"),
        Err(_) => println!("calamine xlsx: PANIC"),
    }
    match std::panic::catch_unwind(|| ironcalc::import::load_from_xlsx(&path, "en", "UTC", "en")) {
        Ok(Ok(m)) => println!("ironcalc: OK, charts per sheet: {:?}", m.workbook.worksheets.iter().map(|w| w.charts.len()).collect::<Vec<_>>()),
        Ok(Err(e)) => println!("ironcalc: {e:?}"),
        Err(_) => println!("ironcalc: PANIC"),
    }
}
