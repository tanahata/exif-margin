import Cocoa
import FlutterMacOS
import ImageIO
import UniformTypeIdentifiers

class MainFlutterWindow: NSWindow {
  private var imageChannel: FlutterMethodChannel?
  override func awakeFromNib() {
    let controller = FlutterViewController()
    let initialFrame = frame
    contentViewController = controller
    let visible = (screen ?? NSScreen.main)?.visibleFrame
    let defaultFrame = frameRect(forContentRect: NSRect(x: 0, y: 0, width: 1100, height: 740))
    let width = min(defaultFrame.width, visible?.width ?? defaultFrame.width)
    let height = min(defaultFrame.height, visible?.height ?? defaultFrame.height)
    minSize = NSSize(width: min(1000, width), height: min(680, height))
    setFrame(
      NSRect(
        x: visible.map { $0.midX - width / 2 } ?? initialFrame.minX,
        y: visible.map { $0.midY - height / 2 } ?? initialFrame.minY,
        width: width,
        height: height
      ),
      display: true
    )
    RegisterGeneratedPlugins(registry: controller)
    let channel = FlutterMethodChannel(name: "local.photoframe/image", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      DispatchQueue.global(qos: .userInitiated).async {
        autoreleasepool {
          do {
            let value: Any
            if call.method == "normalize", let bytes = call.arguments as? FlutterStandardTypedData {
              value = try normalizePhoto(bytes.data)
            } else if call.method == "copyExifWithoutGps", let args = call.arguments as? [String: Any],
                      let original = args["original"] as? FlutterStandardTypedData,
                      let jpeg = args["jpeg"] as? FlutterStandardTypedData {
              value = FlutterStandardTypedData(bytes: try copyExifWithoutGps(original.data, jpeg.data))
            } else { DispatchQueue.main.async { result(FlutterMethodNotImplemented) }; return }
            DispatchQueue.main.async { result(value) }
          } catch {
            DispatchQueue.main.async { result(FlutterError(code: "image_metadata", message: error.localizedDescription, details: nil)) }
          }
        }
      }
    }
    imageChannel = channel
    super.awakeFromNib()
    title = "EXIF Margin"
  }
}

