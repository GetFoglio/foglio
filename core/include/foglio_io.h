// foglio_io.h — open any common spreadsheet format, export CSV.
// Can be included together with foglio_core.h (in either order).
// Every char* returned (including *err_out) must be released with foglio_string_free.
#ifndef FOGLIO_IO_H
#define FOGLIO_IO_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef FOGLIO_BOOK_DEFINED
#define FOGLIO_BOOK_DEFINED
typedef struct FoglioBook FoglioBook;
#endif

// Opens a workbook, choosing the reader by extension (case-insensitive):
//   .xlsx .xlsm .xltx .xltm  IronCalc importer (full fidelity); values+formulas fallback if it fails
//   .xls .xlt .xlsb .ods  values, formulas (re-evaluated), dates (shown as dd/mm/yyyy)
//   .csv .tsv .txt     encoding (UTF-8/UTF-16 BOM/Windows-1252) and delimiter (, ; tab |)
//                      auto-detected; with ';' decimal commas ("1.234,56") become numbers;
//                      values starting with '=' are kept as text, never evaluated
//   anything else      sniffed from the content (zip -> xlsx/ods, OLE -> xls, else text)
// Returns NULL on failure and, if err_out is not NULL, stores a message in *err_out.
FoglioBook *foglio_open_any(const char *path, char **err_out);

// Writes the formatted values (what the user sees) of the used range of `sheet` (0-based)
// to `path`: UTF-8 without BOM, RFC 4180 quoting, CRLF line endings.
// `delimiter` is an ASCII byte such as ',' ';' or '\t' (0 means ',').
// The file is replaced atomically. Returns 0 on success, -1 on failure (message in *err_out).
int32_t foglio_save_csv(FoglioBook *b, uint32_t sheet, const char *path, uint8_t delimiter, char **err_out);

// 1 if `path` is a zip package with a VBA project (xl/vbaProject.bin), else 0.
int32_t foglio_has_macros(const char *path);

// Saves the workbook as .xlsm at `path`, keeping the VBA project (and its signatures) of
// `macro_source`, the macro-enabled file the workbook was opened from, and the code names that
// link the VBA document modules to the workbook and its sheets. Macros are never run or edited.
// The file is replaced atomically. Returns 0 on success, -1 on failure (message in *err_out).
int32_t foglio_save_xlsm(FoglioBook *b, const char *path, const char *macro_source, char **err_out);

// Comma-separated list of extensions foglio_open_any understands, lowercase without dots,
// e.g. "xlsx,xlsm,xltx,xltm,xls,xlt,xlsb,ods,csv,tsv,txt". Free with foglio_string_free.
char *foglio_supported_extensions(void);

#ifdef __cplusplus
}
#endif

#endif // FOGLIO_IO_H
