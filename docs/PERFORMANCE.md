# IronCalc performance for Foglio

Foglio uses a patched fork of IronCalc 0.9.1 in `third_party/` (see
`third_party/README.md` for every change). This document has the measurements
before and after the fork's performance work, and what is left.

Measured with `bench/` on this Mac (Apple Silicon, release build, single thread):

```sh
cd bench
cargo run --release --bin perf                 # all sizes, each in its own child process
cargo run --release --bin perf -- 100000       # one size (add `novlookup` to drop column F)
cargo run --release --bin perf -- lookups      # cost per lookup function
IRONCALC_CHECK_INCREMENTAL=1 cargo run --release --bin perf -- 10000   # verify each edit
```

## Workbook

N rows of
`A = r`, `B = (r·37 mod 100)+0.5`, `C = A*B`, `D = C*1.22`, `E = IF(D>100,"a","b")`
(3 formulas per row), a summary row `SUM(A) SUM(B) SUM(C) AVERAGE(D) COUNTIF(E,"a")`,
and — in the "+VLOOKUP" variant — column F on rows 1..1000:
`=VLOOKUP(key,$A$1:$B$N,2,FALSE)` with scattered keys (plus `SUM(F1:F1000)`).

* **evaluate** = `Model::evaluate()`, a full recalculation.
* **edit** = `UserModel::set_user_input(0, N/2+i, 1, "…")` — what the user waits
  for after pressing Enter, evaluation included (median of 5). It changes a
  cell that 3 row formulas, the summary row and (in the +VLOOKUP variant) all
  1000 VLOOKUPs depend on: the VLOOKUP table contains it.
* **isolated edit** = typing into Z1, a cell nothing reads.
* **formula edit** = replacing `D(N/2)` with a new formula; **undo** = undo of
  a value edit.
* **first edit** = the first edit after `UserModel::from_model` (a full
  evaluation: the UserModel does not know what was done to the model
  before); **2nd edit** = the next one, which also builds the dependency index.
* **RSS** = `getrusage` `ru_maxrss` (peak so far) after the first evaluation,
  and after the edits (includes the dependency index).

## Results: before → after

Before = IronCalc 0.9.1 as published; after = Foglio's fork (this repository).

| N rows (formula cells) | evaluate | **edit (felt)** | isolated edit | formula edit, undo | after: first / 2nd edit | after: RSS after eval → after edits |
|---|---|---|---|---|---|---|
| 10k (30k) | 7.9 → **4.9 ms** | 7.1 → **1.0 ms** | 7.1 → 0.001 ms | 7 → 0.9 ms | 4.0 / 2.5 ms | 16 → 18 MB |
| 100k (300k) | 88 → **55 ms** | 82 → **12 ms** | 84 → 0.001 ms | 82 → 8 ms | 51 / 30 ms | 79 → 102 MB |
| 300k (900k) | 287 → **183 ms** | 280 → **36 ms** | 277 → 0.002 ms | 280 → 25 ms | 186 / 98 ms | 203 → 281 MB |
| 10k + 1000 VLOOKUP | 1.83 s → **5.3 ms** | 1.86 s → **1.5 ms** | 1.79 s → 0.001 ms | 1.9 s → 0.8 ms | 4.5 / 3.2 ms | 17 → 19 MB |
| 100k + 1000 VLOOKUP | 18.6 s → **62 ms** | 18.6 s → **16 ms** | 18.1 s → 0.001 ms | 18.6 s → 8 ms | 56 / 34 ms | 82 → 107 MB |
| 300k + 1000 VLOOKUP | 53.5 s → **197 ms** | 53.5 s → **49 ms** | 53.5 s → 0.002 ms | 53.5 s → 26 ms | 195 / 112 ms | 212 → 292 MB |

(Before = a fresh run of the same harness on the vendored, unmodified 0.9.1,
matching the original audit within noise. Before, every edit — formula edit
and undo included — was a full evaluation, so those columns repeat the edit
cost.)
Unchanged: build via `Model::set_user_input` ≈ 6.7 µs/row, xlsx save
1.4 s and load 2.3 s at 300k rows, `to_bytes` 9 ms.

### Lookup cost (1000 formulas over a 10k-row table, full evaluation, `perf -- lookups`)