private func imageError(_ message: String) -> NSError {
  NSError(domain: "PhotoFrame", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

// Generate a fresh EXIF block from standard TIFF/EXIF fields and insert it into
// the already encoded JPEG. No GPS, XMP, thumbnail or opaque maker-note data is copied.
func copyExifWithoutGps(_ original: Data, _ jpeg: Data) throws -> Data {
  guard let input = CGImageSourceCreateWithData(original as CFData, nil),
        let props = CGImageSourceCopyPropertiesAtIndex(input, 0, nil) as? [CFString: Any],
        let encoded = CGImageSourceCreateWithData(jpeg as CFData, nil),
        let dimensions = CGImageSourceCopyPropertiesAtIndex(encoded, 0, nil) as? [CFString: Any],
        let w = dimensions[kCGImagePropertyPixelWidth] as? Int,
        let h = dimensions[kCGImagePropertyPixelHeight] as? Int else { throw imageError("撮影情報を読み込めません。") }
  func sanitized(_ dict: [CFString: Any]) -> [CFString: Any] {
    dict.filter { key, value in
      let name = (key as String).lowercased()
      return !name.contains("gps") && !name.contains("maker") && !name.contains("thumbnail") && !(value is Data) && !(value is NSDictionary)
    }
  }
  var tiff = sanitized(props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:])
  var exif = sanitized(props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:])
  if (exif[kCGImagePropertyExifLensModel] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
    let aux = props[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]
    let auxiliary = (aux[kCGImagePropertyExifAuxLensModel] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let lens = auxiliary?.isEmpty == false ? auxiliary : panasonicLensModel(original), !lens.isEmpty {
      exif[kCGImagePropertyExifLensModel] = lens
    }
  }
  // The image has already been rotated and resized; copied pixel dimensions and orientation must match it.
  tiff[kCGImagePropertyTIFFOrientation] = 1
  exif[kCGImagePropertyExifColorSpace] = 1 // The exported pixels have been converted to sRGB.
  exif[kCGImagePropertyExifPixelXDimension] = w
  exif[kCGImagePropertyExifPixelYDimension] = h
  let rewritten = NSMutableData()
  guard let destination = CGImageDestinationCreateWithData(rewritten, UTType.jpeg.identifier as CFString, 1, nil) else { throw imageError("撮影情報を準備できません。") }
  let options: [CFString: Any] = [kCGImagePropertyTIFFDictionary: tiff, kCGImagePropertyExifDictionary: exif,
    kCGImagePropertyOrientation: 1, kCGImageMetadataShouldExcludeGPS: true,
    kCGImageMetadataShouldExcludeXMP: true, kCGImageDestinationEmbedThumbnail: false]
  CGImageDestinationAddImageFromSource(destination, encoded, 0, options as CFDictionary)
  guard CGImageDestinationFinalize(destination) else { throw imageError("撮影情報を保存できません。") }
  let bytes = [UInt8](rewritten as Data)
  var offset = 2
  var segment: Data?
  while offset + 4 <= bytes.count, bytes[offset] == 0xff {
    let marker = bytes[offset + 1]
    if marker == 0xda || marker == 0xd9 { break }
    let len = Int(bytes[offset + 2]) * 256 + Int(bytes[offset + 3])
    guard len >= 2, offset + 2 + len <= bytes.count else { throw imageError("撮影情報の形式が正しくありません。") }
    if marker == 0xe1 && len >= 8 && Array(bytes[(offset+4)..<(offset+10)]) == [69,120,105,102,0,0] {
      segment = Data(bytes[offset..<(offset+2+len)]); break
    }
    offset += 2 + len
  }
  guard let block = segment, jpeg.count >= 2, jpeg[0] == 0xff, jpeg[1] == 0xd8 else { throw imageError("撮影情報を保存できません。") }
  var result = Data(jpeg.prefix(2)); result.append(block); result.append(jpeg.dropFirst(2)); return result
}

func normalizePhoto(_ data: Data) throws -> [String: Any] {
  guard let source = CGImageSourceCreateWithData(data as CFData, nil),
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = props[kCGImagePropertyPixelWidth] as? Int,
        let height = props[kCGImagePropertyPixelHeight] as? Int,
        width > 0, height > 0 else { throw imageError("写真を読み込めません。JPEGまたはPNGを選んでください。") }
  guard width <= 30000, height <= 30000, Int64(width)*Int64(height) <= 100_000_000 else {
    throw imageError("この写真は大きすぎます。1億画素・1辺30000px以下の写真を選んでください。")
  }
  let options: [CFString:Any] = [kCGImageSourceCreateThumbnailFromImageAlways:true,
    kCGImageSourceCreateThumbnailWithTransform:true, kCGImageSourceThumbnailMaxPixelSize:max(width,height),
    kCGImageSourceShouldCacheImmediately:true]
  guard let oriented = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(data:nil, width:oriented.width, height:oriented.height,
          bitsPerComponent:8, bytesPerRow:0, space:colorSpace,
          bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw imageError("写真の向き・色を処理できません。") }
  context.interpolationQuality = .none
  context.draw(oriented, in: CGRect(x:0,y:0,width:oriented.width,height:oriented.height))
  guard let image = context.makeImage() else { throw imageError("画像の変換に失敗しました。") }
  let output = NSMutableData()
  guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw imageError("画像を準備できません。") }
  CGImageDestinationAddImage(destination,image,nil)
  guard CGImageDestinationFinalize(destination) else { throw imageError("画像の準備に失敗しました。") }
  let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString:Any] ?? [:]
  let exif = props[kCGImagePropertyExifDictionary] as? [CFString:Any] ?? [:]
  var metadata: [String:Any] = [:]
  metadata["make"] = tiff[kCGImagePropertyTIFFMake]
  metadata["model"] = tiff[kCGImagePropertyTIFFModel]
  metadata["lensMake"] = exif[kCGImagePropertyExifLensMake]
  metadata["lensModel"] = exif[kCGImagePropertyExifLensModel]
  if (metadata["lensModel"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
    let aux = props[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]
    let auxiliary = (aux[kCGImagePropertyExifAuxLensModel] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    metadata["lensModel"] = auxiliary?.isEmpty == false ? auxiliary : panasonicLensModel(data)
  }
  metadata["focal"] = exif[kCGImagePropertyExifFocalLength]
  metadata["focal35"] = exif[kCGImagePropertyExifFocalLenIn35mmFilm]
  metadata["aperture"] = exif[kCGImagePropertyExifFNumber]
  metadata["exposure"] = exif[kCGImagePropertyExifExposureTime]
  if let values = exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber], let first = values.first, first.intValue > 0, first.intValue < 65535 {
    metadata["iso"] = first
  } else { metadata["iso"] = exif[kCGImagePropertyExifISOSpeed] }
  guard let icc = colorSpace.copyICCData() else { throw imageError("sRGBプロファイルを取得できません。") }
  return ["png":FlutterStandardTypedData(bytes:output as Data),"metadata":metadata,"icc":FlutterStandardTypedData(bytes:icc as Data)]
}

