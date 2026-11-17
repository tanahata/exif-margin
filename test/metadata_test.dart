import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_frame/src/caption.dart';
import 'package:photo_frame/src/frame.dart';
import 'package:photo_frame/src/photo_metadata.dart';

img.Image samplePhoto() {
  final photo = img.Image(width: 600, height: 400);
  img.fill(photo, color: img.ColorRgb8(80, 130, 170));
  photo.exif.imageIfd['Make'] = 'Canon';
  photo.exif.imageIfd['Model'] = 'Canon EOS R6';
  photo.exif.exifIfd['LensModel'] = 'RF50mm F1.8 STM';
  photo.exif.exifIfd[0x920a] = img.IfdValueRational(50, 1);
  photo.exif.exifIfd[0x829d] = img.IfdValueRational(28, 10);
  photo.exif.exifIfd[0x829a] = img.IfdValueRational(1, 125);
  photo.exif.exifIfd[0x8827] = img.IfdValueShort(400);
  return photo;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('JPEGから撮影情報を読み取り、メーカー名を重複させない', () {
    final prepared = preparePhoto(img.encodeJpg(samplePhoto()));
    expect(prepared.metadata.camera, 'Canon EOS R6');
    expect(prepared.metadata.lens, 'RF50mm F1.8 STM');
    expect(prepared.metadata.settings, '50mm  F2.8  1/125  ISO 400');
  });

  test('情報のない画像では文字を生成しない', () async {
    final prepared = preparePhoto(
      img.encodePng(img.Image(width: 200, height: 300)),
    );
    expect(prepared.metadata.isEmpty, isTrue);
    expect(await renderCaption(prepared.metadata, prepared.geometry), isNull);
  });

  test('欠けた値・無効な分母・制御文字を表示しない', () {
    final exif = img.ExifData();
    exif.imageIfd['Model'] = '  Camera\x00\n Model  ';
    exif.exifIfd[0x829a] = img.IfdValueRational(1, 0);
    exif.exifIfd[0x829d] = img.IfdValueRational(0, 1);
    exif.exifIfd[0x8827] = img.IfdValueShort(0);
    final metadata = PhotoMetadata.fromExif(exif);
    expect(metadata.lines, ['Camera Model']);
  });

  test('長秒露光と小数の焦点距離を表示する', () {
    final exif = img.ExifData();
    exif.imageIfd['Make'] = 'Maker';
    exif.imageIfd['Model'] = 'Camera';
    exif.exifIfd[0x829a] = img.IfdValueRational(16, 10);
    exif.exifIfd[0x920a] = img.IfdValueRational(435, 10);
    exif.exifIfd[0x8827] = img.IfdValueShort(65535);
    exif.exifIfd[0x8833] = img.IfdValueLong(102400);
    final metadata = PhotoMetadata.fromExif(exif);
    expect(metadata.camera, 'Maker Camera');
    expect(metadata.settings, '43.5mm  1.6sec  ISO 102400');
  });

  testWidgets('撮影情報は下余白だけに入り、オフで白フレームに戻る', (tester) async {
    await tester.runAsync(() async {
      final original = img.encodeJpg(samplePhoto(), quality: 98);
      final before = Uint8List.fromList(original);
      final prepared = preparePhoto(original);
      final layer = await renderCaption(prepared.metadata, prepared.geometry);
      expect(layer, isNotNull);
      final caption = img.decodePng(layer!)!;
      expect(caption.width, prepared.geometry.width);
      expect(caption.height, prepared.geometry.bottom);
      final annotated = img.decodeJpg(
        renderExport(ExportRequest(original, caption: layer)),
      )!;
      final plain = img.decodeJpg(renderExport(ExportRequest(original)))!;
      final g = prepared.geometry;
      expect([annotated.width, annotated.height], [g.width, g.height]);
      var ink = 0;
      for (var y = g.top + g.photoHeight + 8; y < g.height - 8; y++) {
        for (var x = 0; x < g.width; x++) {
          if (annotated.getPixel(x, y).r < 200) ink++;
          expect(plain.getPixel(x, y).r, greaterThan(250));
        }
      }
      expect(ink, greaterThan(100));
      final photoPixel = annotated.getPixel(g.side + 50, g.top + 50);
      expect(photoPixel.r, closeTo(80, 5));
      expect(photoPixel.g, closeTo(130, 5));
      expect(original, orderedEquals(before));
      expect(annotated.exif.imageIfd.isEmpty, isTrue);
    });
  });

  testWidgets('長い文字でも描画が下余白の範囲内に収まる', (tester) async {
    await tester.runAsync(() async {
      const metadata = PhotoMetadata(
        cameraModel: 'Camera model with a very long name that needs truncation',
        lensModel:
            'A very long lens name with more details than will fit in one line',
        focalLength: 50,
        fNumber: 2.8,
        exposureTime: 0.008,
        iso: 400,
      );
      final g = FrameGeometry.forPhoto(100, 300);
      final layer = img.decodePng((await renderCaption(metadata, g))!)!;
      expect(layer.getPixel(0, 0).a, 0);
      expect(layer.getPixel(layer.width - 1, layer.height - 1).a, 0);
      expect(layer.any((pixel) => pixel.a > 0), isTrue);
    });
  });
}
