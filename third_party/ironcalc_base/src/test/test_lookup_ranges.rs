#![allow(clippy::unwrap_used)]
#![allow(clippy::panic)]

//! Foglio fork: lookups read only the used part of their vectors, once per
//! evaluation pass (`functions/lookup_cache.rs`).
//!
//! The reference is the naive evaluation (`NAIVE_LOOKUPS`): every lookup
//! reads its whole vector — a million cells for `A:A` — on every call, with
//! no cache and no index, and searches it as upstream did. Randomized
//! workbooks with whole-column, whole-row, tall and structured-reference
//! lookups over mixed data (numbers, zeros, text with wildcards, booleans,
//! errors, empty cells inside and below the data, formulas, spills) are
//! evaluated both ways, at load (conditional formatting, outside a pass) and
//! by a full evaluation, and every cell must be identical. Edits go through a
//! `UserModel` in check mode (incremental vs full).

use std::collections::HashMap;

use crate::calc_result::CalcResult;
use crate::cf_types::CfRuleInput;
use crate::expressions::token::Error;
use crate::expressions::types::CellReferenceIndex;
use crate::functions::binary_search::binary_search_on_array;
use crate::functions::lookup_cache::{LookupMode, VectorData, NAIVE_LOOKUPS};
use crate::functions::util::{
    compare_values, from_wildcard_to_regex, result_matches_regex, values_are_equal,
};
use crate::model::Model;
use crate::sheet_data::SheetData;
use crate::types::{Dxf, Table, TableColumn, TableStyleInfo, Workbook};
use crate::UserModel;

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
        self.next() % n
    }
    fn chance(&mut self, percent: u64) -> bool {
        self.below(100) < percent
    }
    fn pick<'b, T>(&mut self, items: &'b [T]) -> &'b T {
        &items[self.below(items.len() as u64) as usize]
    }
}

// ---------------------------------------------------------------------------
// The searches against upstream's
// ---------------------------------------------------------------------------

fn origin() -> CellReferenceIndex {
    CellReferenceIndex {
        sheet: 0,
        row: 1,
        column: 1,
    }
}

fn random_value(rng: &mut Rng) -> CalcResult {
    match rng.below(14) {
        0 => CalcResult::EmptyCell,
        1 => CalcResult::Number(0.0),
        2 => CalcResult::Number(rng.below(20) as f64 - 5.0),
        3 => CalcResult::Number((rng.below(20) as f64) / 8.0),
        4 => CalcResult::Number(0.1 + 0.2),
        5 => CalcResult::Number(0.3),
        6 => CalcResult::Number(1.0 + 1e-15),
        7 => CalcResult::Boolean(rng.chance(50)),
        8 => CalcResult::Error {
            error: Error::NA,
            origin: origin(),
            message: String::new(),
        },
        9 => CalcResult::String(String::new()),
        _ => CalcResult::String(
            rng.pick(&[
                "a", "A", "b", "apple", "APPLE", "a*", "b?c", "~", "x~y", "Ünï", "10",
            ])
            .to_string(),
        ),
    }
}

/// Upstream's VLOOKUP/HLOOKUP exact search (`lookup_index` with FALSE).
fn upstream_vlookup_exact(target: &CalcResult, array: &[CalcResult]) -> Option<usize> {
    if let CalcResult::String(s) = target {
        match from_wildcard_to_regex(&s.to_lowercase(), true) {
            Ok(reg) => array.iter().position(|x| result_matches_regex(x, &reg)),
            Err(_) => None,
        }
    } else {
        array.iter().position(|x| compare_values(x, target) == 0)
    }
}

/// Upstream's MATCH(…, 0).
fn upstream_match_exact(target: &CalcResult, array: &[CalcResult]) -> Option<usize> {
    if let CalcResult::String(s) = target {
        match from_wildcard_to_regex(&s.to_lowercase(), true) {
            Ok(reg) => array.iter().position(|x| result_matches_regex(x, &reg)),
            Err(_) => None,
        }
    } else {
        array.iter().position(|x| values_are_equal(x, target))
    }
}

