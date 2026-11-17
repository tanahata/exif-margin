import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_frame/src/android/android_caption_editor.dart';
import 'package:photo_frame/src/metadata_fields.dart';

void main() {
  testWidgets('8項目の編集・復元・機材名記憶を親画面へ通知する', (tester) async {
    final fields = <String, TextEditingController>{
      for (final key in editableMetadataFieldLabels.keys)
        key: TextEditingController(),
    };
    addTearDown(() {
      for (final controller in fields.values) {
        controller.dispose();
      }
    });

    var edits = 0;
    var resets = 0;
    var remembers = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AndroidCaptionEditor(
              fields: fields,
              busy: false,
              hasPhoto: true,
              useDisplayNames: true,
              onEditChanged: () => edits++,
              onReset: () => resets++,
              onRemember: () => remembers++,
            ),
          ),
        ),
      ),
    );

    expect(editableMetadataFieldLabels, hasLength(8));
    for (final key in editableMetadataFieldLabels.keys) {
      expect(find.byKey(ValueKey('android_edit_$key')), findsOneWidget);
    }

    await tester.enterText(
      find.byKey(const ValueKey('android_edit_cameraModel')),
      'Example Model',
    );
    expect(fields['cameraModel']!.text, 'Example Model');
    expect(edits, 1);

    final reset = find.text('読み取り内容に戻す');
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    expect(resets, 1);

    final remember = find.text('機材名を記憶する');
    await tester.ensureVisible(remember);
    await tester.tap(remember);
    expect(remembers, 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('写真がない間は入力と操作を無効にする', (tester) async {
    final fields = <String, TextEditingController>{
      for (final key in editableMetadataFieldLabels.keys)
        key: TextEditingController(),
    };
    addTearDown(() {
      for (final controller in fields.values) {
        controller.dispose();
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AndroidCaptionEditor(
              fields: fields,
              busy: false,
              hasPhoto: false,
              useDisplayNames: true,
              onEditChanged: () {},
              onReset: () {},
              onRemember: () {},
            ),
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('android_edit_cameraMaker')),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('EXIF名表示中は入力可能だが機材名の記憶はできない', (tester) async {
    final fields = <String, TextEditingController>{
      for (final key in editableMetadataFieldLabels.keys)
        key: TextEditingController(),
    };
    addTearDown(() {
      for (final controller in fields.values) {
        controller.dispose();
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AndroidCaptionEditor(
              fields: fields,
              busy: false,
              hasPhoto: true,
              useDisplayNames: false,
              onEditChanged: () {},
              onReset: () {},
              onRemember: () => fail('EXIF名表示中は無効'),
            ),
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('android_edit_cameraModel')),
          )
          .enabled,
      isTrue,
    );
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNotNull,
    );
  });
}
