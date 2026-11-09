//! Performance benchmark of IronCalc for Foglio-sized workbooks.
//!
//! Run: `cargo run --release --bin perf`            (all sizes, each in a child process)
//!      `IRONCALC_CHECK_INCREMENTAL=1 cargo run --release --bin perf -- 10000`
//!                                                   (verify every incremental edit)
//!      `cargo run --release --bin perf -- 100000`  (one size, in-process)
//!      `cargo run --release --bin perf -- 100000 novlookup`
//!
//! Each size runs in its own child process so that peak RSS (getrusage
//! ru_maxrss) is per-N and not polluted by earlier, larger runs.

use std::time::{Duration, Instant};

use ironcalc::base::{Model, UserModel};
use ironcalc::export::save_to_xlsx;
use ironcalc::import::load_from_xlsx;

#[repr(C)]
struct RUsage {
    ru_utime: [i64; 2],
    ru_stime: [i64; 2],
    ru_maxrss: i64,
    rest: [i64; 13],
}

extern "C" {
    fn getrusage(who: i32, usage: *mut RUsage) -> i32;
}

/// Peak resident set size of this process in MiB (macOS reports bytes, Linux KiB).
fn peak_rss_mib() -> f64 {
    let mut u = RUsage { ru_utime: [0; 2], ru_stime: [0; 2], ru_maxrss: 0, rest: [0; 13] };
    unsafe { getrusage(0, &mut u) };
    if cfg!(target_os = "macos") {
        u.ru_maxrss as f64 / 1024.0 / 1024.0
    } else {
        u.ru_maxrss as f64 / 1024.0
    }
}

fn ms(d: Duration) -> f64 {
    d.as_secs_f64() * 1000.0
}

fn median(v: &mut [f64]) -> f64 {
    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
    v[v.len() / 2]
}

const VLOOKUP_ROWS: i32 = 1000;

/// Builds the benchmark workbook. Columns:
///   A = r, B = (r*37 % 100) + 0.5, C = A*B, D = C*1.22, E = IF(D>100,"a","b")
///   F (rows 1..1000) = VLOOKUP(key, $A$1:$B$N, 2, FALSE) with scattered keys
/// Summary row N+2: SUM(A), SUM(B), SUM(C), AVERAGE(D), COUNTIF(E,"a"), SUM(F)
fn build(n: i32, with_vlookup: bool) -> Model<'static> {
    let mut m = Model::new_empty("bench", "en", "UTC", "en").unwrap();
    for r in 1..=n {
        m.set_user_input(0, r, 1, r.to_string()).unwrap();
        m.set_user_input(0, r, 2, format!("{}.5", (r * 37) % 100)).unwrap();
        m.set_user_input(0, r, 3, format!("=A{r}*B{r}")).unwrap();
        m.set_user_input(0, r, 4, format!("=C{r}*1.22")).unwrap();
        m.set_user_input(0, r, 5, format!("=IF(D{r}>100,\"a\",\"b\")")).unwrap();
        if with_vlookup && r <= VLOOKUP_ROWS {
            let key = ((r as i64 * 7919) % n as i64) + 1;
            m.set_user_input(0, r, 6, format!("=VLOOKUP({key},$A$1:$B${n},2,FALSE)")).unwrap();
        }
    }
    let s = n + 2;
    m.set_user_input(0, s, 1, format!("=SUM(A1:A{n})")).unwrap();
    m.set_user_input(0, s, 2, format!("=SUM(B1:B{n})")).unwrap();
    m.set_user_input(0, s, 3, format!("=SUM(C1:C{n})")).unwrap();
    m.set_user_input(0, s, 4, format!("=AVERAGE(D1:D{n})")).unwrap();
    m.set_user_input(0, s, 5, format!("=COUNTIF(E1:E{n},\"a\")")).unwrap();
    if with_vlookup {
        m.set_user_input(0, s, 6, format!("=SUM(F1:F{VLOOKUP_ROWS})")).unwrap();
    }
    m
}

