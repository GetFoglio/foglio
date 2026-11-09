#![allow(clippy::unwrap_used)]
#![allow(clippy::panic)]

//! Foglio fork: incremental recalculation.
//!
//! Every test runs with `set_check_incremental(true)`: after each incremental
//! evaluation a full evaluation runs and every cell of every sheet is
//! compared; any difference panics. The randomized test drives a `UserModel`
//! through long random edit sequences over workbooks that mix ranges, chains,
//! cross-sheet references, lookups, conditional aggregates, dynamic arrays,
//! volatile and dynamic references, errors and cycles.

use crate::expressions::types::Area;
use crate::UserModel;

fn new_model<'a>() -> UserModel<'a> {
    let mut model = UserModel::new_empty("model", "en", "UTC", "en").unwrap();
    model.set_check_incremental(true);
    model
}

#[test]
fn edit_recalculates_only_dependents() {
    let mut model = new_model();
    for r in 1..=100 {
        model.set_user_input(0, r, 1, &r.to_string()).unwrap();
        model.set_user_input(0, r, 2, &format!("=A{r}*2")).unwrap();
        model.set_user_input(0, r, 3, &format!("=B{r}+1")).unwrap();
    }
    model.set_user_input(0, 101, 1, "=SUM(A1:A100)").unwrap();
    model.set_user_input(0, 101, 5, "=SUM(B:B)").unwrap();
    // The first evaluation after creation is a full one, then incremental.
    model.set_user_input(0, 50, 1, "1000").unwrap();
    // B50, C50, A101, E101
    assert_eq!(model.last_evaluation_incremental(), Some(4));
    assert_eq!(model.get_formatted_cell_value(0, 50, 3).unwrap(), "2001");
    assert_eq!(model.get_formatted_cell_value(0, 101, 1).unwrap(), "6000");
    // A cell nothing reads
    model.set_user_input(0, 1, 10, "7").unwrap();
    assert_eq!(model.last_evaluation_incremental(), Some(0));
    // Undo is incremental too
    model.undo().unwrap();
    assert_eq!(model.last_evaluation_incremental(), Some(0));
    model.undo().unwrap();
    assert_eq!(model.last_evaluation_incremental(), Some(4));
    assert_eq!(model.get_formatted_cell_value(0, 50, 3).unwrap(), "101");
    model.redo().unwrap();
    assert_eq!(model.get_formatted_cell_value(0, 50, 3).unwrap(), "2001");
    // A structural change is a full evaluation
    model.insert_rows(0, 1, 1).unwrap();
    assert_eq!(model.last_evaluation_incremental(), None);
    assert_eq!(model.get_formatted_cell_value(0, 51, 3).unwrap(), "2001");
    model.set_user_input(0, 51, 1, "1").unwrap();
    assert_eq!(model.last_evaluation_incremental(), Some(4));
    assert_eq!(model.get_formatted_cell_value(0, 51, 3).unwrap(), "3");
}

#[test]
fn chains_and_cross_sheet() {
    let mut model = new_model();
    model.new_sheet().unwrap();
    model.set_user_input(0, 1, 1, "1").unwrap();
    for r in 2..=500 {
        model.set_user_input(0, r, 1, &format!("=A{}+1", r - 1)).unwrap();
    }
    model.set_user_input(1, 1, 1, "=Sheet1!A500*2").unwrap();
    model.set_user_input(1, 2, 1, "=SUM(Sheet1!A1:A500)").unwrap();
    model.set_user_input(0, 1, 1, "10").unwrap();
    assert_eq!(model.last_evaluation_incremental(), Some(501));
    assert_eq!(model.get_formatted_cell_value(1, 1, 1).unwrap(), "1018");
    // Editing in the middle of the chain
    model.set_user_input(0, 250, 1, "0").unwrap();
    assert_eq!(model.get_formatted_cell_value(1, 1, 1).unwrap(), "500");
}

