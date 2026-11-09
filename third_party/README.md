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
  1.7 s → 1.4 ms. (Now built from the vectors kept per pass, see the next
  item.)
* **Lookups read only the used part of their vectors, once per pass**
  (`functions/lookup_cache.rs`: `Model::lookup_vector`, `VectorData`; used by
  VLOOKUP/HLOOKUP, MATCH, LOOKUP, XLOOKUP, XMATCH; `prepare_array` removed):
  - A lookup vector (the first column of a VLOOKUP table, MATCH's range, …) is
    read in order, cell by cell, as before, but only up to the last row (for a
    column) or column (for a row) of the sheet that holds a cell; this is
    checked again after the walk in case a formula evaluated during it
    spilled further. Positions past it are empty: put on record as read empty
    in one go (`record_seen_empty_range`, so a later spill into them still
    restarts the pass) and treated as empty cells by the searches, which give
    the same answers as on the whole vector (`VLOOKUP(0,A:B,2,FALSE)` still
    finds the first empty cell below the data; IronCalc's approximate search
    over a whole column still lands on the last row, as before). Any range is
    clipped this way, not only `A:A` and `1:1`.
  - The values read are kept for the rest of the evaluation pass (replacing
    the per-pass hash index, which is now built on demand from them): later
    lookups into the same vector read no cell and allocate nothing — a hash
    probe for exact matches (same rules as before), `VectorData::binary_search`
    (upstream's `binary_search_on_array`, same probes) for approximate ones, a
    scan otherwise. XLOOKUP/XMATCH keep upstream's whole-column clipping
    (`clip_to_used_area`) and use the kept values for every mode. LOOKUP's
    result vector goes through the same path. Same invariants as before:
    not while a cell of the vector is on the evaluation stack, nothing kept
    from an interrupted read, a spill into a kept vector reruns the pass
    without them.
  - Outside a pass the cache is used only while the conditional formatting is
    evaluated (`with_lookup_cache_outside_pass`), which at load time
    (`Model::from_workbook`) is what evaluates the formulas the rules read; a
    spill into a kept vector drops it, and a vector during whose reading a
    spill happened is not kept.
  - `clip_to_used_area` and SUMIFS & co. (`apply_ifs`) take the used area from
    `Worksheet::used_max_row`/`used_max_column` (new
    `SheetData::last_row_with_cells`/`last_column_in_rows`): the same bounds
    as `dimension()`, which visited every cell of the sheet on every call.
  - Apache POI's `StructuredRefs-lots-with-lookups.xlsx` (7 274 formulas,
    3 264 `VLOOKUP(…,Query!$A:$N,…,FALSE)`, structured references, a
    conditional format reading them): opening it took 12 s
    (`Model::from_workbook`, the conditional formatting evaluating every
    formula outside a pass, each VLOOKUP copying 1 048 576 cells), now
    ≈ 25 ms; its full evaluation 54 → 3 ms.
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
* **Currency tags in number formats** (`formatter/lexer.rs`, `parser.rs`):
  the symbol of `[$€-407]` is written where the format puts it
  (`#,##0.00 [$€-407]` is `1.234,50 €`; upstream always put it in front of the
  number), symbols can be longer than one character (`[$CHF-807]`), and a
  locale-only tag such as `[$-410]` (Italian dates) shows nothing instead of
  making the format invalid. `Token::Currency` holds a `String`; the two
  upstream lexer tests in `test/test_special_dollar.rs` compare with one.
* **Frozen panes and grid lines of the sheet view** (`import/worksheets.rs::get_sheet_view`):
  a pane in state `frozenSplit` (panes frozen after a split, as Excel writes
  them) is read as frozen like `frozen` (upstream: not frozen); `showGridLines`
  accepts `true`/`false` as well as `1`/`0` (upstream: `"true"` hid them).
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

### Charts
* **Model** (new `ironcalc_base/src/charts.rs`, field `Worksheet::charts`):
  `Chart` = name, kind (clustered/stacked column and bar, line, line with
  markers, pie, doughnut, area, stacked area, scatter), title, legend
  position, axis titles, series (name ref or literal, categories/X ref,
  values ref, colour) and a two-cell anchor (cell + EMU offsets, like
  `xdr:twoCellAnchor`). References are sheet-qualified absolute A1 strings
  (`Sheet1!$B$2:$B$9`), exactly what `<c:f>` holds. `Model::get_chart_data`
  evaluates them for drawing (formatted category text, numbers; hidden rows
  and columns skipped like Excel's default).
* **Undo**: `UserModel::add_chart`, `update_chart`, `delete_chart` push
  `Diff::SetCharts` (whole list of the sheet, old/new); no recalculation.
* **Structure**: inserting/deleting rows or columns moves the charts of the
  sheet and shifts every series reference into it (hooks next to
  `displace_merged_cells` in `actions.rs`; a fully deleted range becomes
  `Sheet!#REF!`); renaming a sheet renames it in the references
  (`new_empty.rs::rename_sheet_by_index`). Moving rows/columns
  (`move_*_action`) does not touch charts.
* **xlsx import** (new `ironcalc/src/import/charts.rs`, called from
  `load_sheets`): sheet rels → `xl/drawings/drawingN.xml` (two-cell,
  one-cell and absolute anchors) → drawing rels → `xl/charts/chartN.xml`.
  bar/bar3D, line/line3D/stock/radar (as line), pie/pie3D/ofPie, doughnut,
  area/area3D, scatter/bubble (as scatter), surface (as column); combination
  charts keep every series with the first group's type. Anything unreadable
  is skipped without failing the load.
* **xlsx export** (new `ironcalc/src/export/charts.rs`): drawing part, chart
  parts with formula references plus value caches, drawing rels, sheet rel
  `rIdFoglioDrawing1`, `<drawing>` in the worksheet (after `<hyperlinks>`,
  before `<legacyDrawing>`), content types. Element order follows the
  DrawingML chart schema; Excel 2016 defaults (gap width 219, overlap -27,
  no rounded corners, light gridlines).

### Pictures
* **Model** (new `ironcalc_base/src/pictures.rs`, fields `Worksheet::pictures`
  and `Worksheet::images`): `Picture` = name, alt text (`descr`), image key,
  two-cell anchor (shared `ChartAnchor`), size `cx`/`cy` in EMU, `edit_as`
  (twoCell / oneCell / absolute), crop (`a:srcRect` l/t/r/b in 1/1000 %),
  `in_cell` ("Place in Cell": fitted in the cell of `from`, aspect `cx:cy`,
  1 px margin, written as a two-cell anchor) and `z`. Image bytes live in a
  per-sheet store keyed by a content hash (FNV-1a 64 + length): identical
  images are stored once, and undo steps never copy bytes. The store only
  grows during a session; only images in use are written. Only PNG/JPEG/GIF/
  BMP headers are read (pixel size); decoding and resampling are left to the
  app.
* **Stacking**: `Chart::z` (new field, `#[serde(default)]`) and `Picture::z`
  share one order (`drawing_order`, `restack_drawing`; new charts and pictures
  go in front). It is the order of the anchors in the drawing part.
* **Undo**: `add_picture`, `update_picture`, `delete_picture` push
  `Diff::SetPictures` (old/new list of the sheet, no recalculation);
  `restack_drawing` pushes `SetCharts` + `SetPictures` as one step.
* **Structure**: `displace_charts` (already hooked into row/column insert and
  delete) also moves pictures (`displace_pictures`): absolute pictures stay,
  others move with their cells, a two-cell picture whose cells are deleted
  keeps a minimal size.
* **xlsx import** (new `ironcalc/src/import/pictures.rs`; the chart reader's
  loop in `import/charts.rs`, renamed `load_sheet_drawings`, now hands
  `xdr:pic` anchors to it and records the anchor order): `a:blip/@r:embed`
  → drawing rels → `xl/media/*` (case-insensitive part names, 64 MB cap),
  twoCell/oneCell/absolute anchors, `a:srcRect`, `cNvPr/@descr`; anchors
  inside `mc:AlternateContent` (first choice with an anchor, else the
  fallback); pictures inside group shapes (`xdr:grpSp`, nested, with scaled
  child coordinates `chOff`/`chExt`) become pictures of their own, placed where
  the group puts them in its anchor (groups squeezed to zero size are skipped);
  a two-cell anchor fitted in a single cell the way Foglio writes in-cell
  pictures (centred, aspect kept, 1 px tolerance) becomes an in-cell picture,
  any other picture inside one cell stays floating. Excel 365 pictures in cells: `xl/metadata.xml` (XLRICHVALUE value
  metadata) → `xl/richData/rdrichvalue.xml` + `rdrichvaluestructure.xml`
  (`_localImage`, `_rvRel:LocalImageIdentifier`, `Text` as alt text) →
  `richValueRel.xml` + rels → media; cells with a matching `vm` (found by a
  streaming pass over the sheet part, only when `xl/richData` exists) get an
  in-cell picture and lose their `#VALUE!` placeholder. Unreadable pictures and
  other drawing objects (shapes, text boxes, OLE icons) are skipped.
* **xlsx export** (new `ironcalc/src/export/pictures.rs`; `export/charts.rs`
  writes the drawing part for sheets with charts *or* pictures): one
  `xdr:twoCellAnchor editAs="…"` per picture in stacking order with charts,
  `to` recomputed from the size (one-cell/absolute) or the cell (in-cell),
  `a:off`/`a:ext`, `a:srcRect`, `picLocks noChangeAspect`; media numbered
  across the workbook and deduplicated, stored uncompressed; `<Default>`
  content types for the image extensions; drawing rels `rIdImgN`.

### Tests added
* `ironcalc_base/src/test/test_incremental.rs`: targeted tests, randomized
  edit sequences (400 sessions × 60 edits in the default run; 2000 × 120 in
  `--ignored many_random_sessions`) over workbooks mixing ranges, chains,
  cross-sheet references, IF/VLOOKUP/HLOOKUP/INDEX/MATCH/XLOOKUP/SUMIFS,
  FILTER/SORT/UNIQUE/SEQUENCE spills, INDIRECT/OFFSET, LET, errors and
  cycles, with undo/redo, clears, row insert/delete and paused batches — all
  in check mode.
* `ironcalc_base/src/test/test_lookup_ranges.rs`: lookups against a naive
  evaluation (`NAIVE_LOOKUPS`: every lookup reads its whole vector on every
  call, no cache, no index, as upstream) on randomized workbooks — whole
  columns and rows, tall and `A2:A1048576` ranges, structured references,
  numbers/zeros/text with wildcards/booleans/errors/empty cells, formulas,
  spills into the lookup column, cycles — at load (conditional formatting)
  and after full evaluations, all cells identical; random edits in check
  mode; the vector searches against upstream's on materialized vectors;
  `used_max_row`/`used_max_column` against `dimension()`.
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
