# IronCalc 0.9.1 performance for Foglio

Measured with `bench/` on this Mac (Apple Silicon, release build, single thread):

```sh
cd bench
cargo run --release --bin perf                 # all sizes, each in its own child process
cargo run --release --bin perf -- 100000       # one size (add `novlookup` to drop column F)
cargo run --release --bin perf -- lookups      # cost per lookup function
```

## Workbook

N rows of
`A = r`, `B = (r·37 mod 100)+0.5`, `C = A*B`, `D = C*1.22`, `E = IF(D>100,"a","b")`
(3 formulas per row), a summary row `SUM(A) SUM(B) SUM(C) AVERAGE(D) COUNTIF(E,"a")`,
and — in the "+VLOOKUP" variant — column F on rows 1..1000:
`=VLOOKUP(key,$A$1:$B$N,2,FALSE)` with scattered keys (plus `SUM(F1:F1000)`).

* **build** = 5N (or 5N+1000) calls to `Model::set_user_input` (no evaluation)
* **evaluate** = `Model::evaluate()` (first / second run)
* **edit** = one `UserModel::set_user_input(0, N/2, 1, "1000")` — what the user waits for after
  pressing Enter, including the automatic full re-evaluation (median of 5; 1 run for the
  slow VLOOKUP sizes). "edit, isolated cell" = typing into Z1, a cell nothing reads.
  With `pause_evaluation()` the same call takes ≈ 1 µs, i.e. the edit itself is free —
  **100 % of the latency is the full recalculation.**
* **RSS** = `getrusage` `ru_maxrss` in the child process for that N: after the first evaluate,
  and the peak of the whole run (which includes save + load).

## Results

| N rows (formula cells) | build | evaluate | **edit (felt)** | edit, isolated cell | save xlsx | xlsx size | load xlsx | eval after load | RSS after eval | peak RSS (incl. save/load) |
|---|---|---|---|---|---|---|---|---|---|---|
| 10k (30k) | 68 ms | 7.9 ms | **7.1 ms** | 7.0 ms | 44 ms | 0.42 MB | 77 ms | 7.5 ms | 16 MB | 32 MB |
| 100k (300k) | 681 ms | 99 ms | **91 ms** | 93 ms | 477 ms | 4.1 MB | 789 ms | 95 ms | 79 MB | 243 MB |
| 300k (900k) | 2.07 s | 291 ms | **272 ms** | 276 ms | 1.43 s | 12.4 MB | 2.34 s | 281 ms | 202 MB | 592 MB |
| 10k + 1000 VLOOKUP | 69 ms | 1.65 s | **1.64 s** | 1.70 s | 46 ms | 0.43 MB | 85 ms | 1.87 s | 17 MB | 30 MB |
| 100k + 1000 VLOOKUP | 980 ms | 18.7 s | **19.6 s** | 18.8 s | 545 ms | 4.1 MB | 795 ms | 24.8 s | 79 MB | 189 MB |
| 300k + 1000 VLOOKUP | 3.55 s | 62.0 s | **54.1 s** | 54.9 s | 1.48 s | 12.4 MB | 2.97 s | 61.9 s | 203 MB | 552 MB |

The internal binary format (`Model::to_bytes`, bitcode) is ~100× faster than xlsx to
write: 9 ms / 12 MB at 300k rows (vs 1.43 s for xlsx).

### Lookup cost (1000 formulas over a 10k-row table, `perf -- lookups`)

| Formula | evaluate | per formula |
|---|---|---|
| `VLOOKUP(k,A:B,2,FALSE)` | 2001 ms | 2.0 ms |
| `XLOOKUP(k,A,B)` (exact) | 2062 ms | 2.1 ms |
| `INDEX(B,MATCH(k,A,0))` | 116 ms | 0.12 ms |
| `VLOOKUP(k,A:B,2,TRUE)` (sorted) | 111 ms | 0.11 ms |
| `XLOOKUP(…,,0,2)` (binary) | 109 ms | 0.11 ms |
| `SUMIF(A,k,B)` | 131 ms | 0.13 ms |
| `SUM(A)` (baseline: just reading 10k cells) | 93 ms | 0.09 ms |