#[test]
fn lookups_volatile_and_arrays() {
    let mut model = new_model();
    for r in 1..=50 {
        model.set_user_input(0, r, 1, &(r * 3).to_string()).unwrap();
        model.set_user_input(0, r, 2, &format!("item{r}")).unwrap();
    }
    model.set_user_input(0, 1, 4, "=VLOOKUP(30,A1:B50,2,FALSE)").unwrap();
    model.set_user_input(0, 2, 4, "=INDEX(B1:B50,MATCH(60,A1:A50,0))").unwrap();
    model.set_user_input(0, 3, 4, "=XLOOKUP(\"ITEM7\",B1:B50,A1:A50)").unwrap();
    model.set_user_input(0, 4, 4, "=INDIRECT(\"A\"&5)").unwrap();
    model.set_user_input(0, 5, 4, "=OFFSET(A1,9,0)").unwrap();
    model.set_user_input(0, 6, 4, "=SUM(A1:INDEX(A:A,3))").unwrap();
    model.set_user_input(0, 7, 4, "=SUMIFS(A1:A50,B1:B50,\"item1*\")").unwrap();
    model.set_user_input(0, 8, 4, "=ROWS(FILTER(A1:A50,A1:A50>100))").unwrap();
    model.set_user_input(0, 1, 6, "=SORT(A1:A5,1,-1)").unwrap();
    model.set_user_input(0, 10, 1, "999").unwrap();
    assert_eq!(model.get_formatted_cell_value(0, 1, 4).unwrap(), "#N/A");
    model.set_user_input(0, 11, 1, "30").unwrap();
    assert_eq!(model.get_formatted_cell_value(0, 1, 4).unwrap(), "item11");
    model.set_user_input(0, 5, 1, "1").unwrap();
    assert_eq!(model.get_formatted_cell_value(0, 4, 4).unwrap(), "1");
    assert_eq!(model.get_formatted_cell_value(0, 5, 4).unwrap(), "999");
    assert_eq!(model.get_formatted_cell_value(0, 1, 6).unwrap(), "12");
    model.set_user_input(0, 2, 1, "1000").unwrap();
    assert_eq!(model.get_formatted_cell_value(0, 1, 6).unwrap(), "1000");
    // typing into the spill area blocks the array; clearing it unblocks it
    model.set_user_input(0, 3, 6, "x").unwrap();
    assert_eq!(model.get_formatted_cell_value(0, 1, 6).unwrap(), "#SPILL!");
    model
        .range_clear_contents(&Area {
            sheet: 0,
            row: 3,
            column: 6,
            width: 1,
            height: 1,
        })
        .unwrap();
    assert_eq!(model.get_formatted_cell_value(0, 1, 6).unwrap(), "1000");
}

// ---------------------------------------------------------------------------
// Randomized edit sequences
// ---------------------------------------------------------------------------

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
    fn pick<'b, T>(&mut self, items: &'b [T]) -> &'b T {
        &items[self.below(items.len() as u64) as usize]
    }
}

const ROWS: i64 = 12;
const COLS: i64 = 6;

fn col(c: i64) -> char {
    (b'A' + (c - 1) as u8) as char
}

