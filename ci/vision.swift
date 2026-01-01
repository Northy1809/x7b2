// Reads every photo of the test set with Apple Vision the way the app does
// on the phone (mobile_scanner analyzeImage: CIImage(contentsOf:), .up),
// on the raw file and on the app's upright copy (orientation applied, short
// side at most 2400, JPEG 92), plus simple clearer crops when both miss.
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

let dir = CommandLine.arguments[1]
let ctx = CIContext()

func read(_ image: CIImage) -> [String] {
    let handler = VNImageRequestHandler(ciImage: image, orientation: .up, options: [:])
    let req = VNDetectBarcodesRequest()
    do { try handler.perform([req]) } catch { return ["ERR \(error.localizedDescription)"] }
    return (req.results ?? []).compactMap { $0.payloadStringValue }
}

func upright(_ url: URL) -> CIImage? {
    guard var im = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { return nil }
    let w = im.extent.width, h = im.extent.height
    let r = min(1.0, max(2400 / w, 2400 / h))
    if r < 1 { im = im.transformed(by: CGAffineTransform(scaleX: r, y: r)) }
    // Through a JPEG like flutter_image_compress.
    let out = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("u.jpg")
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    try? ctx.writeJPEGRepresentation(of: im, to: out, colorSpace: cs,
                                     options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.92])
    return CIImage(contentsOf: out)
}

func clearer(_ im: CIImage) -> [CIImage] {
    let e = im.extent
    func crop(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CIImage {
        var c = im.cropped(to: CGRect(x: e.width * x0, y: e.height * y0, width: e.width * (x1 - x0), height: e.height * (y1 - y0)))
        c = c.transformed(by: CGAffineTransform(translationX: -c.extent.minX, y: -c.extent.minY))
        let long = max(c.extent.width, c.extent.height)
        if long < 1600 { c = c.transformed(by: CGAffineTransform(scaleX: 1600 / long, y: 1600 / long)) }
        return c.applyingFilter("CIColorControls", parameters: ["inputSaturation": 0, "inputContrast": 1.4])
    }
    let whole = im.applyingFilter("CIColorControls", parameters: ["inputSaturation": 0, "inputContrast": 1.4])
    return [whole, crop(0.2, 0.2, 0.8, 0.8), crop(0, 0.3, 1, 0.7)]
}

func norm(_ s: String) -> String {
    var t = s
    while t.hasPrefix("0") { t.removeFirst() }
    return t
}

struct Item: Decodable { let file: String; let code: String; let kind: String; let how: String? }
struct Manifest: Decodable { let items: [Item] }
let data = try! Data(contentsOf: URL(fileURLWithPath: dir + "/manifest.json"))
let items = try! JSONDecoder().decode(Manifest.self, from: data).items

var stats: [String: [Int]] = [:]
for it in items where it.kind != "front" {
    let url = URL(fileURLWithPath: dir + "/" + it.file)
    let key = it.kind == "hard" ? "hard-\(it.how ?? "")" : it.kind
    let raw = CIImage(contentsOf: url).map(read) ?? []
    let up = upright(url)
    var got = up.map(read) ?? []
    var via = "upright"
    let want = norm(it.code)
    if !got.contains(where: { norm($0) == want }), let u = up {
        via = "none"
        for (i, v) in clearer(u).enumerated() {
            let r = read(v)
            if r.contains(where: { norm($0) == want }) { got = r; via = "clearer\(i)"; break }
        }
    }
    let rawOk = raw.contains { norm($0) == want }
    let ok = got.contains { norm($0) == want }
    let wrong = got.filter { norm($0) != want && $0.allSatisfy(\.isNumber) }
    var s = stats[key] ?? [0, 0, 0, 0]
    s[0] += rawOk ? 1 : 0; s[1] += ok ? 1 : 0; s[2] += 1; s[3] += wrong.isEmpty ? 0 : 1
    stats[key] = s
    print("\(ok ? "OK  " : "MISS") \(it.file) raw=\(rawOk ? "ok" : "no") via=\(via) got=\(got) ")
}
print("SUMMARY (raw file / app pipeline / total / other numbers read)")
for (k, s) in stats.sorted(by: { $0.key < $1.key }) {
    print("\(k): raw \(s[0])/\(s[2])  app \(s[1])/\(s[2])  wrong \(s[3])")
}