Every function that takes a range reads **all** of it (≈ 9 ns/cell — the range is
materialised into a `Vec<CalcResult>` through `evaluate_cell` for each formula), and exact
VLOOKUP/XLOOKUP is another **20× slower** on top of that: `functions/util.rs::compare_values`
calls `number_format::to_excel_precision` on *both* operands for every compared cell, and
that function rounds via `format!("{:.*e}")` + `parse::<f64>()` — two string round-trips
per cell (~200 ns). MATCH(…,0) uses a different comparison and is 17× faster.

## Answers

### 1. Does `UserModel::set_user_input` re-evaluate the whole workbook?
**Yes.** `UserModel::set_user_input` (`ironcalc_base/src/user_model/common.rs:436`) calls
`evaluate_if_not_paused()` (`:2296`) → `Model::evaluate()` (`src/evaluation.rs:506`), which runs
`run_pass` over **every formula cell of every sheet** (`formula_positions()`) and then
`evaluate_conditional_formatting()` (also full). There is no dependency graph (IronCalc
issue #849): the measured latency for an edit of a cell that nothing depends on (column
"isolated") is identical to editing a cell that feeds 3 formulas plus the summary row.

### 2. When does a single edit exceed 100 ms?
Cost is linear: ≈ **0.30 µs per simple formula cell** (+ the range reads).
* Simple formulas only: ~**330k formula cells ≈ 110k rows** of this workbook (91 ms at 100k
  rows, 272 ms at 300k).
* Any formula that scans a range scales with *formulas × range length*: with 1000 exact
  VLOOKUPs into the table the 100 ms budget is blown already at **~1k rows**
  (1.6 s at 10k rows, ~19 s at 100k, ~55 s at 300k).

Other observations: build via `set_user_input` ≈ 1.4 µs/cell; xlsx load ≈ 7.8 µs/row and
dominates peak memory (≈ 3× the in-memory model at 300k rows: 592 MB peak vs 202 MB).

### 3. What does IronCalc already cache?
* **Parsed ASTs, shared:** `Model::parsed_formulas: Vec<Vec<(Arc<Node>, StaticResult)>>`
  (`src/model.rs:200`), and formulas that are the same in R1C1 form (`=A1*B1`, `=A2*B2`, …)
  share one entry (`shared_formula_lookup`). Nothing is re-parsed on evaluate.
* **Only formula cells are walked**, and sheets without formulas are skipped
  (`sheets_with_formulas`, `formula_positions` in `evaluation.rs`).
* Per pass, each formula is evaluated once (`Evaluation::cells` state map with a custom
  fast hasher), dynamic-array anchor order is remembered across evaluations.
* The pass already **records reads** (`Evaluation::seen`, `seen_ranges`, `record_seen`),
  but only "first root that saw this position empty/occupied", used to restart passes
  when a spill contradicts a read — not a usable reverse-dependency index.

So the "cheap tricks" (AST caching, only visiting formulas) are already in; what is left
is to visit *fewer* formulas.

### 4. Incremental recalculation — assessment and recommendation

**Difficulty: medium-high inside IronCalc (≈ 800–1200 LOC + tests), but well-contained.**

Plan (in a fork of `ironcalc_base`, ideally upstreamed):

