import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_frame/src/frame.dart';
import 'package:photo_frame/src/margin_dialog.dart';
import 'package:photo_frame/src/editor_preferences.dart';
import 'package:photo_frame/src/macos/mac_settings_panel.dart';
import 'package:photo_frame/src/photo_metadata.dart';

void main() {
  testWidgets('余白を数値入力し範囲外は適用しない・初期値へ戻せる', (tester) async {
    FrameMargins? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await showDialog<FrameMargins>(
                  context: context,
                  builder: (_) =>
                      const MarginDialog(margins: editorDefaultMargins),
                );
              },
              child: const Text('開く'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('margin_side')), '21');
    await tester.tap(find.text('適用'));
    await tester.pumpAndSettle();
    expect(find.text('0〜20で入力'), findsOneWidget);
    expect(selected, isNull);
    await tester.tap(find.text('初期値に戻す'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('適用'));
    await tester.pumpAndSettle();
    expect([selected!.side, selected!.top, selected!.bottom], [.02, .07, .2]);
  });
  testWidgets('Macで換算値が欠けても35mm換算を選択できる', (tester) async {
    FocalLengthMode? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MacSettingsPanel(
            metadata: const PhotoMetadata(focalLength: 12),
            fields: const {},
            margins: editorDefaultMargins,
            sizes: const CaptionSizes(),
            busy: false,
            captionPending: false,
            showMetadata: true,
            showLogos: true,
            useDisplayNames: true,
            canRememberNames: true,
            onMetadataChanged: (_) {},
            onLogoChanged: (_) {},
            onNameSourceChanged: (_) {},
            onFocalChanged: (value) => chosen = value,
            onEditChanged: () {},
            onAdjustMargins: () {},
            onAdjustSizes: () {},
            onReset: () {},
            onRemember: () {},
          ),
        ),
      ),
    );
    final finder = find.byKey(const ValueKey('focal_mode'));
    final segments = tester.widget<SegmentedButton<FocalLengthMode>>(finder);
    expect(segments.selected, {FocalLengthMode.actual});
    expect(segments.segments.map((item) => item.value), [
      FocalLengthMode.actual,
      FocalLengthMode.equivalent,
    ]);
    expect(find.text('35mm換算値を入力'), findsNothing);
    await tester.tap(find.text('35mm換算').last);
    await tester.pumpAndSettle();
    expect(chosen, FocalLengthMode.equivalent);
  });
}
