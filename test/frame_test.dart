import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_frame/src/frame.dart';

void main() {
  test('指定の余白を短辺から計算する', () {
    final portrait = FrameGeometry.forPhoto(1000, 1500);
    expect([portrait.side, portrait.top, portrait.bottom], [20, 70, 200]);
    expect([portrait.width, portrait.height], [1040, 1770]);
    final square = FrameGeometry.forPhoto(1000, 1000);
    expect([square.side, square.top, square.bottom], [20, 70, 200]);
    expect([square.width, square.height], [1040, 1270]);
    final landscape = FrameGeometry.forPhoto(1500, 1000);
    expect([landscape.side, landscape.top, landscape.bottom], [20, 70, 200]);
    expect([landscape.width, landscape.height], [1540, 1270]);
    expect(FrameGeometry.forPhoto(101, 200).side, 2);
  });

  test('白フレームの配置が正しく、元の画素数を保つ', () {
    final source = img.Image(width: 100, height: 200);
    img.fill(source, color: img.ColorRgb8(20, 40, 60));
    final framed = addFrame(source);
    expect([framed.width, framed.height], [104, 227]);
    final white = framed.getPixel(0, 0);
    expect([white.r, white.g, white.b], [255, 255, 255]);
    final first = framed.getPixel(2, 7);
    final last = framed.getPixel(101, 206);
    expect([first.r, first.g, first.b], [20, 40, 60]);
    expect([last.r, last.g, last.b], [20, 40, 60]);
    expect(framed.getPixel(102, 207).r, 255);
    expect([source.width, source.height], [100, 200]);
  });

  for (var orientation = 1; orientation <= 8; orientation++) {
    test('EXIF Orientation $orientation の回転・反転を補正する', () {
      final source = img.Image(width: 60, height: 40);
      final colors = [
        img.ColorRgb8(230, 20, 20),
        img.ColorRgb8(20, 230, 20),
        img.ColorRgb8(20, 20, 230),
        img.ColorRgb8(230, 230, 20),
      ];
      for (final pixel in source) {
        pixel.set(colors[(pixel.y >= 20 ? 2 : 0) + (pixel.x >= 30 ? 1 : 0)]);
      }
      source.exif.imageIfd.orientation = orientation;
      final encoded = img.encodeJpg(
        source,
        quality: 100,
        chroma: img.JpegChroma.yuv444,
      );
      final oriented = decodeOriented(encoded);
      expect([
        oriented.width,
        oriented.height,
      ], orientation >= 5 ? [40, 60] : [60, 40]);
      final expected = colors[[0, 1, 3, 2, 0, 2, 3, 1][orientation - 1]];
      final actual = oriented.getPixel(5, 5);
      expect(actual.r, closeTo(expected.r, 5));
      expect(actual.g, closeTo(expected.g, 5));
      expect(actual.b, closeTo(expected.b, 5));
      final result = img.decodeJpg(renderJpeg(encoded))!;
      final geometry = FrameGeometry.forPhoto(oriented.width, oriented.height);
      expect([result.width, result.height], [geometry.width, geometry.height]);
      expect(result.exif.imageIfd.hasOrientation, isFalse);
    });
  }

  test('透過PNGを白地に合成し、入力データを変更しない', () {
    final source = img.Image(width: 20, height: 20, numChannels: 4);
    final input = img.encodePng(source);
    final before = Uint8List.fromList(input);
    final result = img.decodeJpg(renderJpeg(input))!;
    final center = result.getPixel(10, 10);
    expect(center.r, greaterThan(250));
    expect(center.g, greaterThan(250));
    expect(center.b, greaterThan(250));
    expect(input, orderedEquals(before));
  });

  test('読めない画像はエラーにする', () {
    expect(
      () => preparePhoto(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
}