1. **Reverse-dependency index** — new `src/dependencies.rs`:
   `cell_deps: HashMap<CellKey, Vec<CellKey>, KeyBuild>` for single references and a
   per-sheet list of range rectangles → dependent (sorted by column, or an interval tree)
   for `RangeKind`, plus `always_dirty: HashSet<CellKey>` for formulas that cannot be
   analysed statically: volatile functions (`TODAY NOW RAND RANDBETWEEN RANDARRAY OFFSET
   INDIRECT CELL INFO`), defined names, structured/table references, `LAMBDA` invocations
   of names. Build it by walking each formula cell's `Node` (`expressions/parser/mod.rs`
   `Node::ReferenceKind / RangeKind / OpRangeKind / FunctionKind`), resolving the
   relative AST against the cell. Hook: `Model::parse_formulas` (`src/new_empty.rs:73`,
   full rebuild on load) and `Model::set_cell_with_formula` (`src/model.rs:2794`,
   incremental add/remove). Any structural change (insert/delete rows/cols, move, rename
   sheet, defined-name edits) → simply mark the index stale and rebuild lazily (it is one
   pass over the formula cells; cheaper than an evaluate).
2. **`Model::evaluate_dirty(changed: &[CellKey])`** in `evaluation.rs`: BFS over the index
   from the changed cells (+ `always_dirty`) → dirty set. Run a pass whose driver list is
   the dirty set instead of `formula_positions()`; in `evaluate_formula_cell` a formula
   cell that is **not** dirty returns `stored_value()` instead of running. Fall back to
   the full `evaluate()` when the dirty set contains a dynamic-array anchor or spill area
   (the restart machinery assumes a full pass), when the index is stale, or when the
   dirty set exceeds ~30 % of formulas.
3. **Wire it in** `UserModel::evaluate_if_not_paused` (`user_model/common.rs:2296`): the
   changed cells are already known from the `diff_list` (`Diff::SetCellValue`,
   `range_clear_contents`, paste …). Conditional formatting: re-evaluate only rules whose
   range intersects the dirty set (`conditional_formatting.rs`).

Expected effect: a value edit in the 300k-row workbook touches 3 formulas + 5 summary
formulas → sub-millisecond instead of 272 ms; the summary `SUM(C1:C300000)` itself
still re-reads 300k cells (≈ 3 ms) unless aggregates are also made incremental.

**Cheaper things to do first (in this order):**

1. **Fix exact-match comparison** (1-line-class change, 20× on VLOOKUP/XLOOKUP exact):
   in `functions/util.rs::compare_values` compare numbers with a fast path
   (`if (a-b).abs() > 1e-9*a.abs().max(b.abs()) { return sign }`) and only fall back to
   `to_excel_precision` when they are nearly equal; or round the lookup value once in
   `lookup_and_reference/mod.rs::lookup_index` / `xlookup.rs`. Also make
   `to_excel_precision` arithmetic instead of `format!`+`parse`.
2. **Stop materialising the whole lookup column**: `LookupTable::first_column`
   (`functions/lookup_and_reference/mod.rs:94`) builds a `Vec` of all rows before
   searching; iterate lazily and stop at the first exact match. Optionally a per-pass
   memo `HashMap<(range, column), index>` in `Evaluation` so 1000 lookups into the same
   table build it once (Excel does this).
3. **Foglio-side, no engine change:** keep the model on a worker thread, apply the edit
   with `pause_evaluation()` (≈ 1 µs, the typed value is shown immediately), then run
   `evaluate()` asynchronously and coalesce edits that arrive while it runs (typing in
   several cells, paste, fill → one evaluation). Use `pause_evaluation`/`resume_evaluation`
   around every multi-cell operation. This makes ≤ 300k-row workbooks feel instant
   (results arrive ≤ 0.3 s later) and is needed anyway as a safety net for workbooks with
   heavy lookups.
4. Save with `to_bytes()` for autosave/crash recovery (9 ms vs 1.4 s for xlsx at 300k rows);
   write xlsx only on explicit save, off the main thread.

Recommendation: do 3 (Foglio, now), 1 and 2 (small upstreamable PRs, big win for the most
common heavy formula), then the dependency index (4) as a fork/PR once Foglio needs
>100k-row workbooks to recalc instantly.
