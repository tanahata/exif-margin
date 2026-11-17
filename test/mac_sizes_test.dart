import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_frame/src/caption.dart';
import 'package:photo_frame/src/display_settings.dart';
import 'package:photo_frame/src/frame.dart';
import 'package:photo_frame/src/logo_store.dart';
import 'package:photo_frame/src/size_dialog.dart';
import 'package:photo_frame/src/margin_dialog.dart';
import 'package:photo_frame/src/editor_preferences.dart';
import 'package:photo_frame/src/photo_metadata.dart';

void main() {
  test('横・縦・正方形で写真の底辺を基準に2.4%を使う', () {
    const m = PhotoMetadata(
      cameraMaker: 'A',
      cameraModel: 'B',
      lensModel: 'L',
      iso: 100,
    );
    final settings = const CaptionSizes().applyTo(const DisplaySettings());
    for (final (width, height) in [(1500, 1000), (1000, 1500), (1000, 1000)]) {
      final rows = layoutCaption(
        m,
        FrameGeometry.forPhoto(width, height),
        settings: settings,
      );
      final size = width * .024;
      expect(rows.first.parts.first.fontSize, closeTo(size, .001));
      expect(
        rows.firstWhere((r) => r.role == 'lensModel').fontSize,
        closeTo(size, .001),
      );
      expect(
        rows.firstWhere((r) => r.role == 'settings').fontSize,
        closeTo(size, .001),
      );
    }
    final changed = const CaptionSizes(
      left: 1.25,
      right: .8,
    ).applyTo(const DisplaySettings());
    expect(changed.cameraGlyphHeightScale! / .7, closeTo(.024 * 1.25, .000001));
    expect(changed.logoHeightScale, changed.cameraGlyphHeightScale);
    expect(changed.lensTextScale, closeTo(.024 * .8, .000001));
    expect(changed.exifTextScale, changed.lensTextScale);
  });

  testWidgets('余白の数値とバーが双方向に連動する', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: MarginDialog(margins: editorDefaultMargins)),
    );
    await tester.enterText(find.byKey(const ValueKey('margin_side')), '8');
    await tester.pump();
    expect(
      tester
          .widget<Slider>(find.byKey(const ValueKey('margin_side_slider')))
          .value,
      8,
    );
    tester
        .widget<Slider>(find.byKey(const ValueKey('margin_side_slider')))
        .onChanged!(12);
    await tester.pump();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('margin_side')))
          .controller!
          .text,
      '12',
    );
  });
  testWidgets('左右のサイズを別々に指定する', (tester) async {
    CaptionSizes? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<CaptionSizes>(
                  context: context,
                  builder: (_) => const SizeDialog(sizes: CaptionSizes()),
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
    await tester.enterText(find.byKey(const ValueKey('left_size')), '125');
    tester
        .widget<Slider>(find.byKey(const ValueKey('right_size_slider')))
        .onChanged!(80);
    await tester.pump();
    await tester.tap(find.text('適用'));
    await tester.pumpAndSettle();
    expect(result!.left, 1.25);
    expect(result!.right, .8);
  });
  testWidgets('文字倍率とロゴ倍率が独立して描画される', (tester) async {
    await tester.runAsync(() async {
      final folder = await Directory.systemTemp.createTemp('sizes_');
      final store = LogoStore(folder);
      try {
        await File('${folder.path}/maker.svg').writeAsString(
          '<svg xmlns="http://www.w3.org/2000/svg" width="60" height="20"><rect width="60" height="20"/></svg>',
        );
        final logo = (await store.load('maker.svg'))!;
        const m = PhotoMetadata(
          cameraMaker: 'A',
          cameraModel: 'B',
          cameraMakerLogo: 'maker.svg',
          lensModel: 'L',
          iso: 100,
        );
        final g = FrameGeometry.forPhoto(1500, 1000);
        final initial = layoutCaption(m, g, logos: {'maker.svg': logo});
        final resized = layoutCaption(
          m,
          g,
          logos: {'maker.svg': logo},
          settings: const DisplaySettings().withSizeMultipliers(
            text: 1.25,
            logo: .8,
          ),
        );
        final a = initial.firstWhere((e) => e.role == 'camera'),
            b = resized.firstWhere((e) => e.role == 'camera');
        expect(
          b.parts.first.bounds.height,
          closeTo(a.parts.first.bounds.height * .8, .001),
        );
        expect(
          b.parts.last.fontSize,
          closeTo(a.parts.last.fontSize! * 1.25, .001),
        );
        expect(
          resized.firstWhere((e) => e.role == 'settings').fontSize,
          closeTo(
            initial.firstWhere((e) => e.role == 'settings').fontSize * 1.25,
            .001,
          ),
        );
        final textOnly = layoutCaption(
          m,
          g,
          settings: const DisplaySettings().withSizeMultipliers(
            text: 1,
            logo: 2,
          ),
        );
        final originalText = layoutCaption(m, g);
        expect(
          textOnly.first.parts.last.fontSize,
          originalText.first.parts.last.fontSize,
        );
        final macBase = layoutCaption(
          m,
          g,
          logos: {'maker.svg': logo},
          settings: const CaptionSizes().applyTo(const DisplaySettings()),
        );
        final macScaled = layoutCaption(
          m,
          g,
          logos: {'maker.svg': logo},
          settings: const CaptionSizes(
            left: 1.25,
            right: .8,
          ).applyTo(const DisplaySettings()),
        );
        final baseCamera = macBase.firstWhere((line) => line.role == 'camera');
        final scaledCamera = macScaled.firstWhere(
          (line) => line.role == 'camera',
        );
        expect(
          scaledCamera.parts.first.bounds.height,
          closeTo(baseCamera.parts.first.bounds.height * 1.25, .001),
        );
        expect(
          scaledCamera.parts.last.fontSize,
          closeTo(baseCamera.parts.last.fontSize! * 1.25, .001),
        );
        expect(
          macScaled.firstWhere((line) => line.role == 'settings').fontSize,
          closeTo(
            macBase.firstWhere((line) => line.role == 'settings').fontSize * .8,
            .001,
          ),
        );
      } finally {
        store.dispose();
        await folder.delete(recursive: true);
      }
    });
  });
}
