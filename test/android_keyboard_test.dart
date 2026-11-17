import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_frame/src/android/android_frame_page.dart';
import 'package:photo_frame/src/android/android_platform.dart';
import 'package:photo_frame/src/photo_metadata.dart';
import 'package:photo_frame/src/manual_focal_dialog.dart';
import 'package:photo_frame/src/frame.dart';

class KeyboardTestPlatform extends AndroidPlatform {
  KeyboardTestPlatform(this.root);
  final Directory root;
  @override
  Future<Map<String, String>> paths() async => {
    'files': '${root.path}/files',
    'cache': '${root.path}/cache',
  };
  @override
  Future<Map?> nextIncoming() async => null;
  @override
  Future<ImportedFile?> pickPhoto() async {
    final file = File('${root.path}/input.png');
    await file.writeAsBytes(img.encodePng(img.Image(width: 80, height: 60)));
    return ImportedFile(file.path, 'input.png');
  }

  @override
  Future<AndroidNormalizedPhoto> normalize(String path) async {
    final copy = await File(path).copy('${root.path}/normalized.png');
    return AndroidNormalizedPhoto(
      copy,
      const PhotoMetadata(
        cameraMaker: 'SONY',
        cameraModel: 'ILCE-7CM2',
        focalLength: 15.4,
      ),
      File('android/app/src/main/assets/srgb.icc').readAsBytesSync(),
    );
  }
}