fn show(value: &CalcResult) -> String {
    match value {
        CalcResult::String(s) => format!("{s:?}"),
        CalcResult::Number(f) => format!("{f:?}"),
        CalcResult::Boolean(b) => format!("{b}"),
        CalcResult::Error { error, .. } => format!("{error}"),
        CalcResult::EmptyCell => "(empty)".to_string(),
        _ => "(other)".to_string(),
    }
}

fn show_all(values: &[CalcResult]) -> String {
    values.iter().map(show).collect::<Vec<_>>().join(", ")
}

fn same(a: &CalcResult, b: &CalcResult) -> bool {
    show(a) == show(b)
}

#[test]
fn vector_searches_match_upstream_on_materialized_vectors() {
    let mut rng = Rng(0x9e37_79b9_7f4a_7c15);
    for _ in 0..3000 {
        let visited = rng.below(12) as usize;
        let tail = if rng.chance(50) {
            0
        } else {
            rng.below(6) as usize
        };
        let mut values: Vec<CalcResult> = (0..visited).map(|_| random_value(&mut rng)).collect();
        if rng.chance(30) {
            // sorted data, as approximate lookups expect
            values.sort_by(|a, b| compare_values(a, b).cmp(&0));
        }
        let mut full = values.clone();
        full.extend((0..tail).map(|_| CalcResult::EmptyCell));
        for cached in [false, true] {
            let vector = VectorData::for_test(values.clone(), visited + tail, cached);
            assert_eq!(vector.len(), full.len());
            for (i, value) in full.iter().enumerate() {
                assert!(same(vector.get(i), value));
            }
            for _ in 0..8 {
                let target = random_value(&mut rng);
                assert_eq!(
                    vector.binary_search(&target),
                    binary_search_on_array(&target, &full),
                    "binary search for {} in {}",
                    show(&target),
                    show_all(&full)
                );
                if !matches!(target, CalcResult::EmptyCell) {
                    assert_eq!(
                        vector.exact_position(&target, LookupMode::Vlookup),
                        upstream_vlookup_exact(&target, &full),
                        "VLOOKUP exact {} in {} (cached: {cached})",
                        show(&target),
                        show_all(&full)
                    );
                    assert_eq!(
                        vector.exact_position(&target, LookupMode::Match),
                        upstream_match_exact(&target, &full),
                        "MATCH exact {} in {} (cached: {cached})",
                        show(&target),
                        show_all(&full)
                    );
                }
            }
        }
    }
}

#[test]
fn used_extent_is_the_dimension() {
    let mut rng = Rng(77);
    for _ in 0..300 {
        let mut model = Model::new_empty("model", "en", "UTC", "en").unwrap();
        for _ in 0..rng.below(30) {
            let row = if rng.chance(10) {
                1_048_576 - rng.below(3) as i32
            } else {
                1 + rng.below(3000) as i32
            };
            let width = if rng.chance(10) { 16384 } else { 30 };
            let column = 1 + rng.below(width) as i32;
            if rng.chance(20) {
                model
                    .workbook
                    .worksheet_mut(0)
                    .unwrap()
                    .sheet_data
                    .set_row(row, std::iter::empty());
            } else {
                model
                    .set_user_input(0, row, column, rng.below(9).to_string())
                    .unwrap();
            }
            if rng.chance(20) {
                model
                    .workbook
                    .worksheet_mut(0)
                    .unwrap()
                    .cell_clear_contents(row, column)
                    .unwrap();
            }
        }
        let worksheet = model.workbook.worksheet(0).unwrap();
        let dimension = worksheet.dimension();
        assert_eq!(worksheet.used_max_row(), dimension.max_row);
        assert_eq!(worksheet.used_max_column(), dimension.max_column);
    }
}

