// foglio_features.h — comments (notes), data validation, font name, sheet tab colour,
// hyperlinks and a "pivot-lite" summary. Implemented in src/features.rs.
//
// Conventions (as in foglio_core.h): sheets are 0-based, rows and columns 1-based.
// Ranges (r0, c0, r1, c1) are inclusive and may be given in any order.
// Every char* returned (including *err_out, *title_out, *message_out) must be released
// with foglio_string_free. int32_t results: 0 success, -1 failure, unless stated.
// Every change below is one undo step (foglio_undo / foglio_redo) and is saved to xlsx.
#ifndef FOGLIO_FEATURES_H
#define FOGLIO_FEATURES_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef FOGLIO_BOOK_DEFINED
#define FOGLIO_BOOK_DEFINED
typedef struct FoglioBook FoglioBook;
#endif

// ---------------------------------------------------------------- comments (notes)
// One plain-text comment per cell, with an author. Comments move with their cells when
// rows/columns are inserted, deleted or moved (a deleted cell loses its comment).
// Saved like Excel's notes (xl/commentsN.xml + legacy VML drawing).

// Text of the comment of the cell, or NULL if it has none.
char *foglio_comment_get(const FoglioBook *b, uint32_t sheet, int32_t row, int32_t col);
// Author of the comment ("" if unknown), or NULL if the cell has no comment.
char *foglio_comment_author(const FoglioBook *b, uint32_t sheet, int32_t row, int32_t col);
// Sets or replaces the comment. text NULL or "" deletes it. author may be NULL ("").
int32_t foglio_comment_set(FoglioBook *b, uint32_t sheet, int32_t row, int32_t col,
                           const char *text, const char *author);
// Deletes the comment of the cell (no error if there is none).
int32_t foglio_comment_delete(FoglioBook *b, uint32_t sheet, int32_t row, int32_t col);
// Cells with a comment inside the range (e.g. the visible viewport), for the red
// triangles: 2 ints (row, col) per cell, sorted by row then column; *out_n = number of
// cells. Free with foglio_ints_free(ptr, 2 * n).
int32_t *foglio_comment_cells(const FoglioBook *b, uint32_t sheet, int32_t r0, int32_t c0,
                              int32_t r1, int32_t c1, size_t *out_n);
// Every comment of the sheet, sorted by position:
// [{"row":2,"col":3,"text":"…","author":"…"}, …]
char *foglio_comments_json(const FoglioBook *b, uint32_t sheet);

// ---------------------------------------------------------------- data validation
// A rule is JSON (all fields optional except "type"):
// {
//   "type": "none" | "whole" | "decimal" | "list" | "date" | "time" | "textLength" | "custom",
//   "operator": "between" | "notBetween" | "equal" | "notEqual" | "lessThan" |
//               "lessThanOrEqual" | "greaterThan" | "greaterThanOrEqual",   (default between;
//               used by whole/decimal/date/time/textLength)
//   "formula1": "…", "formula2": "…",   (formula2 only for between/notBetween)
//   "allowBlank": true,                 ("Ignore blank")
//   "inCellDropdown": true,             (list: show the dropdown arrow. NB: the opposite of
//                                        xlsx's showDropDown attribute, handled on save/load)
//   "showInputMessage": true, "promptTitle": "…", "prompt": "…",
//   "showErrorMessage": true,           (false: invalid data is accepted silently)
//   "errorStyle": "stop" | "warning" | "information", "errorTitle": "…", "error": "…"
// }
// formula1/formula2 are what the user types in Excel's dialog, in the workbook language
// and locale (Italian: "1,5", "31/12/2025", "a;b;c", "=SOMMA(A1:A3)"):
//   list:        items separated by the locale list separator (";" when the decimal
//                separator is ",", else ","), max 255 characters; or a reference/formula
//                starting with "=" ("=$A$1:$A$10", "=Foglio2!$A$1:$A$5", "=MyName")
//   whole/decimal/textLength: a number, or "=formula"
//   date:        a date ("31/12/2025", "2025-12-31") or "=formula";  time: "13:30" or "=formula"
//   custom:      a formula, with or without "=", TRUE when the value is valid (relative
//                references are relative to the top-left cell of the range)
// foglio_validation_get returns the rule in the same form, plus "sqref" (all the cells
// the rule applies to, e.g. "A1:A10 C3").