/// A random input for the cell in `column` of `sheet`. Formulas only read
/// columns to the left (and Sheet2 also reads Sheet1), so that most workbooks
/// have no cycles; one input in fifty reads anything.
fn random_input(rng: &mut Rng, sheet: u32, column: i32, arrays: bool) -> String {
    let wild = rng.below(50) == 0;
    let max_column = if wild { COLS } else { column as i64 - 1 };
    if max_column < 1 {
        return format!("{}", rng.below(20) as i64 - 5);
    }
    let r = 1 + rng.below(ROWS as u64) as i64;
    let r2 = 1 + rng.below(ROWS as u64) as i64;
    let a = col(1 + rng.below(max_column as u64) as i64);
    let b = col(1 + rng.below(max_column as u64) as i64);
    let last = col(max_column);
    let (other, other_last) = if sheet == 1 && rng.below(2) == 0 {
        ("Sheet1!", 'F')
    } else {
        ("", last)
    };
    let oa = if other.is_empty() { a } else { col(1 + rng.below(COLS as u64) as i64) };
    let mut choice = rng.below(40);
    if !arrays && matches!(choice, 22 | 23 | 24 | 35) {
        choice = 0;
    }
    match choice {
        0..=7 => format!("{}", rng.below(20) as i64 - 5),
        8 => format!("{}.5", rng.below(10)),
        9 => (*rng.pick(&["a", "b", "x1", "X1", "item", "", "TRUE", "FALSE"])).to_string(),
        10 => format!("={a}{r}+1"),
        11 => format!("={other}{oa}{r}*2-{b}{r2}"),
        12 => format!("=SUM({a}1:{b}{r})"),
        13 => format!("=SUM({other}{oa}:{oa})"),
        14 => format!("=IF({a}{r}>3,{b}{r2},\"small\")"),
        15 => format!("=VLOOKUP({a}{r},A1:{last}{ROWS},{},FALSE)", 1 + rng.below(max_column as u64)),
        16 => format!("=INDEX({b}1:{b}{ROWS},MATCH({a}{r},A1:A{ROWS},0))"),
        17 => format!("=SUMIFS({b}1:{b}{ROWS},A1:A{ROWS},\">\"&{a}{r})"),
        18 => format!("=XLOOKUP({a}{r},{other}A1:A{ROWS},{other}{other_last}1:{other_last}{ROWS},\"nf\")"),
        19 => format!("=COUNTIF(A1:{last}{ROWS},\">3\")"),
        20 => format!("=IFERROR(1/{a}{r},-1)"),
        21 => format!("=1/{a}{r}"),
        22 => format!("=FILTER(A1:A{ROWS},A1:A{ROWS}>3,\"none\")"),
        23 => format!("=SORT({a}1:{a}4)"),
        24 => format!("=UNIQUE({b}1:{b}{ROWS})"),
        25 => format!("={a}{r}&\"x\""),
        26 => format!("=MATCH(\"x*\",{a}1:{a}{ROWS},0)"),
        27 => format!("=SUM({other}A1:{other_last}{ROWS})"),
        28 => format!("=INDIRECT(\"{a}\"&{r})"),
        29 => format!("=OFFSET(A1,{},{})", rng.below(5), rng.below(max_column as u64)),
        30 => format!("=SUM(A1:INDEX(A:A,{r}))"),
        31 => format!("=AVERAGE({a}{r}:{b}{r2})"),
        32 => format!("=MAX({other}{oa}1:{oa}{ROWS})+{b}{r}"),
        33 => format!("=HLOOKUP({a}{r},A1:{last}3,2,FALSE)"),
        34 => format!("=ROW()+{a}{r}"),
        35 => format!("=SEQUENCE(2,2,{a}{r})"),
        36 => format!("=LET(x,{a}{r},y,SUM({b}1:{b}{r2}),x+y)"),
        37 => format!("=SUMPRODUCT(A1:A{ROWS},{b}1:{b}{ROWS})"),
        38 => format!("=TEXTJOIN(\",\",TRUE,{a}1:{a}{r})"),
        _ => format!("=ISNUMBER({a}{r})*{b}{r2}"),
    }
}

