// foglio_pictures.h — pictures on worksheets (see src/pictures.rs).
// Rows and columns are 1-based, sheets and picture indexes 0-based.
// Sizes are in EMU: 914400 per inch, 12700 per point, 9525 per pixel at 96 dpi.
// Every char* returned must be released with foglio_string_free.
// Changes are undoable with foglio_undo (one step each; group several with
// foglio_begin_group/foglio_end_group from foglio_ui.h) and are saved to/read from .xlsx.
// The engine stores image bytes only; decoding, cropping and resampling are up to the app.
#ifndef FOGLIO_PICTURES_H
#define FOGLIO_PICTURES_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef FOGLIO_BOOK_DEFINED
#define FOGLIO_BOOK_DEFINED
typedef struct FoglioBook FoglioBook;
#endif

// JSON array, one object per picture:
//   {"index":0, "name":"Picture 1", "descr":"alt text", "image":"<key>", "format":"png"|"jpeg"|"gif"|"bmp"|"tiff"|"emf"|"wmf"|"bin",
//    "bytes":12345, "px_w":640, "px_h":480 (0 if unknown),
//    "from":{"row":2,"col":3,"fy":0.0,"fx":0.25}, "to":{...},   // cell + fraction of it
//    "cx":3810000, "cy":2857500,       // displayed size (two_cell pictures: what the anchor spans)
//    "edit_as":"one_cell"|"two_cell"|"absolute",
//    "crop":{"l":0,"t":0,"r":0,"b":0},   // thousandths of a percent cut off each side
//    "in_cell":false,                 // Place in Cell: fitted in the cell of "from", aspect cx:cy
//    "z":3}                           // stacking order shared with charts (higher = in front)
char *foglio_pictures_json(const FoglioBook *b, uint32_t sheet);
int32_t foglio_picture_count(const FoglioBook *b, uint32_t sheet);

// Copy of an image's bytes (key from "image"); free with foglio_bytes_free.
uint8_t *foglio_picture_image(const FoglioBook *b, uint32_t sheet, const char *key, size_t *len);
void foglio_bytes_free(uint8_t *p, size_t len);

// Placement/edit patch (JSON object, every key optional):
//   "from":{"row","col","fy","fx"}  top-left corner (in-cell pictures: the cell)
//   "cx","cy"                       size in EMU (in-cell: only the aspect ratio counts)
//   "crop":{"l","t","r","b"}  "name"  "descr"  "edit_as"  "in_cell":true|false
// in_cell true = Place in Cell (fitted, centred, moves and sizes with the cell);
// false on an in-cell picture = Place over Cells (a one_cell picture where it was).

// Adds a picture showing `data` (PNG, JPEG, GIF, BMP, TIFF, EMF or WMF bytes; the app converts
// other formats). Default size: the image's pixel size; default place: A1.
// Returns the new index or -1.
int32_t foglio_picture_add(FoglioBook *b, uint32_t sheet, const uint8_t *data, size_t len, const char *json_patch);

// Applies the patch to picture `index`; with `data` (may be NULL) it also replaces the
// image (Change Picture, Compress Pictures). Returns 0 or -1.
int32_t foglio_picture_update(FoglioBook *b, uint32_t sheet, uint32_t index, const char *json_patch,
                              const uint8_t *data, size_t len);

int32_t foglio_picture_delete(FoglioBook *b, uint32_t sheet, uint32_t index);

// Charts and pictures from back to front: [{"kind":"chart"|"picture","index":0}, ...]
char *foglio_drawing_order_json(const FoglioBook *b, uint32_t sheet);
// kind: "chart" | "picture"; how: "forward" | "backward" | "front" | "back".
int32_t foglio_drawing_restack(FoglioBook *b, uint32_t sheet, const char *kind, uint32_t index, const char *how);

#ifdef __cplusplus
}
#endif

#endif // FOGLIO_PICTURES_H
