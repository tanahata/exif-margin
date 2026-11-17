import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_frame/src/android/android_settings_panel.dart';
import 'package:photo_frame/src/caption_sizes.dart';
import 'package:photo_frame/src/frame.dart';
import 'package:photo_frame/src/photo_metadata.dart';

void main() {
  for (final logoEdition in [false, true]) {
    testWidgets('Android設定の選択・余白・ロゴ表示: $logoEdition', (tester) async {
      bool? metadataSelection;
      bool? logoSelection;
      bool? nameSelection;
      FocalLengthMode? focalSelection;
      var marginTaps = 0;
      var sizeTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AndroidSettingsPanel(
                busy: false,
                hasConfiguration: true,
                hasPreferences: true,
                hasPhoto: true,
                showLogoOption: logoEdition,
                showMetadata: true,
                showLogos: false,
                useDisplayNames: true,
                focalLengthMode: FocalLengthMode.actual,
                margins: const FrameMargins(),
                sizes: const CaptionSizes(),
                onMetadataChanged: (value) => metadataSelection = value,
                onLogosChanged: (value) => logoSelection = value,
                onNameSourceChanged: (value) => nameSelection = value,
                onFocalChanged: (value) => focalSelection = value,
                onAdjustMargins: () => marginTaps++,
                onAdjustSizes: () => sizeTaps++,
              ),
            ),
          ),
        ),
      );
      expect(find.text('表示設定'), findsOneWidget);
      expect(find.text('ロゴで表示'), logoEdition ? findsOneWidget : findsNothing);
      expect(find.text('左右2%・上7%・下20%'), findsOneWidget);

      await tester.tap(find.text(logoEdition ? '撮影情報表示' : '撮影情報を表示'));
      expect(metadataSelection, isFalse);

      if (logoEdition) {
        await tester.tap(find.text('ロゴで表示'));
        expect(logoSelection, isTrue);
      }

      await tester.ensureVisible(find.text('EXIF名'));
      await tester.tap(find.text('EXIF名'));
      expect(nameSelection, isFalse);

      await tester.ensureVisible(find.text('35mm換算'));
      await tester.tap(find.text('35mm換算'));
      expect(focalSelection, FocalLengthMode.equivalent);

      await tester.ensureVisible(find.text('余白'));
      await tester.tap(find.text('余白'));
      expect(marginTaps, 1);

      final sizeLabel = logoEdition ? '文字・ロゴサイズ' : '文字サイズ';
      await tester.ensureVisible(find.text(sizeLabel));
      await tester.tap(find.text(sizeLabel));
      expect(sizeTaps, 1);
    });
  }

  testWidgets('処理中・設定未準備・写真未選択では操作できない', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AndroidSettingsPanel(
              busy: true,
              hasConfiguration: false,
              hasPreferences: false,
              hasPhoto: false,
              showLogoOption: false,
              showMetadata: true,
              showLogos: false,
              useDisplayNames: true,
              focalLengthMode: FocalLengthMode.actual,
              margins: const FrameMargins(),
              sizes: const CaptionSizes(),
              onMetadataChanged: (_) => fail('操作中は無効'),
              onLogosChanged: (_) => fail('操作中は無効'),
              onNameSourceChanged: (_) => fail('操作中は無効'),
              onFocalChanged: (_) => fail('操作中は無効'),
              onAdjustMargins: () => fail('操作中は無効'),
              onAdjustSizes: () => fail('操作中は無効'),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    expect(
      tester
          .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
          .onSelectionChanged,
      isNull,
    );
    expect(
      tester
          .widget<SegmentedButton<FocalLengthMode>>(
            find.byType(SegmentedButton<FocalLengthMode>),
          )
          .onSelectionChanged,
      isNull,
    );
    for (final title in ['余白', '文字サイズ']) {
      final tile = tester.widget<ListTile>(
        find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
      );
      expect(tile.onTap, isNull);
    }
  });
}
