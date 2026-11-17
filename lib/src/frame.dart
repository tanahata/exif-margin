import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'photo_metadata.dart';

enum PhotoShape { portrait, square, landscape }

class FrameMargins {
  const FrameMargins({this.side = .02, this.top = .07, this.bottom = .20});
  final double side, top, bottom;
  void validate() {
    if (!side.isFinite ||
        !top.isFinite ||
        !bottom.isFinite ||
        side < 0 ||
        side > .2 ||
        top < 0 ||
        top > .2 ||
        bottom < .1 ||
        bottom > .5) {
      throw const FormatException('余白は左右・上0〜20%、下10〜50%にしてください。');
    }
  }
}

class FrameGeometry {
  const FrameGeometry({
    required this.photoWidth,
    required this.photoHeight,
    required this.side,
    required this.top,
    required this.bottom,
    required this.shape,
  });

  factory FrameGeometry.forPhoto(
    int width,
    int height, {
    FrameMargins margins = const FrameMargins(),
  }) {
    margins.validate();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('写真のサイズが正しくありません。');
    }
    final shortSide = math.min(width, height);
    final shape = width == height
        ? PhotoShape.square
        : width < height
        ? PhotoShape.portrait
        : PhotoShape.landscape;
    // Polaroid-style margins, relative to the original photo's short side.
    final side = margins.side, top = margins.top, bottom = margins.bottom;
    return FrameGeometry(
      photoWidth: width,
      photoHeight: height,
      side: (shortSide * side).round(),
      top: (shortSide * top).round(),
      bottom: (shortSide * bottom).round(),
      shape: shape,
    );
  }

  final int photoWidth;
  final int photoHeight;
  final int side;
  final int top;
  final int bottom;
  final PhotoShape shape;
  int get width => photoWidth + side * 2;
  int get height => photoHeight + top + bottom;
  String get label => switch (shape) {
    PhotoShape.portrait => '縦の写真',
    PhotoShape.square => '正方形の写真',
    PhotoShape.landscape => '横の写真',
  };
}

// Decoding and encoding run in an isolate, keeping the window responsive.
class PreparedPhoto {
  const PreparedPhoto(this.preview, this.geometry, this.metadata);
  final Uint8List preview;
  final FrameGeometry geometry;
  final PhotoMetadata metadata;
}

img.Image decodeOriented(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('写真を読み込めません。JPEGまたはPNGを選んでください。');
  }
  return img.bakeOrientation(decoded);
}

PreparedPhoto preparePhoto(Uint8List bytes) {
  final photo = decodeOriented(bytes);
  final geometry = FrameGeometry.forPhoto(photo.width, photo.height);
  // Only the screen preview is reduced. Export decodes the original bytes again.
  final longest = math.max(photo.width, photo.height);
  final preview = longest > 1600
      ? img.copyResize(
          photo,
          width: photo.width >= photo.height ? 1600 : null,
          height: photo.height > photo.width ? 1600 : null,
          interpolation: img.Interpolation.average,
        )
      : photo;
  return PreparedPhoto(
    img.encodePng(preview),
    geometry,
    PhotoMetadata.fromExif(photo.exif),
  );
}

img.Image addFrame(
  img.Image oriented, {
  FrameMargins margins = const FrameMargins(),
}) {
  final geometry = FrameGeometry.forPhoto(
    oriented.width,
    oriented.height,
    margins: margins,
  );
  final canvas = img.Image(width: geometry.width, height: geometry.height);
  // The macOS input pipeline converts pixels and the embedded profile to sRGB.
  canvas.iccProfile = oriented.iccProfile?.clone();
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(canvas, oriented, dstX: geometry.side, dstY: geometry.top);
  // The fresh canvas has no inherited Orientation, GPS, or thumbnail metadata.
  return canvas;
}

Uint8List renderJpeg(Uint8List source) => img.encodeJpg(
  addFrame(decodeOriented(source)),
  quality: 98,
  chroma: img.JpegChroma.yuv444,
);

class ExportRequest {
  const ExportRequest(
    this.source, {
    this.caption,
    this.mode = OutputMode.hq,
    this.iccProfile,
    this.margins = const FrameMargins(),
  });
  final FrameMargins margins;
  final Uint8List source;
  final Uint8List? caption;
  final OutputMode mode;
  final Uint8List? iccProfile;
}

enum OutputMode { hq, sns }

({int width, int height}) outputDimensions(FrameGeometry g, OutputMode mode) {
  final longest = math.max(g.width, g.height);
  final ratio = mode == OutputMode.sns && longest > 2048 ? 2048 / longest : 1.0;
  return (
    width: math.max(1, (g.width * ratio).round()),
    height: math.max(1, (g.height * ratio).round()),
  );
}

Uint8List renderExport(ExportRequest request) {
  final photo = decodeOriented(request.source);
  if (request.iccProfile != null) {
    photo.iccProfile = img.IccProfile(
      'sRGB',
      img.IccProfileCompression.none,
      request.iccProfile!,
    );
  }
  final geometry = FrameGeometry.forPhoto(
    photo.width,
    photo.height,
    margins: request.margins,
  );
  final canvas = addFrame(photo, margins: request.margins);
  if (request.caption != null) {
    final layer = img.decodePng(request.caption!);
    if (layer == null ||
        layer.width != geometry.width ||
        layer.height != geometry.bottom) {
      throw const FormatException('撮影情報のサイズが正しくありません。');
    }
    img.compositeImage(
      canvas,
      layer,
      dstY: geometry.top + geometry.photoHeight,
    );
  }
  final dimensions = outputDimensions(geometry, request.mode);
  final output =
      dimensions.width == canvas.width && dimensions.height == canvas.height
      ? canvas
      : img.copyResize(
          canvas,
          width: dimensions.width,
          height: dimensions.height,
          interpolation: img.Interpolation.average,
        );
  return img.encodeJpg(
    output,
    quality: request.mode == OutputMode.hq ? 95 : 90,
    chroma: img.JpegChroma.yuv420,
  );
}