fn run_one(n: i32, with_vlookup: bool) {
    let tmp = std::env::temp_dir().join(format!("foglio_bench_{n}_{}.xlsx", std::process::id()));
    let path = tmp.to_string_lossy().to_string();
    let _ = std::fs::remove_file(&path);

    let t = Instant::now();
    let mut model = build(n, with_vlookup);
    let build_ms = ms(t.elapsed());

    let t = Instant::now();
    model.evaluate();
    let eval_ms = ms(t.elapsed());
    let rss_after_eval = peak_rss_mib();

    let s = n + 2;

    // repetitions of each edit (median)
    let reps = 5;

    // second (warm) evaluation
    let t = Instant::now();
    model.evaluate();
    let eval2_ms = ms(t.elapsed());

    // what the user feels after typing a value: UserModel::set_user_input.
    // The first evaluation of a UserModel is a full one (it does not know what
    // happened to the model before); the second builds the dependency index
    // (Foglio's IronCalc fork). Both are reported separately.
    let mut user = UserModel::from_model(model);
    let check = std::env::var("IRONCALC_CHECK_INCREMENTAL").is_ok();
    let t = Instant::now();
    user.set_user_input(0, n / 3, 1, "999").unwrap();
    let first_edit_ms = ms(t.elapsed());
    let t = Instant::now();
    user.set_user_input(0, n / 3 + 1, 1, "998").unwrap();
    let index_edit_ms = ms(t.elapsed());
    let mut edit = Vec::new();
    let mut ran = None;
    for i in 0..reps {
        let row = n / 2 + i;
        let t = Instant::now();
        user.set_user_input(0, row, 1, &format!("{}", 1000 + i)).unwrap();
        edit.push(ms(t.elapsed()));
        ran = user.last_evaluation_incremental();
    }
    let edit_ms = median(&mut edit);
    // edit of a cell nothing depends on
    let mut edit_iso = Vec::new();
    for i in 0..reps {
        let t = Instant::now();
        user.set_user_input(0, 1, 20, &format!("{i}")).unwrap();
        edit_iso.push(ms(t.elapsed()));
    }
    let edit_iso_ms = median(&mut edit_iso);
    // a new formula (adds to the dependency index)
    let mut edit_formula = Vec::new();
    for i in 0..reps {
        let row = n / 2 + i;
        let t = Instant::now();
        user.set_user_input(0, row, 4, &format!("=C{row}*1.25+{i}")).unwrap();
        edit_formula.push(ms(t.elapsed()));
    }
    let edit_formula_ms = median(&mut edit_formula);
    // undo of a value edit
    let t = Instant::now();
    user.undo().unwrap();
    let undo_ms = ms(t.elapsed());
    // the same edit with evaluation paused = cost of the edit itself
    user.pause_evaluation();
    let mut edit_paused = Vec::new();
    for i in 0..reps {
        let t = Instant::now();
        user.set_user_input(0, 2, 20, &format!("{i}")).unwrap();
        edit_paused.push(ms(t.elapsed()));
    }
    let edit_paused_ms = median(&mut edit_paused);
    user.resume_evaluation();
    // a full recalculation on demand
    let t = Instant::now();
    user.evaluate_full();
    let full_ms = ms(t.elapsed());
    let sum_after_edits = user.get_model().get_cell_value_by_index(0, s, 3).unwrap();
    // includes the dependency index (peak so far; save and load come after)
    let rss_after_edits = peak_rss_mib();
    // what is saved (after the edits) must come back after load + evaluate
    let sum_a = user.get_model().get_cell_value_by_index(0, s, 1).unwrap();

    // save / load
    let t = Instant::now();
    save_to_xlsx(user.get_model(), &path).unwrap();
    let save_ms = ms(t.elapsed());
    let size_mb = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0) as f64 / 1e6;

    // internal binary format, for comparison
    let t = Instant::now();
    let bytes = user.get_model().to_bytes();
    let to_bytes_ms = ms(t.elapsed());
    let icalc_mb = bytes.len() as f64 / 1e6;
    drop(bytes);

    drop(user);
    let _ = check;

    let t = Instant::now();
    let mut loaded = load_from_xlsx(&path, "en", "UTC", "en").unwrap();
    let load_ms = ms(t.elapsed());
    let t = Instant::now();
    loaded.evaluate();
    let load_eval_ms = ms(t.elapsed());
    let sum_a_loaded = loaded.get_cell_value_by_index(0, s, 1).unwrap();
    drop(loaded);
    // PERF_KEEP_XLSX=/some/file.xlsx keeps the generated workbook (to time opening it in an app).
    if let Ok(keep) = std::env::var("PERF_KEEP_XLSX") { let _ = std::fs::copy(&path, keep); }
    let _ = std::fs::remove_file(&path);

    let peak = peak_rss_mib();
    println!(
        "RESULT n={n} vlookup={with_vlookup} build_ms={build_ms:.1} eval_ms={eval_ms:.1} eval2_ms={eval2_ms:.1} \
first_edit_ms={first_edit_ms:.1} index_edit_ms={index_edit_ms:.1} edit_ms={edit_ms:.3} edit_ran={ran:?} \
edit_isolated_ms={edit_iso_ms:.3} edit_formula_ms={edit_formula_ms:.3} undo_ms={undo_ms:.3} \
edit_paused_ms={edit_paused_ms:.3} full_recalc_ms={full_ms:.1} sum_c_after_edits={sum_after_edits:?} \
save_ms={save_ms:.1} xlsx_mb={size_mb:.2} load_ms={load_ms:.1} load_eval_ms={load_eval_ms:.1} \
to_bytes_ms={to_bytes_ms:.1} icalc_mb={icalc_mb:.2} rss_after_eval_mib={rss_after_eval:.1} rss_after_edits_mib={rss_after_edits:.1} peak_rss_mib={peak:.1} \
check_sum={sum_a:?}/{sum_a_loaded:?}"
    );
}