// ---------------------------------------------------------------------------
// Workbooks: optimized against naive
// ---------------------------------------------------------------------------

fn snapshot(model: &Model) -> Vec<SheetData> {
    model
        .workbook
        .worksheets
        .iter()
        .map(|w| w.sheet_data.clone())
        .collect()
}

fn describe_difference(model: &Model, expected: &[SheetData], got: &[SheetData]) -> String {
    let mut message = String::new();
    for (sheet, (a, b)) in expected.iter().zip(got).enumerate() {
        for (row, column, cell) in a.cells() {
            let other = b.cell(row, column);
            if other.as_deref() != Some(&*cell) {
                let formula = model
                    .get_cell_formula(sheet as u32, row, column)
                    .ok()
                    .flatten()
                    .unwrap_or_default();
                message.push_str(&format!(
                    "\n  {sheet}!R{row}C{column} {formula}: naive {cell:?}, optimized {other:?}"
                ));
            }
        }
        for (row, column, cell) in b.cells() {
            if a.cell(row, column).is_none() {
                message.push_str(&format!(
                    "\n  {sheet}!R{row}C{column}: naive (none), optimized {cell:?}"
                ));
            }
        }
    }
    message
}

/// Loads `workbook` (the conditional formatting evaluates what it reads,
/// outside a pass) and evaluates it, naive and optimized; both states must be
/// identical.
fn assert_same_as_naive(workbook: &Workbook, label: &str) {
    let run = |naive: bool| {
        NAIVE_LOOKUPS.with(|n| n.set(naive));
        let mut model = Model::from_workbook(workbook.clone(), "en").unwrap();
        let loaded = snapshot(&model);
        let cf: Vec<_> = (0..model.workbook.worksheets.len() as u32)
            .map(|sheet| {
                (1..=40)
                    .map(|row| model.get_extended_style_for_cell(sheet, row, 1).ok())
                    .collect::<Vec<_>>()
            })
            .collect();
        model.evaluate();
        let evaluated = snapshot(&model);
        model.evaluate();
        let again = snapshot(&model);
        NAIVE_LOOKUPS.with(|n| n.set(false));
        (model, loaded, format!("{cf:?}"), evaluated, again)
    };
    let (naive_model, naive_loaded, naive_cf, naive_evaluated, _) = run(true);
    let (_, loaded, cf, evaluated, again) = run(false);
    if naive_loaded != loaded {
        panic!(
            "{label}: after loading{}",
            describe_difference(&naive_model, &naive_loaded, &loaded)
        );
    }
    assert_eq!(naive_cf, cf, "{label}: conditional formatting");
    if naive_evaluated != evaluated {
        panic!(
            "{label}: after evaluating{}",
            describe_difference(&naive_model, &naive_evaluated, &evaluated)
        );
    }
    if naive_evaluated != again {
        panic!(
            "{label}: second evaluation{}",
            describe_difference(&naive_model, &naive_evaluated, &again)
        );
    }
}

const DATA: u32 = 0;

fn data_input(rng: &mut Rng, row: i32, sorted_column: bool) -> Option<String> {
    if sorted_column {
        // ascending numbers with some text at the end, as approximate
        // lookups expect (and the odd break, as they do not)
        return Some(if rng.chance(5) {
            "text".to_string()
        } else if rng.chance(5) {
            String::new()
        } else {
            (row * 3 - rng.below(2) as i32).to_string()
        });
    }
    Some(
        match rng.below(20) {
            0 | 1 => return None,
            2 => "0".to_string(),
            3 => "0.5".to_string(),
            4 => "-3".to_string(),
            5 => "TRUE".to_string(),
            6 => "FALSE".to_string(),
            7 => "=NA()".to_string(),
            8 => "=1/0".to_string(),
            9 => "=\"\"".to_string(),
            10 => format!("=A{}+1", (row - 1).max(1)),
            11 => "=0.1+0.2".to_string(),
            12 => rng
                .pick(&["apple", "APPLE", "a*", "b?c", "~", "pear", "Pear", "x y"])
                .to_string(),
            13 => format!("k{}", rng.below(8)),
            _ => (1 + rng.below(12)).to_string(),
        }
        .to_string(),
    )
}

