import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_frame/src/manual_focal_dialog.dart';
import 'package:photo_frame/src/photo_metadata.dart';

void main() {
  test('換算値のない写真に65mmを補い、実焦点距離と切り替えられる', () {
    const original = PhotoMetadata(focalLength: 16.3);
    final supplemented = original.copyWith(focalLength35: 65);
    expect(
      supplemented.withFocalLengthMode(FocalLengthMode.equivalent).focalText,
      '65mm eq.',
    );
    expect(
      supplemented.withFocalLengthMode(FocalLengthMode.actual).focalText,
      '16.3mm',
    );
    expect(original.focalLength35, isNull);
  });

  testWidgets('不正値を拒否し65mmを適用できる', (tester) async {
    double? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<double>(
                context: context,
                builder: (_) => const ManualFocalDialog(),
              );
            },
            child: const Text('開く'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    for (final invalid in ['', '0', '-1', 'NaN', 'Infinity', 'abc']) {
      await tester.enterText(
        find.byKey(const Key('manual_equivalent')),
        invalid,
      );
      await tester.tap(find.text('適用'));
      await tester.pumpAndSettle();
      expect(find.text('0より大きい数値を入力してください。'), findsOneWidget);
    }
    await tester.enterText(find.byKey(const Key('manual_equivalent')), '65');
    await tester.tap(find.text('適用'));
    await tester.pumpAndSettle();
    expect(result, 65);
  });
}
