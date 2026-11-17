import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_frame/src/editor_preferences.dart';
import 'package:photo_frame/src/frame.dart';
import 'package:photo_frame/src/photo_metadata.dart';

void main() {
  test('新規インストールでは元サイズを選び、前回のSNS用を復元する', () async {
    final root = await Directory.systemTemp.createTemp('export-mode-prefs-');
    try {
      final file = File('${root.path}/android-preferences.json');
      final first = EditorPreferences(file);
      await first.load();
      expect(first.outputMode, OutputMode.hq);

      first.outputMode = OutputMode.sns;
      await first.save();
      final restored = EditorPreferences(file);
      await restored.load();
      expect(restored.outputMode, OutputMode.sns);

      restored.outputMode = OutputMode.hq;
      await restored.save();
      final again = EditorPreferences(file);
      await again.load();
      expect(again.outputMode, OutputMode.hq);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('旧バージョン4の設定に保存サイズがなくても機材名は維持する', () async {
    final root = await Directory.systemTemp.createTemp('export-mode-legacy-');
    try {
      final file = File('${root.path}/android-preferences.json');
      final original = EditorPreferences(file);
      original.remember(
        const PhotoMetadata(cameraMaker: 'SHARP', cameraModel: 'A504SH'),
        const PhotoMetadata(
          cameraMaker: 'SHARP',
          cameraModel: 'A504SH',
        ).withOverrides({'cameraModel': 'R9 Pro'}),
      );
      await original.save();
      final oldJson = await file.readAsString();
      await file.writeAsString(oldJson.replaceFirst(',"outputMode":"hq"', ''));

      final current = EditorPreferences(file);
      await current.load();
      expect(current.outputMode, OutputMode.hq);
      expect(
        current.overrides(
          const PhotoMetadata(cameraMaker: 'SHARP', cameraModel: 'A504SH'),
        )['cameraModel'],
        'R9 Pro',
      );
      current.outputMode = OutputMode.sns;
      await current.save();
      final again = EditorPreferences(file);
      await again.load();
      expect(again.outputMode, OutputMode.sns);
      expect(again.names, current.names);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
