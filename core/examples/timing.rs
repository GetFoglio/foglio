//! `cargo run --release --example timing -- file.xlsx`: load vs evaluate time and formula count.
use std::time::Instant;
fn main() {
    let path = std::env::args().nth(1).expect("path");
    let t = Instant::now();
    let mut m = ironcalc::import::load_from_xlsx(&path, "en", "UTC", "en").expect("load");
    println!("load: {:?}", t.elapsed());
    let n: usize = m.workbook.worksheets.iter().map(|w| w.sheet_data.cells().filter(|(_, _, c)| c.get_formula().is_some()).count()).sum();
    println!("formulas: {n}, sheets: {}", m.workbook.worksheets.len());
    let t = Instant::now();
    m.evaluate();
    println!("evaluate: {:?}", t.elapsed());
}