fn random_key(rng: &mut Rng, rows: i32) -> String {
    match rng.below(16) {
        0 => "0".to_string(),
        1 => "\"\"".to_string(),
        2 => "TRUE".to_string(),
        3 => "FALSE".to_string(),
        4 => "\"a*\"".to_string(),
        5 => "\"~*\"".to_string(),
        6 => "\"?pple\"".to_string(),
        7 => "NA()".to_string(),
        8 => "Data!Z999".to_string(),
        9 => "0.3".to_string(),
        10 => format!("\"k{}\"", rng.below(8)),
        11 => "\"APPLE\"".to_string(),
        12 => format!("{}", rng.below(40) as f64 / 2.0),
        _ => format!(
            "Data!{}{}",
            rng.pick(&["A", "B", "C"]),
            1 + rng.below(rows as u64 + 3)
        ),
    }
}

/// Columns `first..last` of Data, in one of six shapes (`kind`).
fn column_range(kind: u64, first: &str, last: &str, rows: i32) -> String {
    match kind {
        0 | 1 | 2 => format!("Data!${first}:${last}"),
        3 => format!("Data!{first}1:{last}{}", rows + 40),
        4 => format!("Data!{first}2:{last}1048576"),
        _ => format!("Data!{first}1:{last}{}", rows.max(2) - 1),
    }
}

fn random_row_range(rng: &mut Rng, rows_down: i32) -> String {
    match rng.below(3) {
        0 | 1 => format!("Data!$1:${rows_down}"),
        _ => format!("Data!A1:AZ{rows_down}"),
    }
}

fn random_lookup(rng: &mut Rng, rows: i32, table: bool) -> String {
    let key = random_key(rng, rows);
    let sorted = *rng.pick(&["FALSE", "TRUE", "0", "1"]);
    let kind = rng.below(6);
    let a = column_range(kind, "A", "A", rows);
    let b = column_range(kind, "B", "B", rows);
    let a_c = column_range(rng.below(6), "A", "C", rows);
    match rng.below(if table { 18 } else { 15 }) {
        0 | 1 => format!("VLOOKUP({key},{a_c},{},{sorted})", 1 + rng.below(3)),
        2 => format!("VLOOKUP({key},{a_c},2)"),
        3 => format!(
            "HLOOKUP({key},{},{},{sorted})",
            random_row_range(rng, 3),
            1 + rng.below(3)
        ),
        4 => format!("MATCH({key},{a},{})", rng.pick(&["0", "1", "-1"])),
        5 => format!("MATCH({key},{a})"),
        6 => format!("MATCH({key},{},0)", random_row_range(rng, 1)),
        7 => format!("LOOKUP({key},{a},{b})"),
        8 => format!("LOOKUP({key},{a_c})"),
        9 => format!(
            "XLOOKUP({key},{a},{b},\"nf\",{},{})",
            rng.pick(&["0", "-1", "1", "2"]),
            rng.pick(&["1", "-1", "2", "-2"])
        ),
        10 => format!(
            "XMATCH({key},{a},{},{})",
            rng.pick(&["0", "-1", "1", "2"]),
            rng.pick(&["1", "-1", "2", "-2"])
        ),
        11 => format!("INDEX({b},MATCH({key},{a},0))"),
        12 => format!("COUNTIF({a},{key})"),
        13 => format!("SUMIF({a},{key},{b})"),
        14 => format!("IF(ISNA(VLOOKUP({key},{a_c},2,FALSE)),\" \",VLOOKUP({key},{a_c},2,FALSE))"),
        15 => format!("VLOOKUP({key},TblData[#All],{},{sorted})", 1 + rng.below(3)),
        16 => format!("MATCH({key},TblData[k],0)"),
        _ => format!("XLOOKUP({key},TblData[k],TblData[v])"),
    }
}