| Formula | before | after |
|---|---|---|
| `VLOOKUP(k,A:B,2,FALSE)` | 1703 ms | **1.3 ms** |
| `XLOOKUP(k,A,B)` (exact) | 1614 ms | **0.8 ms** |
| `INDEX(B,MATCH(k,A,0))` | 92 ms | **0.9 ms** |
| `VLOOKUP(k,A:B,2,TRUE)` (sorted) | 91 ms | 88 ms |
| `XLOOKUP(…,,0,2)` (binary) | 84 ms | 81 ms |
| `SUMIF(A,k,B)` | 95 ms | 90 ms |
| `SUM(A)` (baseline: reading 10k cells) | 68 ms | 66 ms |

## What changed (in `third_party/ironcalc_base`)

1. **Number comparison** (`functions/util.rs::compare_values`): exact
   equality first, numbers more than 1e-12 apart (relative; and 1e-15
   absolute) are ordered directly; only nearly equal numbers are rounded to 15
   significant digits. `number_format::to_excel_precision` returns integers
   below 1e15 and numbers whose shortest representation has ≤ 15 digits
   unchanged, without `format!` + `parse`. Same results; this alone made exact
   VLOOKUP/XLOOKUP ~20× faster and a full evaluation ~35 % faster (`IF(D>100)`
   compares numbers too).
2. **Exact-match lookup index** (`functions/lookup_cache.rs`): the first
   VLOOKUP/HLOOKUP(FALSE), MATCH(…,0) or exact XLOOKUP into a vector in an
   evaluation pass reads it once — exactly as the linear search does, so
   formulas in it are evaluated and cycles found the same way — and hashes it;
   later lookups are a probe. Used only where the hash gives the linear
   search's answer (numbers of magnitude ≥ 1, text without wildcards); a
   spill into an indexed vector reruns the pass without it. This replaced the
   "stop at the first match" idea: stopping early changes which cells a
   lookup reads, and with it cycle detection and spill-conflict detection.
3. **Incremental recalculation** (`dependencies.rs`, `evaluation/incremental.rs`,
   wired in `user_model/common.rs`), following the plan of the original audit:
   * a reverse-dependency index built from the parsed formulas with relative
     references resolved per cell — single cells per column sorted by row,
     ranges as rectangles (`A:A` is one entry), volatile formulas
     (NOW/TODAY/RAND/RANDBETWEEN/RANDARRAY/INDIRECT/OFFSET/CELL/INFO/SHEET(S),
     defined names, tables, `A1:INDEX(…)`, `A1#`, LAMBDAs in names) always
     dirty. Built lazily on the first incremental evaluation (≈ 60 ms at
     900k formulas, ≈ 90 B per formula), updated per edited cell afterwards.
   * `UserModel` reports `set_user_input`, `range_clear_contents` and undo/redo
     of content edits as changed positions; every other operation makes the
     next evaluation a full one (and drops the index).
   * the dirty formulas (changed formulas, everything reachable from the
     changed cells, volatile formulas and their dependents) run in the order a
     full pass would; every other formula is read as its stored value.
   * full evaluation instead when it cannot be shown identical: the edit
     touches an array area (spill cells, CSE areas, spilling anchors), a
     dynamic array is `#SPILL!`/`#CIRC!`, a dirty anchor would change its
     spill size, the workbook has circular references, the dirty set is more
     than half of the formulas. Spilling arrays elsewhere in the workbook and
     single-value dynamic formulas (INDEX/MATCH, LET, INDIRECT — IronCalc
     parses them as dynamic arrays) are handled incrementally.
   * `UserModel::evaluate()` is incremental too (so `pause_evaluation` /
     batch / `resume_evaluation` + `evaluate()` stays cheap);
     `UserModel::evaluate_full()` recalculates everything.

### How correctness is verified

* **Check mode**: with `IRONCALC_CHECK_INCREMENTAL=1` (or
  `UserModel::set_check_incremental(true)`) every incremental evaluation is
  followed by a full one and all cells — values, error origins and messages,
  spill cells — and HYPERLINK links are compared; a difference panics.
* `third_party/ironcalc_base/src/test/test_incremental.rs` (check mode on):
  targeted tests plus randomized edit sequences on two-sheet workbooks mixing
  SUM ranges, whole columns, chains, cross-sheet references, IF, VLOOKUP,
  HLOOKUP, INDEX/MATCH, XLOOKUP, SUMIFS, COUNTIF, SUMPRODUCT, TEXTJOIN, LET,
  FILTER/SORT/UNIQUE/SEQUENCE spills, INDIRECT/OFFSET, `A1:INDEX(…)`, errors
  and (rarely) cycles, with clears, undo/redo, row insert/delete and paused
  batches. Default run: 400 sessions × 60 edits; `cargo test --release --
  --ignored many_random_sessions`: 2000 × 120 edits (≈ 132 000 incremental
  evaluations checked, 0 differences), also with `IRONCALC_MAX_DEPTH=1`
  (every recursion unwinds and replays).