// Panasonic MakerNote tag 0x0051 contains the recorded lens string.
// https://exiftool.org/TagNames/Panasonic.html
// Read only bounded JPEG APP1/TIFF metadata; never scan image pixels for text.
func panasonicLensModel(_ data: Data) -> String? {
  let bytes = [UInt8](data)
  guard bytes.count >= 4, bytes[0] == 0xff, bytes[1] == 0xd8 else { return nil }
  var cursor = 2
  while cursor + 4 <= bytes.count {
    guard bytes[cursor] == 0xff else { return nil }
    while cursor < bytes.count && bytes[cursor] == 0xff { cursor += 1 }
    guard cursor < bytes.count else { return nil }
    let marker = bytes[cursor]; cursor += 1
    if marker == 0xda || marker == 0xd9 { return nil }
    if marker == 0x01 || (0xd0...0xd7).contains(marker) { continue }
    guard cursor + 2 <= bytes.count else { return nil }
    let length = Int(bytes[cursor]) * 256 + Int(bytes[cursor + 1])
    guard length >= 2, length <= bytes.count - cursor else { return nil }
    let start = cursor + 2, end = cursor + length
    cursor = end
    guard marker == 0xe1, end - start >= 14,
      Array(bytes[start..<start+6]) == [69,120,105,102,0,0] else { continue }
    let base = start + 6, size = end - base
    let little: Bool
    if bytes[base] == 73 && bytes[base+1] == 73 { little = true }
    else if bytes[base] == 77 && bytes[base+1] == 77 { little = false }
    else { continue }
    func number(_ offset: Int, _ count: Int) -> Int? {
      guard offset >= 0, count <= size, offset <= size - count else { return nil }
      var result = 0
      for i in 0..<count {
        result |= Int(bytes[base + offset + i]) << (8 * (little ? i : count - 1 - i))
      }
      return result
    }
    func entry(_ ifd: Int, _ tag: Int) -> Int? {
      guard let count = number(ifd, 2), count <= 4096,
        ifd <= size - 2, count <= (size - ifd - 2) / 12 else { return nil }
      for i in 0..<count {
        let p = ifd + 2 + i * 12
        if number(p, 2) == tag { return p }
      }
      return nil
    }
    guard number(2,2) == 42, let first = number(4,4),
      let exifEntry = entry(first,0x8769), number(exifEntry+2,2) == 4,
      number(exifEntry+4,4) == 1, let exif = number(exifEntry+8,4),
      let noteEntry = entry(exif,0x927c), number(noteEntry+2,2) == 7,
      let noteCount = number(noteEntry+4,4), noteCount >= 14,
      let note = number(noteEntry+8,4), note <= size - noteCount,
      Array(bytes[base+note..<base+note+12]) == [80,97,110,97,115,111,110,105,99,0,0,0],
      let lens = entry(note+12,0x0051), lens + 12 <= note + noteCount,
      number(lens+2,2) == 2, let count = number(lens+4,4), count > 1, count <= 256,
      let value = number(lens+8,4) else { continue }
    let offset = count <= 4 ? lens + 8 : value
    guard offset >= note, offset <= note + noteCount - count else { continue }
    let content = bytes[(base+offset)..<(base+offset+count)].prefix { $0 != 0 }
    guard !content.isEmpty, content.allSatisfy({ $0 >= 32 && $0 < 127 }),
      let text = String(bytes:content,encoding:.ascii)?.trimmingCharacters(in:.whitespacesAndNewlines),
      !text.isEmpty else { continue }
    return text
  }
  return nil
}
