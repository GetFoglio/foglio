// foglio_core.h — C ABI over the IronCalc engine.
// Rows and columns are 1-based (like Excel). Sheets are 0-based.
// Every char* returned must be released with foglio_string_free.
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifndef FOGLIO_BOOK_DEFINED
#define FOGLIO_BOOK_DEFINED
typedef struct FoglioBook FoglioBook;
#endif

enum { FOGLIO_KIND_TEXT = 0, FOGLIO_KIND_NUMBER = 1, FOGLIO_KIND_BOOL = 2, FOGLIO_KIND_ERROR = 3 };
enum { FOGLIO_ALIGN_GENERAL = 0, FOGLIO_ALIGN_LEFT = 1, FOGLIO_ALIGN_CENTER = 2, FOGLIO_ALIGN_RIGHT = 3 };
#define FOGLIO_NO_COLOR 0xFFFFFFFFu

typedef struct {
    int32_t row, col;
    uint32_t text_off, text_len;   // slice into FoglioViewport.text (UTF-8)
    uint8_t kind, align, bold, italic;
    uint32_t fg;                   // 0xRRGGBB or FOGLIO_NO_COLOR
    uint32_t bg;                   // 0xRRGGBB or FOGLIO_NO_COLOR
    uint8_t font_size;             // points, Excel units (11 = default)
    uint8_t underline, strike, wrap;
    uint8_t valign;                // 0 bottom, 1 center, 2 top
    uint8_t border_mask;           // bit0 top, bit1 right, bit2 bottom, bit3 left
    uint8_t border_weight;         // 2 bits per side (top, right, bottom, left from low bits): 1 thin, 2 medium, 3 thick
    uint8_t _pad;
    uint32_t border_colors[4];     // top, right, bottom, left: 0xRRGGBB or FOGLIO_NO_COLOR (= automatic)
} FoglioCell;

typedef struct {
    const FoglioCell *cells; size_t count;
    const uint8_t *text; size_t text_len;
} FoglioViewport;

// Locale ("en", "en-GB", "it", "de", "es", "fr"), function-name language ("en", "it", "de", "es", "fr"), IANA timezone.
// Applies to workbooks created or opened afterwards.
void foglio_set_locale(const char *locale, const char *language, const char *tz);

FoglioBook *foglio_new(void);
FoglioBook *foglio_open_xlsx(const char *path, char **err_out);
int32_t foglio_save_xlsx(FoglioBook *b, const char *path, char **err_out);
void foglio_free(FoglioBook *b);
void foglio_string_free(char *s);

uint32_t foglio_sheet_count(const FoglioBook *b);
char *foglio_sheet_name(const FoglioBook *b, uint32_t sheet);
int32_t foglio_add_sheet(FoglioBook *b);

int32_t foglio_set_input(FoglioBook *b, uint32_t sheet, int32_t row, int32_t col, const char *utf8);
char *foglio_get_input(const FoglioBook *b, uint32_t sheet, int32_t row, int32_t col);
char *foglio_get_formatted(const FoglioBook *b, uint32_t sheet, int32_t row, int32_t col);
int32_t foglio_clear_range(FoglioBook *b, uint32_t sheet, int32_t r0, int32_t c0, int32_t r1, int32_t c1);
int32_t foglio_set_style(FoglioBook *b, uint32_t sheet, int32_t r0, int32_t c0, int32_t r1, int32_t c1,
                         const char *style_path, const char *value);
// Drag the fill handle: extend the source range down to to_row (to_col == 0) or right to to_col (to_row == 0).
int32_t foglio_autofill(FoglioBook *b, uint32_t sheet, int32_t r0, int32_t c0, int32_t r1, int32_t c1,
                        int32_t to_row, int32_t to_col);
// Paste tab/newline separated text starting at (row, col), one undo step, one recalculation.
int32_t foglio_paste_tsv(FoglioBook *b, uint32_t sheet, int32_t row, int32_t col, const char *tsv);

int32_t foglio_undo(FoglioBook *b);
int32_t foglio_redo(FoglioBook *b);
bool foglio_can_undo(const FoglioBook *b);
bool foglio_can_redo(const FoglioBook *b);


// Benchmark helper: full workbook evaluation, returns elapsed microseconds.
uint64_t foglio_evaluate_us(FoglioBook *b);

#include "foglio_ui.h"