/// Cost of 1000 lookups over a 10k-row table, per lookup function.
fn lookups() {
    let n = 10_000;
    let forms: &[(&str, &str)] = &[
        ("VLOOKUP exact", "=VLOOKUP({k},$A$1:$B${n},2,FALSE)"),
        ("VLOOKUP sorted", "=VLOOKUP({k},$A$1:$B${n},2,TRUE)"),
        ("INDEX/MATCH exact", "=INDEX($B$1:$B${n},MATCH({k},$A$1:$A${n},0))"),
        ("XLOOKUP exact", "=XLOOKUP({k},$A$1:$A${n},$B$1:$B${n})"),
        ("XLOOKUP binary", "=XLOOKUP({k},$A$1:$A${n},$B$1:$B${n},,0,2)"),
        ("SUMIF", "=SUMIF($A$1:$A${n},{k},$B$1:$B${n})"),
        ("SUM(range)", "=SUM($A$1:$A${n})+{k}"),
    ];
    for (name, f) in forms {
        let mut m = Model::new_empty("bench", "en", "UTC", "en").unwrap();
        for r in 1..=n {
            m.set_user_input(0, r, 1, r.to_string()).unwrap();
            m.set_user_input(0, r, 2, (r * 2).to_string()).unwrap();
        }
        for r in 1..=1000 {
            let k = ((r as i64 * 7919) % n as i64) + 1;
            let formula = f.replace("{k}", &k.to_string()).replace("{n}", &n.to_string());
            m.set_user_input(0, r, 4, formula).unwrap();
        }
        let t = Instant::now();
        m.evaluate();
        let e = ms(t.elapsed());
        println!("LOOKUP {name:<18} 1000 formulas over {n} rows: eval {e:.1} ms ({:.1} us/formula) check={:?}", e, m.get_cell_value_by_index(0, 1, 4).unwrap());
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.iter().any(|a| a == "lookups") {
        lookups();
        return;
    }
    if args.len() > 1 {
        let n: i32 = args[1].parse().expect("N");
        let with_vlookup = !args.iter().any(|a| a == "novlookup");
        run_one(n, with_vlookup);
        return;
    }
    let exe = std::env::current_exe().unwrap();
    for with_vlookup in [false, true] {
        for n in [10_000, 100_000, 300_000] {
            let mut cmd = std::process::Command::new(&exe);
            cmd.arg(n.to_string());
            if !with_vlookup {
                cmd.arg("novlookup");
            }
            let out = cmd.output().unwrap();
            print!("{}", String::from_utf8_lossy(&out.stdout));
            eprint!("{}", String::from_utf8_lossy(&out.stderr));
        }
    }
}
