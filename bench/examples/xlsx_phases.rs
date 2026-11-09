//! `cargo run --release --example xlsx_phases -- file.xlsx [more.xlsx …]`:
//! time of each phase of opening an xlsx (read the package, build the model:
//! parse formulas + conditional formatting, first full evaluation, second
//! evaluation).
use std::time::Instant;

use ironcalc::base::Model;

fn main() {
    for path in std::env::args().skip(1) {
        let bytes = std::fs::read(&path).expect("read");
        let t = Instant::now();
        let workbook =
            ironcalc::import::load_from_xlsx_bytes(&bytes, "book", "en", "UTC").expect("load");
        let read = t.elapsed();
        let t = Instant::now();
        let mut model = Model::from_workbook(workbook, "en").expect("model");
        let build = t.elapsed();
        let t = Instant::now();
        model.evaluate();
        let first = t.elapsed();
        let t = Instant::now();
        model.evaluate();
        let second = t.elapsed();
        println!(
            "{path}: read {read:?}, from_workbook {build:?}, evaluate {first:?}, again {second:?}"
        );
    }
}
