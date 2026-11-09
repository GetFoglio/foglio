//! `cargo run --release --example xlsx_values -- out.txt file.xlsx [more …]`:
//! writes every formula cell's value after loading (conditional formatting
//! evaluated) and after a full evaluation, plus the time each file took, so
//! two builds of the engine can be compared with `diff`.
use std::io::Write;
use std::time::Instant;

use ironcalc::base::Model;

fn dump(model: &Model, out: &mut impl Write, phase: &str) {
    for (sheet, worksheet) in model.workbook.worksheets.iter().enumerate() {
        for (row, column, cell) in worksheet.sheet_data.cells() {
            if cell.get_formula().is_none() {
                continue;
            }
            let value = model.get_cell_value_by_index(sheet as u32, row, column);
            writeln!(out, "{phase} {sheet}!R{row}C{column} {value:?}").unwrap();
        }
    }
}

fn main() {
    let mut args = std::env::args().skip(1);
    let out_path = args.next().expect("output file");
    let mut out = std::io::BufWriter::new(std::fs::File::create(out_path).expect("create"));
    for path in args {
        let Ok(bytes) = std::fs::read(&path) else {
            continue;
        };
        let started = Instant::now();
        // Some files make the importer panic; they are skipped.
        let Ok(Ok(workbook)) = std::panic::catch_unwind(|| {
            ironcalc::import::load_from_xlsx_bytes(&bytes, "book", "en", "UTC")
        }) else {
            continue;
        };
        let Ok(mut model) = Model::from_workbook(workbook, "en") else {
            continue;
        };
        writeln!(out, "FILE {path}").unwrap();
        dump(&model, &mut out, "load");
        model.evaluate();
        dump(&model, &mut out, "eval");
        eprintln!("{:>10.1} ms {path}", started.elapsed().as_secs_f64() * 1000.0);
    }
}
