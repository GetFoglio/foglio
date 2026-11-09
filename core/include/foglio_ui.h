// foglio_ui.h — UI-facing calls (see src/ui.rs). Included by foglio_core.h.
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

// Hot path: every non-empty (or styled) cell in the inclusive range, in one call.
FoglioViewport *foglio_viewport(FoglioBook *b, uint32_t sheet, int32_t r0, int32_t c0, int32_t r1, int32_t c1);
void foglio_viewport_free(FoglioViewport *v);

typedef struct {
    uint8_t bold, italic, underline, strike, align, valign, wrap, font_size;
    uint32_t fg, bg;
    char *num_fmt;  // free with foglio_string_free
} FoglioStyle;
int32_t foglio_style_at(FoglioBook *b, uint32_t sheet, int32_t row, int32_t col, FoglioStyle *out);

typedef struct { int32_t index; uint8_t hidden; double size; } FoglioAxisEntry;   // size in engine px
typedef struct {
    const FoglioAxisEntry *cols; size_t ncols;
    const FoglioAxisEntry *rows; size_t nrows;
    double default_col, default_row;
    int32_t frozen_rows, frozen_cols;
    uint8_t show_grid;
    int32_t max_row, max_col;          // used range (1-based)
} FoglioLayout;
FoglioLayout *foglio_layout(const FoglioBook *b, uint32_t sheet);
void foglio_layout_free(FoglioLayout *l);
int32_t foglio_set_col_width(FoglioBook *b, uint32_t sheet, int32_t c0, int32_t c1, double px);
int32_t foglio_set_row_height(FoglioBook *b, uint32_t sheet, int32_t r0, int32_t r1, double px);
int32_t foglio_set_hidden(FoglioBook *b, uint32_t sheet, bool is_rows, int32_t i0, int32_t i1, bool hidden);
int32_t foglio_set_frozen(FoglioBook *b, uint32_t sheet, int32_t rows, int32_t cols);
int32_t foglio_set_show_grid(FoglioBook *b, uint32_t sheet, bool show);

// op: 0 insert rows, 1 delete rows, 2 insert columns, 3 delete columns
int32_t foglio_structure(FoglioBook *b, uint32_t sheet, int32_t op, int32_t index, int32_t count);
// op: 0 rename(name), 1 delete, 2 move to arg, 3 duplicate, 4 hide, 5 unhide
int32_t foglio_sheet_op(FoglioBook *b, uint32_t sheet, int32_t op, uint32_t arg, const char *name);
int32_t foglio_sheet_hidden(const FoglioBook *b, uint32_t sheet);

int32_t *foglio_merges(const FoglioBook *b, uint32_t sheet, size_t *out_n);   // 4 ints per merge
void foglio_ints_free(int32_t *p, size_t len);
int32_t foglio_merge(FoglioBook *b, uint32_t sheet, int32_t r0, int32_t c0, int32_t r1, int32_t c1, int32_t mode);

int32_t foglio_set_border(FoglioBook *b, uint32_t sheet, int32_t r0, int32_t c0, int32_t r1, int32_t c1,
                          const char *kind, const char *style, const char *color);
int32_t foglio_clear_formats(FoglioBook *b, uint32_t sheet, int32_t r0, int32_t c0, int32_t r1, int32_t c1);

char *foglio_copy(FoglioBook *b, uint32_t sheet, int32_t r0, int32_t c0, int32_t r1, int32_t c1, uint64_t *out_token);
int32_t foglio_paste_internal(FoglioBook *b, uint32_t sheet, int32_t r0, int32_t c0, int32_t r1, int32_t c1,
                              uint64_t token, bool is_cut);
int32_t foglio_paste_text(FoglioBook *b, uint32_t sheet, int32_t row, int32_t col, const char *tsv);

int32_t foglio_sort(FoglioBook *b, uint32_t sheet, int32_t r0, int32_t c0, int32_t r1, int32_t c1, int32_t key_col, bool ascending);
int32_t foglio_current_region(const FoglioBook *b, uint32_t sheet, int32_t row, int32_t col, int32_t *out4);
int32_t foglio_jump(const FoglioBook *b, uint32_t sheet, int32_t row, int32_t col, int32_t dr, int32_t dc, int32_t *out2);

typedef struct { uint64_t count, numeric; double sum, min, max; } FoglioStats;
int32_t foglio_stats(const FoglioBook *b, uint32_t sheet, int32_t r0, int32_t c0, int32_t r1, int32_t c1, FoglioStats *out);

int32_t foglio_find(const FoglioBook *b, uint32_t sheet, int32_t row, int32_t col, const char *query, uint32_t flags, int32_t *out2);
int32_t foglio_replace_all(FoglioBook *b, uint32_t sheet, const char *query, const char *repl, uint32_t flags);

// "LOCALIZED\tENGLISH" per line, for the current language.
char *foglio_function_names(void);
typedef struct { uint8_t kind; uint32_t replace_from; uint32_t arg_index; char *name; } FoglioCompletion;
int32_t foglio_completion(FoglioBook *b, uint32_t sheet, int32_t row, int32_t col, const char *formula, uint32_t cursor, FoglioCompletion *out);
char *foglio_cycle_reference(const FoglioBook *b, const char *text, uint32_t start, uint32_t end, int32_t *out2);
char *foglio_unique_values(const FoglioBook *b, uint32_t sheet, int32_t col, int32_t r0, int32_t r1);

// Conditional formatting (see src/ui.rs for kind/op/style codes). v1/v2 are typed values (may be NULL).
int32_t foglio_add_cf(FoglioBook *b, uint32_t sheet, int32_t r0, int32_t c0, int32_t r1, int32_t c1,
                      uint32_t kind, uint32_t op, const char *v1, const char *v2, uint32_t style);
// Removes rules intersecting the area; r0 <= 0 clears the whole sheet. Returns the number removed.
int32_t foglio_clear_cf(FoglioBook *b, uint32_t sheet, int32_t r0, int32_t c0, int32_t r1, int32_t c1);
