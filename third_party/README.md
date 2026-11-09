# Vendored IronCalc (Foglio fork)

`ironcalc_base/` and `ironcalc/` are **patched forks of IronCalc 0.9.1**
(<https://github.com/ironcalc/ironcalc>, crates `ironcalc_base` 0.9.1 and
`ironcalc` 0.9.1, © Nicolás Hatcher and contributors, dual-licensed
MIT OR Apache-2.0 — see `LICENSE-MIT` and `LICENSE-Apache-2.0` in each crate;
`ironcalc_base/THIRD-PARTY-NOTICES.md` is upstream's).

They were copied verbatim from the crates.io packages (the normalized
`Cargo.toml` works as a path dependency as is) and are wired into Foglio with

```toml
[patch.crates-io]
ironcalc = { path = "../third_party/ironcalc" }
ironcalc_base = { path = "../third_party/ironcalc_base" }
```

in `core/Cargo.toml` and `bench/Cargo.toml`, so `ironcalc = "0.9"` keeps
resolving to these copies. Every Foglio change is marked with a
`Foglio fork:` comment.

## Changes

### Build
* `ironcalc_base/build.rs`: upstream sets `GIT_VERSION` (used by
  `INFO("release")`) from `git describe` of the *current* directory, which for
  a vendored copy is the Foglio repository. Fixed to `0.9.1-foglio`.
* `ironcalc/Cargo.toml`: the dependency on `ironcalc_base` also has
  `path = "../ironcalc_base"`, so building or testing `ironcalc` on its own
  uses the fork; a new test target `incremental_corpus`.

### Performance
* **Number comparison fast path** (`functions/util.rs::compare_values`):
  exact equality first; numbers more than 1e-12 apart (relative, and 1e-15
  absolute) are ordered directly. Only nearly equal numbers go through the
  15-significant-digit rounding. Same result as before (proof in the comment).
* **`to_excel_precision` fast path** (`number_format.rs`): integers below
  1e15, and numbers whose shortest representation (ryu) has at most
  `precision` digits, are returned unchanged instead of going through
  `format!` + `parse`. Exact (argument in the comment).
* **Exact-match lookup index** (new `functions/lookup_cache.rs`, used by
  VLOOKUP/HLOOKUP with FALSE, MATCH with 0 and XLOOKUP in its default exact
  mode): the first lookup into a vector in an evaluation pass reads the vector
  once (exactly like the plain path) and builds a hash index; later lookups are
  a hash probe. Used only when it gives the same answer as the linear search:
  numbers of magnitude >= 1, texts without wildcards (non-empty for XLOOKUP);
  not while a cell of the vector is being evaluated (cycle detection); and a
  spill into an indexed vector abandons the pass, which runs again without the
  index (`Restart::LookupCacheConflict`). 1000 exact VLOOKUPs into 10k rows:
  1.7 s → 1.4 ms.
* **Incremental recalculation** (new `dependencies.rs`,
  `evaluation/incremental.rs`; hooks in `evaluation.rs`, `user_model/common.rs`):
  - `DependencyIndex`: reverse dependencies of every formula, built from the
    parsed formulas with relative references resolved per cell. Single cells
    are kept per column sorted by row; ranges are rectangles (per column for
    ranges up to 16 columns wide, one list for wider ones), so `A:A` is one
    entry. Formulas that cannot be analysed statically are *volatile* and run
    on every evaluation together with what depends on them: NOW, TODAY, RAND,
    RANDBETWEEN, RANDARRAY, INDIRECT, OFFSET, CELL, INFO, SHEET(S), defined
    names, table references, the range operator between computed references
    (`A1:INDEX(…)`), the spill operator (`A1#`) and LAMBDAs stored in names.
  - `UserModel` reports every edit: `set_user_input`, `range_clear_contents`
    and undo/redo of plain content edits as changed positions; every other
    operation (and every diff pushed to the history that is not known to leave
    values alone) as "anything may have changed" → the next evaluation is a
    full one and the index is rebuilt lazily.
  - `Model::evaluate_pending`: dirty set = changed formulas + everything
    reachable from the changed positions + volatile formulas and their
    dependents; runs only those, in the order a full pass would (dynamic
    anchors in their order, then natural order). A formula that is not dirty
    is read as its stored value.
  - Falls back to a full evaluation when it cannot be shown to be identical:
    the edit touches an array area (spill cells, CSE areas, anchors that
    spill), a dynamic array is blocked or circular (`#SPILL!`/`#CIRC!`), a
    dirty anchor would change the size of its spill area (the pass is
    abandoned before writing), the workbook has circular references (which
    cells IronCalc reports a cycle on depends on where the recursion entered
    it), the dirty set is more than half the formulas, or any restart.
  - `UserModel::evaluate()` is now incremental when possible (the same API;
    `pause_evaluation`/`resume_evaluation` + `evaluate()` batches stay
    incremental). New: `UserModel::evaluate_full()`,
    `last_evaluation_incremental()`, `last_full_evaluation_reason()`,
    `set_check_incremental(bool)` (and `Model::` equivalents).
  - **Check mode**: `IRONCALC_CHECK_INCREMENTAL=1` (or
    `set_check_incremental(true)`) runs a full evaluation after every
    incremental one and panics if any cell (value, error origin and message,
    spill state) or HYPERLINK link differs.
  - `evaluation.rs`: `formula_positions` also records the CSE anchors;
    `evaluate()` records array areas, whether an array is blocked and whether
    the workbook has cycles; `evaluate_formula_cell` / `evaluate_spill_cell`
    honour the dirty set; `run_top` abandons an incremental pass when an
    anchor would resize.

### Excel compatibility
* **Number → text with 15 significant digits** (`cast.rs`, new
  `number_format::to_excel_string`): `=0.1+0.2&""` is `0.3`, `=1/3&""` is
  `0.333333333333333`, scientific notation (`1E+20`,
  `1.12589990684262E+15`) from 1E+15 up, and below when fixed notation would
  need more than 18 decimals (Excel's own `VALUETOTEXT(7.123456E-09)` =
  `0.000000007123456` in the test corpus). Affects `&`, CONCATENATE, CONCAT,
  TEXTJOIN, LEN/LEFT/… on numbers, array-to-text.
* **Skipped optional arguments count as omitted** (`functions/util.rs::arg_given`):
  SORT (`SORT(r,,-1)`), TAKE/DROP (`TAKE(r,,1)`), TEXTBEFORE/TEXTAFTER
  (`TEXTBEFORE(t,d,,1)`).
* **YEAR/MONTH/DAY before March 1900** (`functions/date_and_time.rs`): serial 0
  (an empty cell, FALSE) is 1900-01-00 → 1900 / 1 / 0; serial 1 is 1900-01-01
  (upstream: 1899-12-31); serial 60 is Excel's 1900-02-29. Upstream tests in
  `test/test_date_and_time.rs` updated.
* **TEXT**: scientific exponent sign (`TEXT(1.5,"0.0E+00")` = `1.5E+00`, was
  `1.5E-00`) and fraction formats `# ?/?`, `# ??/??`, `?/?`, `# ?/8`
  (`formatter/format.rs::format_fraction`; also used for cell display).
* **AND/OR/XOR with a text argument** (`functions/logical/and_or_xor_not.rs`):
  text other than "TRUE"/"FALSE" given directly is `#VALUE!`; the empty
  string is still ignored (upstream's tests require it); text in referenced
  cells is still ignored.
* Not changed: `POWER(-8,1/3)` stays -2 — Excel computes odd roots of negative
  numbers (Excel cached -1.9999999999999998 in
  `ironcalc/tests/calc_tests/MATH_AND_TRIGONOMETRY/POWER.xlsx`).

### Comments, data validation, font name, tab colour
* **Data validation** (new `ironcalc_base/src/data_validation.rs`, field
  `Worksheet::data_validations`): rules with sqref, type (any, whole, decimal,
  list, date, time, textLength, custom), operator, formula1/formula2 (stored
  as in xlsx: English, no `=`), allowBlank, in-cell dropdown, input message,
  error style/title/message. `Model`: get/add/remove rules by area (rules are
  split around a cleared rectangle, formulas rebased to the new first cell),
  list items of a cell (inline items or the formatted values of the
  referenced range, evaluated per cell), `validate_input` (reads the input as
  `set_user_input` would; custom formulas are evaluated with the candidate
  temporarily in the cell), conversion of formulas from/to what the user types
  in the workbook language and locale, `english_formula_to_user`.
* **Comments**: `Model::get/set/delete_comment`, `get_comment_cells`.
* Both follow inserted/deleted/moved rows and columns (hook at the top of
  `actions.rs::displace_cf_ranges`; deleted cells lose their comment, ranges
  are clipped, formulas of every sheet's rules displaced); sheet renames
  rewrite rule formulas (`new_empty.rs::rename_sheet`).
* **Undo** (new `user_model/annotations.rs`): `Diff::SetSheetAnnotations`
  (comments + rules of a sheet, old/new); the structural actions in
  `user_model/common.rs` push it as a snapshot (old == new) like
  `SetMergedCells`, so undo restores deleted comments/rules exactly.
  `UserModel::set_comment`, `delete_comment`, `set_data_validation`,
  `clear_data_validation`, `get_data_validation_list`, `validate_input`,
  `data_validation_from_user` / `to_user`.
* **History groups**: `UserModel::begin_history_group` /
  `end_history_group` merge everything pushed in between into one undo step
  (`History::group`; `UserModel::history` is `pub(super)`).
* **Font name**: style path `font.name` (`update_range_style`); sets the font
  scheme to `none`, otherwise Excel shows the theme font.
* **xlsx import** (new `ironcalc/src/import/annotations.rs`): comments parts
  at any target (`../comments1.xml`, openpyxl's absolute
  `/xl/comments/comment1.xml`; upstream failed to open those files), authors,
  Excel's bold "Author:" first run is not part of the text, a broken comments
  part is skipped; `<dataValidations>` and the x14 `<x14:dataValidations>`
  extension (cross-sheet lists from older Excel).
* **xlsx export** (new `ironcalc/src/export/annotations.rs`): comments as
  Excel writes notes (`xl/commentsN.xml`, `xl/drawings/vmlDrawingN.vml`,
  `<legacyDrawing>`, sheet rels with ids `rIdFoglioComments1`/`rIdFoglioVml1`,
  content types), `<dataValidations>` (titles/messages truncated to Excel's
  32/255 limits, rules without their formulas skipped), `<sheetPr><tabColor>`
  (upstream imported the tab colour but did not write it).

### Tests added
* `ironcalc_base/src/test/test_incremental.rs`: targeted tests, randomized
  edit sequences (400 sessions × 60 edits in the default run; 2000 × 120 in
  `--ignored many_random_sessions`) over workbooks mixing ranges, chains,
  cross-sheet references, IF/VLOOKUP/HLOOKUP/INDEX/MATCH/XLOOKUP/SUMIFS,
  FILTER/SORT/UNIQUE/SEQUENCE spills, INDIRECT/OFFSET, LET, errors and
  cycles, with undo/redo, clears, row insert/delete and paused batches — all
  in check mode.
* `ironcalc/tests/incremental_corpus.rs`: random edits on every workbook of
  upstream's Excel-made xlsx corpus (242 workbooks), in check mode.
* `number_format::tests::excel_string`.
* `data_validation::tests` (rectangles, displacement + undo, history groups),
  `import::annotations::tests`; Foglio's `core/tests/features.rs` covers the
  C ABI with xlsx round trips and an openpyxl-made workbook.

Known upstream test failures (also failing on the pristine 0.9.1 package):
`test::user_model::test_to_from_bytes::errors` (bitcode error text) and six
date-dependent xlsx tests in `ironcalc` (`test_calc_DATE_AND_TIME_NOW_TODAY`,
`test_templates_*`).