// Applies the rule to the range, replacing the rules those cells had. -1 if the JSON or
// a formula is invalid (message in *err_out, may be NULL).
int32_t foglio_validation_set(FoglioBook *b, uint32_t sheet, int32_t r0, int32_t c0,
                              int32_t r1, int32_t c1, const char *rule_json, char **err_out);
// Removes data validation from the range (rules shrink or disappear).
int32_t foglio_validation_clear(FoglioBook *b, uint32_t sheet, int32_t r0, int32_t c0,
                                int32_t r1, int32_t c1);
// The rule of the cell (JSON as above), or NULL. Use it for the dropdown arrow
// (type "list" && inCellDropdown) and the input message (showInputMessage, prompt…).
char *foglio_validation_get(const FoglioBook *b, uint32_t sheet, int32_t row, int32_t col);
// Items of the cell's list validation as a JSON array of strings, or NULL if the cell has
// no list validation: the inline items, or the displayed (formatted) values of the
// non-empty cells of the referenced range, evaluated for this cell (max 10000).
char *foglio_validation_list(FoglioBook *b, uint32_t sheet, int32_t row, int32_t col);
// The same items as [{"display": "…", "input": "…"}, …]: "input" is what to enter in the cell
// when the item is picked (for a range source, the cell's value as typed, e.g. "0,3333333333333"
// rather than its formatted "0,33 €"; text that would read as a number gets a leading ').
char *foglio_validation_list_items(FoglioBook *b, uint32_t sheet, int32_t row, int32_t col);

enum {
    FOGLIO_VALIDATION_OK = 0,
    FOGLIO_VALIDATION_STOP = 1,         // reject the value (Retry / Cancel)
    FOGLIO_VALIDATION_WARNING = 2,      // "Continue?" Yes enters the value, No edits again
    FOGLIO_VALIDATION_INFORMATION = 3,  // OK enters the value, Cancel discards it
};
// Checks `input` — the text the user is about to commit in the cell, as typed — against
// the cell's rule; call it before foglio_set_input. Returns a FOGLIO_VALIDATION_* code.
// For codes > 0, *title_out and *message_out (if not NULL) receive the rule's error title
// and message, which may be "" (show your own default, as Excel does).
// Always OK: cells without a rule, rules with showErrorMessage false, empty input,
// formulas (input starting with "="). Values are read as foglio_set_input reads them
// (numbers, percentages and dates in the workbook locale; a leading ' forces text).
// List matching is case-insensitive (numbers compare by value). A custom formula is
// evaluated with the input in the cell; other formulas are not recalculated for it.
int32_t foglio_validation_check(FoglioBook *b, uint32_t sheet, int32_t row, int32_t col,
                                const char *input, char **title_out, char **message_out);

// ---------------------------------------------------------------- font name
// Set with foglio_set_style(b, sheet, r0, c0, r1, c1, "font.name", "Arial") (max 31
// characters; the font is then no longer the theme font). Saved in xlsx styles.
// The font name of the cell, e.g. "Calibri".
char *foglio_font_name_at(FoglioBook *b, uint32_t sheet, int32_t row, int32_t col);

// ---------------------------------------------------------------- sheet tab colour
// The tab colour as 0xRRGGBB (theme colours resolved), or FOGLIO_NO_COLOR (0xFFFFFFFF).
uint32_t foglio_sheet_color(const FoglioBook *b, uint32_t sheet);
// Sets the tab colour (0xRRGGBB); FOGLIO_NO_COLOR removes it.
int32_t foglio_set_sheet_color(FoglioBook *b, uint32_t sheet, uint32_t rgb);

