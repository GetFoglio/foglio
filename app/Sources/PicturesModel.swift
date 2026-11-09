import Foundation

// Pictures: Swift side of core/include/foglio_pictures.h. Rows/columns here are 0-based like the rest of the app.
// Sizes are in EMU (9525 per pixel at 96 dpi). On screen one such pixel is drawn as one logical point.

/// Cropping in thousandths of a percent cut off each side (100000 = 100%), like `a:srcRect`.
struct PictureCrop: Codable, Equatable {
    var l = 0, t = 0, r = 0, b = 0
    var isEmpty: Bool { l == 0 && t == 0 && r == 0 && b == 0 }
    /// Fractions (0...1) of the image width/height that stay visible.
    var visibleW: CGFloat { max(0.01, 1 - CGFloat(l + r) / 100_000) }
    var visibleH: CGFloat { max(0.01, 1 - CGFloat(t + b) / 100_000) }
    /// The visible part of a `w` x `h` image, in its pixels (top-left origin).
    func sourceRect(width w: CGFloat, height h: CGFloat) -> CGRect {
        CGRect(x: w * CGFloat(l) / 100_000, y: h * CGFloat(t) / 100_000, width: w * visibleW, height: h * visibleH)
    }
}

enum PictureEditAs: String { case oneCell = "one_cell", twoCell = "two_cell", absolute }

/// One picture of a sheet, as listed by the engine.
struct PictureInfo: Equatable {
    static let emuPerPoint: CGFloat = 9525
    var index: Int
    var name: String
    var descr: String
    var image: String          // key of the image bytes
    var format: String         // png, jpeg, gif, bmp, tiff, emf, wmf, bin
    var bytes: Int
    var pixelW: Int, pixelH: Int
    var from: ChartCorner
    var to: ChartCorner
    var cx: Int, cy: Int       // displayed size, EMU
    var editAs: PictureEditAs
    var crop: PictureCrop
    var inCell: Bool
    var z: Int

    /// Displayed size in logical points.
    var size: CGSize { CGSize(width: CGFloat(cx) / PictureInfo.emuPerPoint, height: CGFloat(cy) / PictureInfo.emuPerPoint) }
}

private struct RawPicture: Decodable {
    struct Corner: Decodable { let row: Int; let col: Int; let fy: Double; let fx: Double }
    let index: Int, name: String, descr: String, image: String, format: String, bytes: Int
    let pxW: Int, pxH: Int
    let from: Corner, to: Corner
    let cx: Int, cy: Int
    let editAs: String
    let crop: PictureCrop
    let inCell: Bool
    let z: Int
}

/// A chart or a picture, for stacking.
enum DrawingRef: Equatable { case chart(Int), picture(Int) }

private let pictureDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    return d
}()

/// A placement/edit for `Workbook.addPicture` / `updatePicture` (nil = unchanged).
struct PicturePatch {
    var from: ChartCorner?
    var size: CGSize?            // logical points
    var crop: PictureCrop?
    var name: String?
    var descr: String?
    var editAs: PictureEditAs?
    var inCell: Bool?

    var json: String {
        var d: [String: Any] = [:]
        if let f = from { d["from"] = ["row": f.row + 1, "col": f.col + 1, "fy": f.fy, "fx": f.fx] }
        if let s = size {
            d["cx"] = Int((max(1, s.width) * PictureInfo.emuPerPoint).rounded())
            d["cy"] = Int((max(1, s.height) * PictureInfo.emuPerPoint).rounded())
        }
        if let c = crop { d["crop"] = ["l": c.l, "t": c.t, "r": c.r, "b": c.b] }
        if let name { d["name"] = name }
        if let descr { d["descr"] = descr }
        if let editAs { d["edit_as"] = editAs.rawValue }
        if let inCell { d["in_cell"] = inCell }
        guard let data = try? JSONSerialization.data(withJSONObject: d) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

extension Workbook {
    func pictures(sheet: Int) -> [PictureInfo] {
        guard let json = Workbook.take(foglio_pictures_json(rawPtr, UInt32(sheet))),
              let raw = try? pictureDecoder.decode([RawPicture].self, from: Data(json.utf8)) else { return [] }
        return raw.map { r in
            PictureInfo(index: r.index, name: r.name, descr: r.descr, image: r.image, format: r.format, bytes: r.bytes,
                        pixelW: r.pxW, pixelH: r.pxH,
                        from: ChartCorner(row: r.from.row - 1, col: r.from.col - 1, fy: r.from.fy, fx: r.from.fx),
                        to: ChartCorner(row: r.to.row - 1, col: r.to.col - 1, fy: r.to.fy, fx: r.to.fx),
                        cx: r.cx, cy: r.cy, editAs: PictureEditAs(rawValue: r.editAs) ?? .oneCell, crop: r.crop,
                        inCell: r.inCell, z: r.z)
        }
    }

    /// The bytes of an image (key from `PictureInfo.image`).
    func pictureImageData(sheet: Int, key: String) -> Data? {
        var len = 0
        guard let p = foglio_picture_image(rawPtr, UInt32(sheet), key, &len) else { return nil }
        defer { foglio_bytes_free(p, len) }
        return Data(bytes: p, count: len)
    }

    /// Adds a picture (PNG/JPEG/GIF/BMP/TIFF bytes). Returns its index.
    @discardableResult
    func addPicture(sheet: Int, data: Data, _ patch: PicturePatch) -> Int? {
        let i = data.withUnsafeBytes { buf in
            foglio_picture_add(rawPtr, UInt32(sheet), buf.bindMemory(to: UInt8.self).baseAddress, buf.count, patch.json)
        }
        return i >= 0 ? Int(i) : nil
    }

    /// Changes a picture; with `data` it also shows a new image. One undo step.
    @discardableResult
    func updatePicture(sheet: Int, index: Int, _ patch: PicturePatch, data: Data? = nil) -> Bool {
        if let data {
            return data.withUnsafeBytes { buf in
                foglio_picture_update(rawPtr, UInt32(sheet), UInt32(index), patch.json, buf.bindMemory(to: UInt8.self).baseAddress, buf.count)
            } == 0
        }
        return foglio_picture_update(rawPtr, UInt32(sheet), UInt32(index), patch.json, nil, 0) == 0
    }

    @discardableResult
    func deletePicture(sheet: Int, index: Int) -> Bool { foglio_picture_delete(rawPtr, UInt32(sheet), UInt32(index)) == 0 }

    /// Charts and pictures from back to front.
    func drawingOrder(sheet: Int) -> [DrawingRef] {
        guard let json = Workbook.take(foglio_drawing_order_json(rawPtr, UInt32(sheet))),
              let list = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [[String: Any]] else { return [] }
        return list.compactMap { o in
            guard let i = o["index"] as? Int else { return nil }
            return (o["kind"] as? String) == "chart" ? .chart(i) : .picture(i)
        }
    }

    /// how: "forward", "backward", "front", "back".
    @discardableResult
    func restack(sheet: Int, _ ref: DrawingRef, _ how: String) -> Bool {
        switch ref {
        case .chart(let i): return foglio_drawing_restack(rawPtr, UInt32(sheet), "chart", UInt32(i), how) == 0
        case .picture(let i): return foglio_drawing_restack(rawPtr, UInt32(sheet), "picture", UInt32(i), how) == 0
        }
    }
}
