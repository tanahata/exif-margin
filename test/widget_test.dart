import 'dart:io';

import 'package:photo_frame/src/gear_dictionary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_frame/main.dart';

void main() {
  testWidgets('起動時は写真選択ができ、保存は無効', (tester) async {
    await tester.pumpWidget(const PhotoFrameApp());
    expect(find.text('ここに写真をドロップ'), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.byKey(const ValueKey('save_hq')),
    );
    expect(save.onPressed, isNull);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('save_sns')))
          .onPressed,
      isNull,
    );
    expect(find.text('撮影情報を表示'), findsOneWidget);
    final metadataSwitch = find.widgetWithText(SwitchListTile, '撮影情報を表示');
    expect(tester.widget<SwitchListTile>(metadataSwitch).value, isTrue);
    await tester.tap(metadataSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(metadataSwitch).value, isFalse);
  });
  testWidgets('写真を開く前にも外部設定を再読み込みできる', (tester) async {
    final folder = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('frame_reload-'),
    ))!;
    try {
      final config = (await tester.runAsync(
        () => GearConfiguration.load(folder),
      ))!;
      await tester.pumpWidget(PhotoFrameApp(configuration: config));
      await tester.runAsync(() async {
        await File('${folder.path}/lenses.csv').writeAsString('broken');
      });
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('設定を再読み込み'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('設定を再読み込みしました。警告を確認してください。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    } finally {
      await tester.runAsync(() => folder.delete(recursive: true));
    }
  });
}