fn run_random_session(seed: u64, steps: usize, arrays: bool) -> (usize, usize) {
    let mut rng = Rng(seed.wrapping_mul(0x9E37_79B9_7F4A_7C15) | 1);
    let mut model = new_model();
    let mut sheet_count = 1;
    if rng.below(2) == 0 {
        model.new_sheet().unwrap();
        sheet_count = 2;
    }
    // A data table to look things up in.
    for r in 1..=ROWS {
        model
            .set_user_input(0, r as i32, 1, &((r * 7) % 11).to_string())
            .unwrap();
        model
            .set_user_input(0, r as i32, 2, &format!("{}", r * 10))
            .unwrap();
    }
    let mut incremental = 0;
    let mut full = 0;
    let log = std::env::var("INCREMENTAL_LOG").is_ok();
    for _ in 0..steps {
        let sheet = rng.below(sheet_count as u64) as u32;
        let row = 1 + rng.below(ROWS as u64) as i32;
        let column = 1 + rng.below(COLS as u64) as i32;
        match rng.below(100) {
            0..=74 => {
                let input = random_input(&mut rng, sheet, column, arrays);
                if log {
                    eprintln!("set {sheet} R{row}C{column} {input}");
                }
                let _ = model.set_user_input(sheet, row, column, &input);
            }
            75..=79 => {
                if log {
                    eprintln!("clear {sheet} R{row}C{column}");
                }
                let _ = model.range_clear_contents(&Area {
                    sheet,
                    row,
                    column,
                    width: 1 + rng.below(2) as i32,
                    height: 1 + rng.below(3) as i32,
                });
            }
            80..=85 => {
                if log {
                    eprintln!("undo");
                }
                let _ = model.undo();
            }
            86..=89 => {
                if log {
                    eprintln!("redo");
                }
                let _ = model.redo();
            }
            90..=91 => {
                let _ = model.insert_rows(sheet, row, 1);
            }
            92..=93 => {
                let _ = model.delete_rows(sheet, row, 1);
            }
            _ => {
                // A burst of edits with the evaluation paused, as in a paste.
                model.pause_evaluation();
                for _ in 0..1 + rng.below(4) {
                    let r = 1 + rng.below(ROWS as u64) as i32;
                    let c = 1 + rng.below(COLS as u64) as i32;
                    let input = random_input(&mut rng, sheet, c, arrays);
                    let _ = model.set_user_input(sheet, r, c, &input);
                }
                model.resume_evaluation();
                model.evaluate();
            }
        }
        match model.last_evaluation_incremental() {
            Some(_) => incremental += 1,
            None => {
                full += 1;
                if std::env::var("SHOW_FULL_REASONS").is_ok() {
                    eprintln!("full: {}", model.last_full_evaluation_reason());
                }
            }
        }
    }
    (incremental, full)
}

#[test]
fn random_edit_sequences_match_full_evaluation() {
    let mut incremental = 0;
    let mut full = 0;
    for seed in 1..=200u64 {
        let (i, f) = std::panic::catch_unwind(|| run_random_session(seed, 60, false))
            .unwrap_or_else(|_| panic!("seed {seed} failed"));
        incremental += i;
        full += f;
    }
    // The incremental path must actually be exercised.
    assert!(incremental > full, "incremental: {incremental}, full: {full}");
}

#[test]
fn random_edit_sequences_with_dynamic_arrays_match_full_evaluation() {
    let mut incremental = 0;
    let mut full = 0;
    for seed in 1000..=1200u64 {
        let (i, f) = std::panic::catch_unwind(|| run_random_session(seed, 60, true))
            .unwrap_or_else(|_| panic!("seed {seed} failed"));
        incremental += i;
        full += f;
    }
    // Edits near spilled arrays fall back to a full evaluation; the others
    // must still be incremental.
    assert!(incremental * 10 > full, "incremental: {incremental}, full: {full}");
}

/// Replays one seed with a log of the edits: `INCREMENTAL_SEED=17
/// INCREMENTAL_ARRAYS=1 INCREMENTAL_LOG=1 cargo test -- replay_one_seed --nocapture`
#[test]
fn replay_one_seed() {
    if let Ok(seed) = std::env::var("INCREMENTAL_SEED") {
        let arrays = std::env::var("INCREMENTAL_ARRAYS").is_ok();
        run_random_session(seed.parse().unwrap(), 60, arrays);
    }
}

/// Many more random sessions (about a minute in release mode):
/// `cargo test --release -- --ignored many_random_sessions`
#[test]
#[ignore]
fn many_random_sessions() {
    let mut incremental = 0;
    let mut full = 0;
    for seed in 10_000..12_000u64 {
        let arrays = seed % 2 == 0;
        let (i, f) = std::panic::catch_unwind(|| run_random_session(seed, 120, arrays))
            .unwrap_or_else(|_| panic!("seed {seed} failed"));
        incremental += i;
        full += f;
    }
    eprintln!("incremental evaluations: {incremental}, full: {full}");
}