fn add_table(model: &mut Model, rows: i32) {
    let columns = ["k", "v", "w"]
        .iter()
        .enumerate()
        .map(|(id, name)| TableColumn {
            id: id as u32 + 1,
            name: name.to_string(),
            ..Default::default()
        })
        .collect();
    model.workbook.tables.insert(
        "TblData".to_string(),
        Table {
            name: "TblData".to_string(),
            display_name: "TblData".to_string(),
            sheet_name: "Data".to_string(),
            reference: format!("A1:C{}", rows.max(2)),
            totals_row_count: 0,
            header_row_count: 1,
            header_row_dxf_id: None,
            data_dxf_id: None,
            totals_row_dxf_id: None,
            columns,
            style_info: TableStyleInfo::default(),
            has_filters: false,
        },
    );
}

fn red() -> Dxf {
    Dxf::default()
}

/// A random workbook: `Data` (lookup tables, sometimes a table `TblData`, a
/// spill, a cycle) and `Calc` (lookups into it), with a conditional format
/// on `Calc` that reads the lookups at load time.
fn random_workbook(rng: &mut Rng) -> Workbook {
    let mut model = Model::new_empty("model", "en", "UTC", "en").unwrap();
    model.rename_sheet("Sheet1", "Data").unwrap();
    model.add_sheet("Calc").unwrap();
    let rows = 2 + rng.below(30) as i32;
    let table = rng.chance(30);
    let sorted_a = rng.chance(30);
    if table {
        for (column, name) in ["k", "v", "w"].iter().enumerate() {
            model
                .set_user_input(DATA, 1, column as i32 + 1, name.to_string())
                .unwrap();
        }
    }
    let first = if table { 2 } else { 1 };
    for row in first..=rows {
        for column in 1..=4 {
            if let Some(input) = data_input(rng, row, sorted_a && column == 1) {
                model.set_user_input(DATA, row, column, input).unwrap();
            }
        }
    }
    // Something far to the right on the first rows, for whole-row lookups.
    if rng.chance(30) {
        model
            .set_user_input(
                DATA,
                1 + rng.below(3) as i32,
                30 + rng.below(20) as i32,
                "k3".to_string(),
            )
            .unwrap();
    }
    // A spill into the lookup column, below the data: it extends the used
    // area when it runs.
    if rng.chance(25) {
        model
            .set_user_input(
                DATA,
                rows + 1 + rng.below(3) as i32,
                1,
                format!("=SEQUENCE({},1,{},2)", 1 + rng.below(12), rng.below(5)),
            )
            .unwrap();
    }
    // A spill next to the data that the lookups' tables cover.
    if rng.chance(15) {
        model
            .set_user_input(DATA, 1 + rng.below(3) as i32, 2, "=SEQUENCE(4)".to_string())
            .unwrap();
    }
    if table {
        // Before the formulas that name it are parsed.
        add_table(&mut model, rows);
        model = Model::from_workbook(model.workbook.clone(), "en").unwrap();
    }
    // A lookup inside its own column: a cycle.
    if rng.chance(10) {
        model
            .set_user_input(DATA, rows + 8, 1, format!("=MATCH(5,A:A,0)"))
            .unwrap();
    }
    // A lookup in the data reading the lookups (chains through Calc).
    if rng.chance(15) {
        model
            .set_user_input(DATA, rows + 6, 3, "=Calc!A1&\"\"".to_string())
            .unwrap();
    }
    let formulas = 6 + rng.below(14) as i32;
    for row in 1..=formulas {
        let formula = random_lookup(rng, rows, table);
        model
            .set_user_input(1, row, 1, format!("={formula}"))
            .unwrap();
        if rng.chance(25) {
            // A lookup keyed on another lookup.
            model
                .set_user_input(1, row, 2, format!("=VLOOKUP(A{row},Data!A:C,2,FALSE)"))
                .unwrap();
        }
    }
    model
        .add_conditional_formatting(
            1,
            "A1:B40",
            CfRuleInput::Formula {
                formula: "=ISERROR(A1)".to_string(),
                format: red(),
                stop_if_true: false,
            },
        )
        .unwrap();
    model.workbook.clone()
}

