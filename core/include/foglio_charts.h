// foglio_charts.h — charts on worksheets (see src/charts.rs).
// Rows and columns are 1-based, sheets and chart indexes 0-based.
// Every char* returned must be released with foglio_string_free.
// Changes are undoable with foglio_undo (one step each) and are saved to/read from .xlsx.
#ifndef FOGLIO_CHARTS_H
#define FOGLIO_CHARTS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef FOGLIO_BOOK_DEFINED
#define FOGLIO_BOOK_DEFINED
typedef struct FoglioBook FoglioBook;
#endif

// Chart types (the `kind` strings):
//   "column" "column_stacked" "bar" "bar_stacked" "line" "line_markers"
//   "pie" "doughnut" "area" "area_stacked" "scatter"
// Legend positions: "none" "right" "top" "bottom" "left"

// JSON array, one object per chart:
//   {"index":0, "name":"Chart 1", "kind":"column", "title":"Sales" (absent = no title),
//    "legend":"bottom", "category_axis_title":..., "value_axis_title":... (optional),
//    "series":[{"name_ref":"Sheet1!$B$1", "name":..., "categories_ref":"Sheet1!$A$2:$A$5",
//               "values_ref":"Sheet1!$B$2:$B$5", "color":"4472C4"}],
//    "anchor":{"from":{"row":2,"col":5,"fy":0.0,"fx":0.0}, "to":{...}},   // cell + fraction of it
//    "data_range":"A1:C5" (or "Other!A1:C5", null if the series are not one rectangle)}
char *foglio_charts_json(const FoglioBook *b, uint32_t sheet);
int32_t foglio_chart_count(const FoglioBook *b, uint32_t sheet);

// Adds a chart for the data in r0..r1 x c0..c1, detecting series names, categories
// and orientation like Excel. Top-left corner at (at_row, at_col), or right of the
// data when at_row <= 0; default size 5 x 3 in. Returns the new index or -1.
int32_t foglio_chart_add(FoglioBook *b, uint32_t sheet, const char *kind,
                         int32_t r0, int32_t c0, int32_t r1, int32_t c1, int32_t at_row, int32_t at_col);

// Changes any of "kind", "title" (null or "" removes), "legend", "category_axis_title",
// "value_axis_title", "name", "series" given in a JSON object. Returns 0 or -1.
int32_t foglio_chart_update(FoglioBook *b, uint32_t sheet, uint32_t index, const char *json_patch);

// Moves/resizes: each corner is a cell plus fractions (0..1) of its height (fy) and width (fx).
int32_t foglio_chart_set_anchor(FoglioBook *b, uint32_t sheet, uint32_t index,
                                int32_t row0, int32_t col0, double fy0, double fx0,
                                int32_t row1, int32_t col1, double fy1, double fx1);

// Re-detects the series from a range such as "A1:C10" or "Sheet2!A1:C10".
int32_t foglio_chart_set_range(FoglioBook *b, uint32_t sheet, uint32_t index, const char *range);

int32_t foglio_chart_delete(FoglioBook *b, uint32_t sheet, uint32_t index);

// Evaluated data for drawing: JSON array of
//   {"name":"Sales", "color":"4472C4" (optional), "categories":["Jan",...] (formatted text),
//    "category_numbers":[1.0,null,...], "values":[10.0,null,...], "format":"#,##0.00"}
// Hidden rows/columns are left out, like Excel.
char *foglio_chart_data_json(const FoglioBook *b, uint32_t sheet, uint32_t index);

#ifdef __cplusplus
}
#endif

#endif // FOGLIO_CHARTS_H
