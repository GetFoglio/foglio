# Excel gaps (vs Excel for Mac 365)

Scope: everyday office use. Already in flight elsewhere (not listed): charts, comments/notes, data validation, font family, tab colours, hyperlinks, summarize-by.
Difficulty: S = under a day, M = a few days, L = a week or more. Hints refer to the current code (`GridView.swift`, `Menus.swift`, `SheetWindowController.swift`, `Engine.swift`, `core/`).

## Tier A: must have to feel like Excel

| # | Feature | Excel for Mac behaviour | Diff | Hint |
|---|---|---|---|---|
| A1 | **Drag to move cells; ⌥-drag to copy** | Hover on the selection border shows a 4-arrow cursor. Drag moves, with overwrite warning. ⌥-drag copies. ⇧-drag inserts. | M | New `drag` case in `mouseDown`/`handleDrag`/`mouseUp` (`GridView.swift`). Reuse `copySelection(cut:)` and `pasteInternal` (cut=true for move). Needs a border hit-test next to `fillHandleRect`. |
| A2 | **Paste Special dialog** (⌃⌘V) | Choices: All, Formulas, Values, Formats, Column widths, Number formats. Operations: add, subtract, multiply, divide. Plus Skip blanks and Transpose. | M | Only `paste` and `pasteValues` exist, and `pasteValues` uses the text pasteboard. Add a `PasteMode` to `pasteInternal` in the core (formulas only / formats only / values only / transpose). Use the existing `foglio_paste_*` entry points. |
| A3 | **Insert / Delete cells with shift** | ⌃I (insert) and ⌘- (delete) open a dialog: shift cells right or down. Context menu says "Insert…" and "Delete…". | M | Today `insertRows` and `deleteRows` always act on whole rows, even for a partial selection. The core needs a shift-range op. A dialog can hide behind "Insert…". |
| A4 | **Repeat last action** | ⌘Y or F4 (outside edit mode) repeats the last formatting or edit command. | S | Record the last `@objc` action and sender in the responder chain. F4 is currently handled only inside the editor (`handleEditingKey`, keyCode 118). |
| A5 | **Typing AutoComplete from the column** | While typing text, Excel proposes a unique match from the same column as grey inline text. Tab/Enter accepts. | S | `controlTextDidChange` + a unique-prefix scan of the column via `book.jump` bounds. Only for text, not formulas. |
| A6 | **Number-format shortcuts** | ⌃⇧~ General, ⌃⇧! Number, ⌃⇧$ Currency, ⌃⇧% Percent, ⌃⇧^ Scientific, ⌃⇧# Date, ⌃⇧@ Time. | S | Add key handling in `keyDown`, mapped to `NumberFormats.all` entries. |
| A7 | **Border shortcuts** | ⌘⌥0 outline, ⌘⌥- none, ⌘⌥← / → / ↑ / ↓ single edges. | S | Existing `setBorder(kind:style:)`. |
| A8 | **Indent, rotate text, shrink to fit** | Increase/decrease indent buttons in Format Cells > Alignment. Text orientation. | M | Style paths `alignment.indent` and `alignment.text_rotation` exist in the xlsx model. Add them to `FormatCells` and the painter. A toolbar button already uses the "indent" icon for decimals (see bugs). |
| A9 | **Fill Series dialog and Flash Fill** | Fill > Series with step and stop value. ⌃E is Flash Fill (pattern completion). | M / L | Series: a dialog over `book.autofill`. Flash Fill: pattern inference from the adjacent column, heuristic. Start with split/join/case examples. |
| A10 | **Remove Duplicates, Text to Columns** | Data tab dialogs with a column checklist (dedupe) and delimiter picker (split). | M | Pure grid ops over `book.input` / `setInput`, wrapped in one undo step. |
| A11 | **Find All, Go To Special** | ⌘F panel lists every hit and clicking jumps. Go To Special offers blanks, formulas, constants, errors, visible cells. | M | `FindPanel` (`Panels.swift`) currently shows one hit at a time. Go To is a text prompt (`goTo`). Add a special-cells scan using `book.stats` style iteration. |
| A12 | **Sort dialog with several keys, plus Sort by header** | Custom Sort: multiple levels, "My data has headers", A-Z or Z-A, by colour. | M | `sort(_:)` is a single key on the active column with header detection. Add a sheet/popover. Keep the multi-key sort stable. |
| A13 | **Page Layout basics** | Print area, fit to 1 page wide, orientation, print titles (repeat rows), header/footer, print gridlines, page breaks. | M / L | `PrintView` paginates the used range or selection with hard-coded margins. Add per-sheet print settings, stored in the xlsx (`pageSetup`, `printOptions`, `definedName _xlnm.Print_Area`). |
| A14 | **Tables (⌃T) with structured references** | Format as Table: banded styles, header filter buttons, auto-extend on typing below, totals row, `Table1[Col]` references. | L | The core has no table model. Cheaper first step: a banded style plus AutoFilter plus auto-extend, without structured refs. |
| A15 | **Named ranges and Name Manager** | Name Box defines names. ⌘F3 opens Name Manager (Formulas tab). Names appear in function autocomplete. | M | IronCalc already supports defined names. Add Name Box write path, a manager panel and autocomplete entries. |
| A16 | **Group / Outline rows and columns** | ⌘⇧K group, ⌘⇧J ungroup. +/- gutter buttons, level buttons 1 2 3. | M | Needs `outlineLevel` and `collapsed` (xlsx stores them). Draw a gutter in `drawHeaders`, hide via the existing `setHidden`. |
| A17 | **Show Formulas (⌃`) and error indicators** | Toggles formula text display. Green triangles on cells with number-as-text, inconsistent formula, and so on. | S / M | Show Formulas: paint `book.input` instead of display text in `SheetPainter`. Triangles: a corner mark for text that parses as a number. |
| A18 | **Autofit and resize quality** | Double-click on a column border fits the widest *visible* value (exists). Also autofit rows from the menu (Format > Row > AutoFit). | S | There is `setRowHeights(px: nil)` for rows, but no menu item. |

## Tier B: important

| Feature | Excel behaviour | Diff | Hint |
|---|---|---|---|
| Split view / New Window / Zoom to selection | Window > New Window, View > Split. Zoom to selection fits it to the window. | M | Multiple `SheetWindowController`s for one `SpreadsheetDocument`. Split needs a second pane in `GridView`. Zoom to selection is S: compute the zoom from `rangeRect`. |
| Protect Sheet / Workbook, locked cells | Review > Protect Sheet with optional password. Locked cells reject edits. | M | Add a flag in the model and a check in `commitEditing`. The xlsx `sheetProtection` element is already preserved or ignored (check). |
| Sheet tab drag reordering | Drag a tab left or right. ⌥-drag copies. Context menu has Move or Copy. | S | `SheetTab` is a plain `NSButton` with a context menu "Move Left / Move Right". Add a drag session. |
| Status bar customization | Right-click for Sum, Average, Count, Numerical Count, Min, Max, Caps Lock, zoom. | S | `updateStatus` produces one fixed string. Add a context menu with toggles. |
| Formula auditing | Trace Precedents / Dependents (⌃[, ⌃]), Evaluate Formula, Error Checking. | M / L | The parser tokens are in `FormulaSupport`. Draw arrows in `drawOverlays`. |
| Conditional formatting: data bars, icon sets, edit rules | "Manage Rules" with edit and priority. | M | See `ConditionalFormat.swift`. Only create and clear exist. |
| Spill range visual | Blue border around dynamic-array results. `#SPILL!` handling. | S | Core already evaluates FILTER, SORT, UNIQUE. Needs spill extent from the core. |
| Number format dialog parity | Negative numbers in red or parentheses. Currency symbol picker, locale picker. | S | `FormatCells.swift`. |
| Multiple selection (⌘-click ranges) | Non-contiguous selection for formatting, ⌘-click rows and columns. | L | `selection` is a single `GridRange`. |
| Autofill option menu, custom lists | Day and month names, quarters, "Fill Weekdays". | S | `foglio_autofill` extension. |

## Tier C: later

- Macros and VBA, Power Query, Solver, Scenario Manager, What-If tables, Goal Seek (Goal Seek is M).
- Sparklines, slicers, timelines, Camera.
- Real pivot tables (beyond summarize-by).
- Workbook sharing / co-authoring, track changes.
- Themes and cell styles gallery. Formatting by colour sorting.
- Data Types (Stocks, Geography).
- Linked cells, external links, Get Data.
- Array-formula entry (⌃⇧↩ legacy `{=}` braces), Table slicers.
- Custom views, headers and footers images, page break preview.
- Spelling (macOS spellcheck is cheap: S via `NSSpellChecker`).
- AGGREGATE, GROUPBY, PIVOTBY (see `docs/FUNCTIONS.md`).

## Bugs and inconsistencies found while reading

1. **Shortcut conflict: Zoom In `⌘+` vs Calculate Now `⌘=` vs Insert Rows `⇧⌘+`.** In `Menus.swift`, Zoom In is `"+"`/⌘, Calculate Now is `"="`/⌘ and Insert > Rows is `"+"`/⌘⇧. AppKit matches the "+" key equivalent on ⌘= (and ⇧⌘= produces "+"). Which one fires depends on menu order (View before Insert before Data), so the README claim "Recalculate: F9 or ⌘=" probably fails in practice (zoom wins). Fix: Excel Mac uses ⌘= for Calculate Now, so drop ⌘+ from Zoom In (or use ⌘⌥= style), keep ⌘- only if no Delete-cells conflict (⌘- is also Excel's Delete cells, see A3).
2. **Page Setup margins are ignored.** `SpreadsheetDocument.printOperation` (`Document.swift`) hard-codes top/bottom 36 and left/right 30 after copying the user's `printInfo`, so margins chosen in Page Setup are overwritten. Orientation and paper size are respected.
3. **Insert > Sheet uses ⇧⌘N.** In Excel for Mac this is ⇧F11; ⇧⌘P is New Workbook from Template and ⇧⌘N is not a sheet shortcut. Not harmful, but not Excel. Also note that Foglio's File > New is ⌘N, so users may confuse them.
4. **Paste Values uses ⌥⇧⌘V.** That is the macOS system "Paste and Match Style" shortcut, and Excel's Paste Special is ⌃⌘V. Paste Values from the text pasteboard drops the number formatting of internal copies, and ignores a multi-cell selection (always pastes at the active cell, `pasteValues` in `GridView.swift`) and leaves the cut range marked after a cut (`cutRange` is cleared but the source cells are not cleared when a *cut* is pasted as values).
5. **Paste does not tile.** Copying one cell and pasting into a larger selection fills only the first cell (`paste` sizes the target to the source `h × w`), where Excel repeats the content over the selection.
6. **Tab/Enter return-to-column is missing.** Excel returns to the column where a Tab sequence started when you press Enter. `commitEditing` -> `advance(1, 0)` simply moves down from the current cell.
7. **Wrong or misleading toolbar icons and labels.** "Increase/Decrease Decimal" use `increase.indent` / `decrease.indent` icons (which read as indent). The "Number" button applies `#,##0.00` (Excel's "Comma Style" button is the accounting-like 1,000 format) and the Percent button applies `0%` while the menu's Percentage is `0.00%`. Tooltips for Strikethrough, Fill, Sort, Freeze and Filter lack their shortcut text while Bold/Italic/Underline/Undo/Redo have it.
8. **Delete Rows/Columns on a partial selection.** `deleteRows` deletes whole rows silently when you select a few cells (Excel Mac shows the Delete dialog for ⌘-). It also beeps when whole columns are selected rather than deleting nothing silently.
9. **`NumberFormats.all` locale logic.** The local variable is named `it` but is true for *any* non-en-US locale, so en-GB gets `dd/mm/yyyy` with a long date of `dddd d mmmm yyyy`, which happens to work. German would still get `dd/mm/yyyy` rather than `dd.mm.yyyy`. Currency uses suffix style (`#,##0.00 "£"`) for any non-"$" locale, which is wrong for GBP (prefix). Time is `hh:mm:ss` (24 h, zero-padded) whereas Excel's default Time is `h:mm:ss AM/PM` in en-US. "Insert current time" uses `HH:mm` (not locale-aware) while "Insert current date" uses the formula locale pattern.
10. **Clear is duplicated.** Edit > Clear > Formats and Format > Clear Formats both exist, and Edit > Delete and Clear > Contents both call `NSText.delete`. Excel has a single Clear menu. Not a bug; cleanup.

### Italian localisation vs Excel Italian terminology

Every string used in code has an entry (checked by script); wording to review (verify against a real Italian Excel before changing):

| English | Foglio IT | Excel IT / macOS IT |
|---|---|---|
| Minimize (Window) | Contrai | **Riduci a icona** (macOS standard) |
| Show All | Mostra tutte | **Mostra tutto** (macOS standard) |
| Page Setup… | Formato di stampa… | macOS: "Formato di stampa…" is right for the app menu, but Excel IT says **Imposta pagina…** |
| Revert to Saved | Ripristina ultima versione salvata | macOS: "Ripristina all'ultima versione salvata" |
| Center | Al centro | **Allinea al centro** (Excel IT) |
| Middle / Top / Bottom | Al centro verticale / In alto / In basso | **Allinea in mezzo / in alto / in basso** |
| Name Box tooltip | Casella Nome | **Casella nome** (Excel IT lowercase) |
| Hide Others | Nascondi altre | macOS: **Nascondi altre** OK |


## Suggested order

A4, A5, A6, A7, A18 (all S) in one sprint. Then A1, A2, A3, A10, A11, A12 (grid interaction). Then A13, A15, A16, A8 (file-format-backed features). A14 (Tables) and A9 Flash Fill last in Tier A.