#[test]
fn random_workbooks_match_naive_evaluation() {
    let mut rng = Rng(0x2545_f491_4f6c_dd1d);
    for case in 0..60 {
        let workbook = random_workbook(&mut rng);
        assert_same_as_naive(&workbook, &format!("case {case}"));
    }
}

#[test]
#[ignore]
fn many_random_workbooks_match_naive_evaluation() {
    let mut rng = Rng(0x1234_5678_9abc_def1);
    for case in 0..600 {
        let workbook = random_workbook(&mut rng);
        assert_same_as_naive(&workbook, &format!("case {case}"));
    }
}

// ---------------------------------------------------------------------------
// Targeted cases
// ---------------------------------------------------------------------------

fn model_with(cells: &[(u32, &str, &str)]) -> Model<'static> {
    let mut model = Model::new_empty("model", "en", "UTC", "en").unwrap();
    model.add_sheet("Calc").unwrap();
    for (sheet, cell, input) in cells {
        let reference = model
            .parse_reference(&format!(
                "{}!{cell}",
                if *sheet == 0 { "Sheet1" } else { "Calc" }
            ))
            .unwrap();
        model
            .set_user_input(*sheet, reference.row, reference.column, input.to_string())
            .unwrap();
    }
    model
}

fn value(model: &Model, sheet: u32, row: i32, column: i32) -> String {
    model.get_formatted_cell_value(sheet, row, column).unwrap()
}

#[test]
fn empty_cells_below_the_data_still_match() {
    let model = model_with(&[
        (0, "A1", "1"),
        (0, "A2", "2"),
        (0, "B1", "x"),
        (0, "B2", "y"),
        // 0 and FALSE match an empty cell: the first one below the data.
        (1, "A1", "=VLOOKUP(0,Sheet1!A:B,2,FALSE)"),
        (1, "A2", "=MATCH(0,Sheet1!A:A,0)"),
        (1, "A3", "=VLOOKUP(FALSE,Sheet1!A:B,2,FALSE)"),
        (1, "A4", "=ROW(INDEX(Sheet1!A:A,MATCH(0,Sheet1!A:A,0)))"),
        (1, "A5", "=VLOOKUP(5,Sheet1!A:B,2,TRUE)"),
        (1, "A6", "=MATCH(5,Sheet1!A:A,1)"),
        (1, "A7", "=MATCH(-1,Sheet1!A:A,-1)"),
        (1, "A8", "=LOOKUP(5,Sheet1!A:A,Sheet1!B:B)"),
        (1, "A9", "=HLOOKUP(0,Sheet1!1:2,2,FALSE)"),
        (1, "A10", "=MATCH(\"*\",Sheet1!B:B,0)"),
        (1, "A11", "=VLOOKUP(\"\",Sheet1!A:B,2,FALSE)"),
    ]);
    let workbook = model.workbook.clone();
    assert_same_as_naive(&workbook, "empty cells");
    let mut model = Model::from_workbook(workbook, "en").unwrap();
    model.evaluate();
    // B3, empty: 0
    assert_eq!(value(&model, 1, 1, 1), "0");
    // MATCH compares with `values_are_equal`: an empty cell is not 0
    assert_eq!(value(&model, 1, 2, 1), "#N/A");
    assert_eq!(value(&model, 1, 3, 1), "0");
    assert_eq!(value(&model, 1, 4, 1), "#N/A");
    // IronCalc's approximate search over a whole column takes the empty
    // cells below the data as 0 (as `compare_values` does): it lands on the
    // last row. Kept as it is.
    assert_eq!(value(&model, 1, 6, 1), "1048576");
}