void main() {
  testWidgets('設定行は横幅を使い、拡大表示では項目名を上に置く', (tester) async {
    final root = Directory.systemTemp.createTempSync('photo-frame-layout-');
    addTearDown(() => root.delete(recursive: true));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final platform = KeyboardTestPlatform(root);

    Future<void> render(double width, double scale) async {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: AndroidFramePage(platform: platform),
        ),
      );
      await tester.pump();
    }

    final gear = find.byType(SegmentedButton<bool>);
    final gearLabel = find.text('機材名');
    final size = find.byType(DropdownButton<OutputMode>);
    final share = find.widgetWithText(OutlinedButton, '共有');
    final save = find.widgetWithText(FilledButton, 'JPEG保存');
    await render(360, 1);
    expect(
      tester.getRect(gearLabel).right,
      lessThan(tester.getRect(gear).left),
    );
    expect(tester.getRect(size).center.dy, tester.getRect(share).center.dy);
    expect(tester.getRect(share).center.dy, tester.getRect(save).center.dy);
    expect(tester.getRect(save).right, 344);
    expect(tester.getRect(gear).bottom, lessThan(tester.getRect(size).top));
    expect(find.text('機材・焦点距離'), findsNothing);
    expect(find.text('35mm換算値を入力'), findsNothing);
    final margins = find.widgetWithText(ListTile, '余白');
    final textSizes = find.widgetWithText(ListTile, '文字サイズ');
    expect(tester.getRect(margins).width, tester.getRect(textSizes).width);
    expect(
      tester.getRect(margins).bottom,
      lessThanOrEqualTo(tester.getRect(textSizes).top),
    );
    expect(tester.getRect(textSizes).right, 344);
    final heading = tester.getRect(find.text('表示文字を修正'));
    final note = tester.getRect(find.text('空欄は表示しません。'));
    expect(note.left, greaterThan(heading.right));
    expect(note.center.dy, closeTo(heading.center.dy, 1));
    expect(find.text('左右2%・上7%・下20%'), findsOneWidget);
    expect(find.text('左100%・右100%'), findsOneWidget);
    expect(tester.getRect(gear).right, greaterThan(325));
    expect(tester.getRect(gear).height, greaterThanOrEqualTo(48));
    expect(find.text('写真を選択すると、完成画像を表示します。'), findsNothing);

    await render(320, 2);
    expect(
      tester.getRect(gearLabel).bottom,
      lessThan(tester.getRect(gear).top),
    );
    expect(tester.getRect(size).bottom, lessThan(tester.getRect(share).top));
    final sizeOutline = find
        .ancestor(of: size, matching: find.byType(DecoratedBox))
        .first;
    expect(tester.getRect(sizeOutline).right, 304);
    expect(tester.getRect(gear).right, 304);
    expect(tester.takeException(), isNull);

    // Let the page's asynchronous initialization finish before teardown.
    for (var i = 0; i < 100; i++) {
      if (tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '写真を選択'))
              .onPressed !=
          null) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  });

  testWidgets('入力を重ねてもフォーカスとキーボードが維持され、空欄と復元が動作する', (tester) async {
    final root = Directory.systemTemp.createTempSync('photo-frame-keyboard-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final platform = KeyboardTestPlatform(root);
    await tester.pumpWidget(
      MaterialApp(home: AndroidFramePage(platform: platform)),
    );
    Future<void> waitFor(bool Function() condition) async {
      for (var i = 0; i < 150 && !condition(); i++) {
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(condition(), isTrue, reason: 'UIの非同期処理が完了しませんでした');
    }

    await waitFor(
      () =>
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '写真を選択'))
              .onPressed !=
          null,
    );
    await tester.tap(find.text('写真を選択'));
    await tester.pump();
    await waitFor(
      () =>
          tester
              .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '共有'))
              .onPressed !=
          null,
    );
    final focal = find.byType(SegmentedButton<FocalLengthMode>);
    final dialog = find.byType(ManualFocalDialog);
    await tester.scrollUntilVisible(
      focal,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(focal);
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    await tester.tap(find.text('35mm換算').last);
    await tester.pump();
    await waitFor(() => dialog.evaluate().isNotEmpty);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(find.byKey(const Key('manual_equivalent')), '65');
    await tester.tap(find.text('適用'));
    await tester.pump();
    await waitFor(
      () =>
          tester
              .widget<SegmentedButton<FocalLengthMode>>(focal)
              .onSelectionChanged !=
          null,
    );
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(tester.widget<SegmentedButton<FocalLengthMode>>(focal).selected, {
      FocalLengthMode.equivalent,
    });
    await tester.tap(find.text('35mm換算').last);
    await tester.pump();
    await waitFor(
      () =>
          tester
              .widget<SegmentedButton<FocalLengthMode>>(focal)
              .onSelectionChanged !=
          null,
    );
    expect(dialog, findsNothing);

    final field = find.byKey(const ValueKey('android_edit_cameraModel'));
    await tester.scrollUntilVisible(
      field,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    final controller = tester.widget<TextField>(field).controller!;
    await tester.showKeyboard(field);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    expect(find.text('共有'), findsNothing);
    expect(find.byType(DropdownButton<OutputMode>), findsNothing);
    expect(tester.getRect(field).bottom, lessThanOrEqualTo(360));
    final focus = tester
        .widget<EditableText>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        )
        .focusNode;
    expect(focus.hasFocus, isTrue);
    for (final text in ['A', 'AB', 'ABC', 'あ', 'あい']) {
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
          composing: text.startsWith('あ')
              ? TextRange(start: 0, end: text.length)
              : TextRange.empty,
        ),
      );
      await tester.pump();
      if (text.startsWith('あ')) {
        expect(
          controller.value.composing,
          TextRange(start: 0, end: text.length),
        );
      }
      expect(focus.hasFocus, isTrue, reason: '文字「$text」の入力後にフォーカスを失いました');
      expect(
        tester.testTextInput.isVisible,
        isTrue,
        reason: '文字「$text」の入力後にキーボードが閉じました',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
      expect(focus.hasFocus, isTrue);
    }
    await tester.enterText(field, '');
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '');
    tester.view.resetViewInsets();
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('読み取り内容に戻す'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.text('読み取り内容に戻す')),
      alignment: 0.3,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('読み取り内容に戻す'));
    await tester.pump();
    await waitFor(() => controller.text == 'ILCE-7CM2');
    expect(tester.takeException(), isNull);
  });
}
