import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_frame/src/frame.dart';
import 'package:photo_frame/src/editor_preferences.dart';
import 'package:photo_frame/src/photo_metadata.dart';

void main() {
  test('旧サイズを新しい2.4%の100%に移行し、その後の左右設定を保持する', () async {
    final dir = await Directory.systemTemp.createTemp('sizes_migrate_');
    try {
      final file = File('${dir.path}/prefs.json');
      await file.writeAsString(
        '{"schemaVersion":3,"margins":[0.05,0.10,0.30],"names":{},"textScale":1.2,"logoScale":0.8}',
      );
      final prefs = EditorPreferences(file);
      await prefs.load();
      expect(prefs.sizes.left, 1);
      expect(prefs.sizes.right, 1);
      final again = EditorPreferences(file);
      await again.load();
      expect(again.sizes.left, 1);
      expect(again.sizes.right, 1);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('旧倍率を新100%へ戻し余白と機材名を保持する', () async {
    final dir = await Directory.systemTemp.createTemp('android_type_migrate_');
    try {
      final file = File('${dir.path}/prefs.json');
      await file.writeAsString(
        '{"schemaVersion":2,"margins":[0.05,0.10,0.30],"names":{"test":{"cameraModel":"Custom"}},"textScale":1.2,"logoScale":0.8}',
      );
      final prefs = EditorPreferences(file);
      await prefs.load();
      expect(prefs.sizes.left, 1);
      expect(prefs.sizes.right, 1);
      expect(prefs.names['test']!['cameraModel'], 'Custom');
      expect(prefs.margins.top, .1);
      prefs.sizes = const CaptionSizes(left: 1.1, right: .9);
      await prefs.save();
      final restored = EditorPreferences(file);
      await restored.load();
      expect(restored.sizes.left, 1.1);
      expect(restored.sizes.right, .9);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('Android旧余白を2・7・20へ移行しカスタム余白は保持する', () async {
    final dir = await Directory.systemTemp.createTemp('android_migrate_');
    try {
      final file = File('${dir.path}/prefs.json');
      await file.writeAsString(
        '{"schemaVersion":1,"margins":[0.06,0.06,0.30],"names":{}}',
      );
      final prefs = EditorPreferences(file);
      await prefs.load();
      expect(
        [prefs.margins.side, prefs.margins.top, prefs.margins.bottom],
        [.02, .07, .2],
      );
      prefs.margins = const FrameMargins();
      await prefs.save();
      final restored = EditorPreferences(file);
      await restored.load();
      expect(restored.margins.side, .02);
      expect(restored.margins.top, .07);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('横・縦・正方形で指定余白を短辺から計算し既定値は維持する', () {
    for (final size in [(1500, 1000), (1000, 1500), (1000, 1000)]) {
      final g = FrameGeometry.forPhoto(
        size.$1,
        size.$2,
        margins: const FrameMargins(side: .1, top: .02, bottom: .2),
      );
      expect([g.side, g.top, g.bottom], [100, 20, 200]);
      expect(FrameGeometry.forPhoto(size.$1, size.$2).bottom, 200);
    }
    expect(
      () => FrameGeometry.forPhoto(
        100,
        100,
        margins: const FrameMargins(bottom: 0),
      ),
      throwsFormatException,
    );
  });
  test('変更余白をJPEGとSNS出力にも反映する', () {
    final source = img.Image(width: 100, height: 200);
    img.fill(source, color: img.ColorRgb8(30, 80, 150));
    final bytes = img.encodePng(source);
    final output = img.decodeJpg(
      renderExport(
        ExportRequest(
          bytes,
          margins: const FrameMargins(side: .1, top: .02, bottom: .2),
        ),
      ),
    )!;
    expect([output.width, output.height], [120, 222]);
    expect(output.getPixel(60, 100).b, closeTo(150, 4));
    expect(output.getPixel(5, 100).r, greaterThan(245));
    final g = FrameGeometry.forPhoto(
      4000,
      3000,
      margins: const FrameMargins(side: .1, top: .02, bottom: .2),
    );
    final d = outputDimensions(g, OutputMode.sns);
    expect(d.width, 2048);
    expect(d.height, (g.height * 2048 / g.width).round());
  });
  test('名前だけを機材別に永続化し再起動後に復元する', () async {
    final dir = await Directory.systemTemp.createTemp('android_preferences_');
    try {
      final file = File('${dir.path}/mac-preferences.json');
      final store = EditorPreferences(file);
      const original = PhotoMetadata(
        cameraMaker: 'SHARP',
        cameraModel: 'LP-03',
        lensModel: 'LENS',
      );
      store.remember(
        original,
        original.withOverrides({
          'cameraMaker': 'Leitz',
          'cameraModel': 'Leitz Phone 3',
          'lensMaker': 'Leica',
          'focal': '999mm',
        }),
      );
      store.sizes = const CaptionSizes(left: 1.25, right: .8);
      store.margins = const FrameMargins(side: .08, top: .04, bottom: .2);
      await store.save();
      final restored = EditorPreferences(file);
      await restored.load();
      expect(restored.margins.side, .08);
      expect(restored.sizes.left, 1.25);
      expect(restored.sizes.right, .8);
      expect(restored.overrides(original), {
        'cameraMaker': 'Leitz',
        'cameraModel': 'Leitz Phone 3',
        'lensMaker': 'Leica',
      });
      expect(
        restored.overrides(
          const PhotoMetadata(cameraMaker: 'SHARP', cameraModel: 'OTHER'),
        ),
        isEmpty,
      );
      // Lens choices are shared with the same EXIF lens on a different camera.
      expect(restored.overrides(const PhotoMetadata(lensModel: 'LENS')), {
        'lensMaker': 'Leica',
      });
      restored.remember(
        original,
        original.withOverrides({
          'cameraModel': 'Leitz Phone 3 (edited)',
          'lensMaker': 'Leica',
        }),
      );
      await restored.save();
      final updated = EditorPreferences(file);
      await updated.load();
      expect(updated.overrides(original), {
        'cameraModel': 'Leitz Phone 3 (edited)',
        'lensMaker': 'Leica',
      });
      updated.remember(original, original);
      await updated.save();
      final cleared = EditorPreferences(file);
      await cleared.load();
      expect(cleared.overrides(original), isEmpty);
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test('EXIF機種名がない写真は記憶しない・不正ファイルを変更しない', () async {
    final dir = await Directory.systemTemp.createTemp('android_preferences_');
    try {
      final file = File('${dir.path}/mac-preferences.json');
      final store = EditorPreferences(file);
      store.remember(
        const PhotoMetadata(),
        const PhotoMetadata(overrides: {'cameraMaker': 'X'}),
      );
      expect(store.names, isEmpty);
      await file.writeAsString('broken');
      await expectLater(store.load(), throwsFormatException);
      expect(await file.readAsString(), 'broken');
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