#[test]
fn a_spill_during_the_walk_extends_it() {
    // At load the conditional formatting evaluates Calc!A1 outside a pass;
    // its walk of Sheet1!A:A runs the SEQUENCE in A1 on demand, which spills
    // below the used area as it stood when the walk began.
    let mut model = model_with(&[
        (0, "A1", "=SEQUENCE(10)"),
        (1, "A1", "=MATCH(7,Sheet1!A:A,0)"),
        (1, "A2", "=VLOOKUP(9,Sheet1!A:A,1,FALSE)"),
        (1, "A3", "=MATCH(9.5,Sheet1!A:A)"),
        (1, "A4", "=XLOOKUP(8,Sheet1!A:A,Sheet1!A:A)"),
    ]);
    model
        .add_conditional_formatting(
            1,
            "A1:A4",
            CfRuleInput::Formula {
                formula: "=ISERROR(A1)".to_string(),
                format: red(),
                stop_if_true: false,
            },
        )
        .unwrap();
    let workbook = model.workbook.clone();
    assert_same_as_naive(&workbook, "spill during the walk");
    let mut model = Model::from_workbook(workbook, "en").unwrap();
    assert_eq!(value(&model, 1, 1, 1), "7");
    model.evaluate();
    assert_eq!(value(&model, 1, 1, 1), "7");
    assert_eq!(value(&model, 1, 2, 1), "9");
    // See `empty_cells_below_the_data_still_match`.
    assert_eq!(value(&model, 1, 3, 1), "1048576");
    assert_eq!(value(&model, 1, 4, 1), "8");
}

#[test]
fn a_lookup_in_its_own_column_is_a_cycle() {
    let model = model_with(&[
        (0, "A1", "1"),
        (0, "A2", "2"),
        (0, "A5", "=MATCH(2,A:A,0)"),
        (1, "A1", "=VLOOKUP(2,Sheet1!A:A,1,FALSE)"),
        (1, "A2", "=MATCH(2,Sheet1!A:A,0)"),
    ]);
    let workbook = model.workbook.clone();
    assert_same_as_naive(&workbook, "cycle");
    let mut model = Model::from_workbook(workbook, "en").unwrap();
    model.evaluate();
    assert_eq!(value(&model, 0, 5, 1), "#CIRC!");
}

#[test]
fn structured_references_and_whole_columns_in_a_loaded_workbook() {
    let mut model = Model::new_empty("model", "en", "UTC", "en").unwrap();
    model.rename_sheet("Sheet1", "Data").unwrap();
    model.add_sheet("Calc").unwrap();
    for (column, name) in ["k", "v", "w"].iter().enumerate() {
        model
            .set_user_input(0, 1, column as i32 + 1, name.to_string())
            .unwrap();
    }
    for row in 2..=400 {
        model
            .set_user_input(
                0,
                row,
                1,
                if row == 2 {
                    "1".to_string()
                } else {
                    format!("=A{}+1", row - 1)
                },
            )
            .unwrap();
        model.set_user_input(0, row, 2, format!("v{row}")).unwrap();
        model
            .set_user_input(0, row, 3, format!("=A{row}&\"|\"&B{row}"))
            .unwrap();
    }
    add_table(&mut model, 400);
    let mut model = Model::from_workbook(model.workbook.clone(), "en").unwrap();
    for row in 1..=200 {
        model
            .set_user_input(
                1,
                row,
                1,
                format!(
                    "=IF(ISNA(VLOOKUP(ROW($A{row})+3,Data!$A:$C,2,FALSE)),\" \",VLOOKUP(ROW($A{row})+3,Data!$A:$C,2,FALSE))"
                ),
            )
            .unwrap();
        model
            .set_user_input(
                1,
                row,
                2,
                format!("=VLOOKUP(ROW($A{row})+3,TblData[#All],3,FALSE)"),
            )
            .unwrap();
        model
            .set_user_input(1, row, 3, format!("=MATCH({row}*2,TblData[k],1)"))
            .unwrap();
    }
    model
        .add_conditional_formatting(
            1,
            "A1:C200",
            CfRuleInput::Formula {
                formula: "=ISERROR(A1)".to_string(),
                format: red(),
                stop_if_true: false,
            },
        )
        .unwrap();
    let workbook = model.workbook.clone();
    assert_same_as_naive(&workbook, "structured references");
    let mut model = Model::from_workbook(workbook, "en").unwrap();
    model.evaluate();
    assert_eq!(value(&model, 1, 1, 1), "v5");
    assert_eq!(value(&model, 1, 1, 2), "4|v5");
    assert_eq!(value(&model, 1, 10, 3), "20");
}

