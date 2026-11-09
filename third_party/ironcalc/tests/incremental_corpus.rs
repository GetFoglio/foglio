#![allow(clippy::unwrap_used)]
#![allow(clippy::panic)]

//! Foglio fork: incremental recalculation on real workbooks.
//!
//! Every xlsx file of the test corpus (Excel-made workbooks covering most
//! functions, plus templates) is loaded into a `UserModel` with the
//! incremental check on (`set_check_incremental`): after every incremental
//! evaluation a full one runs and all cells are compared, a difference
//! panics. Then random edits are made: numbers and texts typed over
//! constants, constants cleared, formulas copied to other cells, undo/redo.
//! Workbooks with functions whose value changes on every evaluation
//! (NOW, TODAY, RAND, …) are skipped: a full evaluation cannot reproduce them.

use std::path::{Path, PathBuf};

use ironcalc::import::load_from_xlsx;
use ironcalc_base::cell::CellValue;
use ironcalc_base::expressions::types::Area;
use ironcalc_base::UserModel;

struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.0 = x;
        x
    }
    fn below(&mut self, n: u64) -> u64 {
        self.next() % n.max(1)
    }
}

fn xlsx_files(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            xlsx_files(&path, out);
        } else if path.extension().is_some_and(|e| e == "xlsx")
            && !path.file_name().unwrap().to_string_lossy().starts_with('~')
        {
            out.push(path);
        }
    }
}

const VOLATILE: &[&str] = &["NOW(", "TODAY(", "RAND", "CELL(", "INFO("];

fn run_file(path: &Path, seed: u64) -> Option<(usize, usize)> {
    let model = load_from_xlsx(path.to_str().unwrap(), "en", "UTC", "en").ok()?;
    // Positions of constants and formulas.
    let mut constants = Vec::new();
    let mut formulas = Vec::new();
    for (sheet, worksheet) in model.workbook.worksheets.iter().enumerate() {
        for (row, column, _) in worksheet.sheet_data.cells() {
            let content = model
                .get_localized_cell_content(sheet as u32, row, column)
                .unwrap_or_default();
            if content.starts_with('=') {
                let upper = content.to_uppercase();
                if VOLATILE.iter().any(|v| upper.contains(v)) {
                    return None;
                }
                formulas.push((sheet as u32, row, column, content));
            } else if !content.is_empty() {
                constants.push((sheet as u32, row, column));
            }
        }
    }
    if formulas.is_empty() || constants.is_empty() {
        return None;
    }
    let mut user = UserModel::from_model(model);
    user.set_check_incremental(true);
    user.evaluate();
    let mut rng = Rng(seed | 1);
    let (mut incremental, mut full) = (0, 0);
    for _ in 0..40 {
        let (sheet, row, column) = constants[rng.below(constants.len() as u64) as usize];
        match rng.below(10) {
            0..=5 => {
                let value = match user.get_model().get_cell_value_by_index(sheet, row, column) {
                    Ok(CellValue::Number(n)) => format!("{}", n + (rng.below(7) as f64) - 3.0),
                    _ => format!("{}", rng.below(100)),
                };
                let _ = user.set_user_input(sheet, row, column, &value);
            }
            6 => {
                let _ = user.set_user_input(sheet, row, column, "text");
            }
            7 => {
                let _ = user.range_clear_contents(&Area {
                    sheet,
                    row,
                    column,
                    width: 1,
                    height: 1,
                });
            }
            8 => {
                // A formula of the workbook typed into another cell.
                let (_, _, _, formula) = &formulas[rng.below(formulas.len() as u64) as usize];
                let _ = user.set_user_input(sheet, row, column, formula);
            }
            _ => {
                if rng.below(2) == 0 {
                    let _ = user.undo();
                } else {
                    let _ = user.redo();
                }
            }
        }
        match user.last_evaluation_incremental() {
            Some(_) => incremental += 1,
            None => full += 1,
        }
    }
    Some((incremental, full))
}

#[test]
fn incremental_recalculation_matches_full_on_the_corpus() {
    let mut files = Vec::new();
    xlsx_files(Path::new("tests"), &mut files);
    files.sort();
    let (mut checked, mut incremental, mut full) = (0, 0, 0);
    for (i, path) in files.iter().enumerate() {
        let result = std::panic::catch_unwind(|| run_file(path, 0x5eed + i as u64));
        match result {
            Ok(Some((inc, f))) => {
                checked += 1;
                incremental += inc;
                full += f;
            }
            Ok(None) => {}
            Err(_) => panic!("incremental recalculation differs in {}", path.display()),
        }
    }
    eprintln!("{checked} workbooks, {incremental} incremental and {full} full evaluations");
    assert!(checked > 50);
    assert!(incremental > full);
}