* `third_party/ironcalc/tests/incremental_corpus.rs`: 40 random edits on each
  of the 242 workbooks of upstream's Excel-made xlsx corpus (≈ 7 500
  incremental evaluations checked, 0 differences).
* The whole upstream suite (2 771 tests) passes in check mode; the only
  failure is one that also fails on the published 0.9.1.
* The check mode found three real problems during development, all fixed
  before shipping: a typed value that blocks a spill changes the anchor
  through `Model::set_user_input` (array areas are now recorded at every
  full evaluation); new anchors must be ordered like `sync_anchor_order`
  would; with circular references IronCalc's verdict depends on where the
  recursion entered the cycle (such workbooks now always evaluate fully).

## Answers (updated)

### 1. Does `UserModel::set_user_input` re-evaluate the whole workbook?
**No longer**, except in the fall-back cases above. Before, every edit ran
`Model::evaluate()` over every formula of every sheet. Now an edit runs the
formulas that depend on it: 7 formulas (3 in the row + summary row) for the
benchmark, 1008 with the VLOOKUP column. The remaining cost of the 300k-row
edit (36 ms) is the summary formulas re-reading 300k cells each
(`SUM(C1:C300000)`, `COUNTIF(E…)`), not bookkeeping: an edit nothing reads
takes 1 µs.

### 2. When does a single edit exceed 100 ms?
* Edits that stay incremental: when the formulas depending on the edited cell
  read more than ≈ 5–10 M cells (e.g. 30 aggregates over a 300k-row column).
  Workbook size alone no longer matters.
* Full evaluations (structural changes, paste via clipboard, sort, fill,
  defined names, edits near spills, workbooks with circular references) cost
  ≈ 0.2 µs per formula: ~100 ms at ≈ 500k formula cells (≈ 160k rows of the
  benchmark). Exact lookups no longer multiply that (1000 VLOOKUPs into 300k
  rows add 11 ms, not 53 s).
* The first edit after opening a file is a full evaluation (185 ms at 300k
  rows) and the second one builds the index (≈ +60 ms); from the third on
  edits are incremental.

### 3. What does IronCalc already cache?
Parsed ASTs (shared between cells with the same R1C1 formula), formula
positions per sheet, the dynamic-array anchor order; now also the dependency
index (across evaluations) and the lookup index (per evaluation pass).

## Notes for `core/` and the app

* No code change is required: the C ABI compiles unchanged and every edit
  that goes through `UserModel` is incremental where possible, including
  `foglio_paste_tsv` and find/replace (pause → `set_user_input`… → resume →
  `evaluate()`).
* `UserModel::evaluate()` is now "recalculate what is pending" (plus the
  volatile formulas), so `foglio_evaluate_us` measures that, not a full
  recalculation. For a "Recalculate all" command (Excel's Ctrl+Alt+F9) or a
  timing of a full recalculation, call the new `UserModel::evaluate_full()`.
* Debugging: run the app with `IRONCALC_CHECK_INCREMENTAL=1` to verify every
  incremental evaluation against a full one (panics on a difference; slow).
  `UserModel::last_evaluation_incremental()` / `last_full_evaluation_reason()`
  tell what the last evaluation did.

## What is left (ideas, not done)

* **Aggregates over huge ranges**: `SUM(C1:C300000)` re-reads 300k cells on
  every edit of C (≈ 5 ms each). Incremental aggregates (keep the sum, apply
  the delta) would make that O(1), but only for SUM/COUNT-like functions and
  with care for errors and precision.
* **Structural edits** (insert/delete rows and columns, move, sort, paste
  through the clipboard API) are full evaluations and drop the index; they
  could shift the index and report the moved/pasted cells instead.
* **Foglio-side**: run evaluation off the main thread and coalesce edits
  (still useful for structural edits and for the first edit after load); save
  autosave/crash-recovery with `to_bytes()` (9 ms vs 1.4 s xlsx at 300k rows).
* Memory: the index costs ≈ 90 B per formula (≈ 80 MB at 900k formulas),
  mostly the per-cell hash map of indexed formulas; recording the replaced
  formula at edit time instead would remove it.