// ---------------------------------------------------------------------------
// Edits: incremental (check mode) and against naive
// ---------------------------------------------------------------------------

#[test]
fn random_edits_with_whole_column_lookups() {
    let mut rng = Rng(0xdead_beef_cafe_f00d);
    for session in 0..25 {
        let workbook = random_workbook(&mut rng);
        let bytes = Model::from_workbook(workbook, "en").unwrap().to_bytes();
        let mut model = UserModel::from_bytes(&bytes, "en").unwrap();
        model.set_check_incremental(true);
        let rows = 40;
        for _ in 0..20 {
            let row = 1 + rng.below(rows + 10) as i32;
            let column = 1 + rng.below(4) as i32;
            if rng.chance(15) {
                model
                    .range_clear_contents(&crate::expressions::types::Area {
                        sheet: DATA,
                        row,
                        column,
                        width: 1,
                        height: 1,
                    })
                    .unwrap();
            } else {
                let input = data_input(&mut rng, row, false).unwrap_or_default();
                model.set_user_input(DATA, row, column, &input).unwrap();
            }
        }
        // And the final state against a naive full evaluation.
        let workbook = Model::from_bytes(&model.to_bytes(), "en").unwrap().workbook;
        assert_same_as_naive(&workbook, &format!("session {session}"));
    }
}

#[test]
fn lookup_vectors_are_read_once_per_pass() {
    // 2000 exact lookups into a whole column and 2000 approximate ones into
    // a column of 3000 rows: with the cache this is a few milliseconds;
    // without it (and without the clipping) it would read billions of cells.
    let mut model = Model::new_empty("model", "en", "UTC", "en").unwrap();
    for row in 1..=3000 {
        model
            .set_user_input(0, row, 1, (row * 2).to_string())
            .unwrap();
        model.set_user_input(0, row, 2, format!("v{row}")).unwrap();
    }
    for row in 1..=2000 {
        model
            .set_user_input(0, row, 4, format!("=VLOOKUP({},A:B,2,FALSE)", row * 2))
            .unwrap();
        model
            .set_user_input(
                0,
                row,
                5,
                format!("=VLOOKUP({},A1:B3000,2,TRUE)", row * 2 + 1),
            )
            .unwrap();
    }
    let started = std::time::Instant::now();
    model.evaluate();
    let elapsed = started.elapsed();
    assert_eq!(value(&model, 0, 7, 4), "v7");
    assert_eq!(value(&model, 0, 7, 5), "v7");
    assert!(elapsed.as_secs_f64() < 5.0, "4000 lookups took {elapsed:?}");
    let mut counts: HashMap<String, usize> = HashMap::new();
    for row in 1..=2000 {
        *counts.entry(value(&model, 0, row, 4)).or_default() += 1;
    }
    assert_eq!(counts.len(), 2000);
}