// ---------------------------------------------------------------- hyperlinks
// The cell's link as JSON {"address": "...", "tooltip": null | "...", "dynamic": false},
// or NULL. address is a URL ("https://…", "mailto:…", a file path) or "#" + a place in
// this workbook ("#Sheet2!A1", "#MyName"). dynamic links come from =HYPERLINK() formulas
// and cannot be edited or removed (only the formula can).
char *foglio_link_get(const FoglioBook *b, uint32_t sheet, int32_t row, int32_t col);
// Attaches (or replaces) the link of the cell; address as above. display (NULL or "" to
// keep the cell content) becomes the cell text. tooltip may be NULL. A cell that had no
// link gets the link style (underline, theme hyperlink colour).
int32_t foglio_link_set(FoglioBook *b, uint32_t sheet, int32_t row, int32_t col,
                        const char *address, const char *display, const char *tooltip);
// Removes the link of the cell; its text and style stay.
int32_t foglio_link_remove(FoglioBook *b, uint32_t sheet, int32_t row, int32_t col);

// ---------------------------------------------------------------- summary (pivot-lite)
enum {
    FOGLIO_AGG_SUM = 0, FOGLIO_AGG_COUNT = 1, FOGLIO_AGG_AVERAGE = 2,
    FOGLIO_AGG_MIN = 3, FOGLIO_AGG_MAX = 4,
};
// Summarizes a table: rows r0..r1 of `sheet` (r0 is the header row) grouped by the
// values of column group_col, aggregating column value_col (both absolute 1-based
// columns inside c0..c1). Creates a NEW sheet (appended, named target_name, or a
// localized "Summary"/"Riepilogo" if NULL/""; " (2)"… is added if the name is taken) with:
//   A1 the group header, B1 e.g. "Sum of Amount" / "Somma di Importo" (workbook language),
//   A2… the distinct non-empty group values, sorted (numbers, then text case-insensitively,
//       then booleans; text is grouped case-insensitively, like *IFS criteria),
//   B2… live formulas SUMIFS / COUNTIFS / AVERAGEIFS / MINIFS / MAXIFS with absolute
//       references to the source ('Sheet'!$C$2:$C$100), so they follow data changes,
//   a bold "Total"/"Totale" row: SUM (sum, count), MIN/MAX of the groups, or AVERAGEIFS
//       over all rows with a group value (average).
// The group values are a snapshot: values added to the source later are not listed.
// Returns the index of the new sheet, or -1 (message in *err_out, may be NULL).
// One undo step.
int32_t foglio_summarize(FoglioBook *b, uint32_t sheet, int32_t r0, int32_t c0, int32_t r1,
                         int32_t c1, int32_t group_col, int32_t value_col, int32_t agg,
                         const char *target_name, char **err_out);

/* ---------- sheet view (Foglio fork) ---------- */

/* Zoom saved for the sheet in percent, 0 = not set. Setting it is not undoable; it is saved to .xlsx. */
uint32_t foglio_sheet_zoom(const FoglioBook *b, uint32_t sheet);
int32_t foglio_set_sheet_zoom(FoglioBook *b, uint32_t sheet, uint32_t zoom);

/* The sheet's AutoFilter as JSON {"range":"A1:L40","columns":[{"col_id":2,"values":["x"],"blank":false}]},
   NULL when there is none (free with foglio_string_free). Setting NULL or "" removes it. Not undoable. */
char *foglio_autofilter_get(const FoglioBook *b, uint32_t sheet);
int32_t foglio_autofilter_set(FoglioBook *b, uint32_t sheet, const char *json);

#ifdef __cplusplus
}
#endif

#endif // FOGLIO_FEATURES_H
