import 'package:flutter_test/flutter_test.dart';
import 'package:photo_frame/src/android/edit_session.dart';
import 'package:photo_frame/src/frame.dart';
import 'package:photo_frame/src/gear_dictionary.dart';
import 'package:photo_frame/src/photo_metadata.dart';

void main() {
  test('手入力換算値は表記・設定再解決で保持し原本・次の写真へ持ち越さない', () {
    const dictionary = GearDictionary();
    final session = EditSession()
      ..load(
        const PhotoMetadata(cameraModel: 'A', focalLength: 40),
        dictionary,
      );
    for (final value in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        () => session.setEquivalent(value, dictionary),
        throwsFormatException,
      );
    }
    session.setEquivalent(65.5, dictionary);
    expect(session.metadata!.focalText, '65.5mm eq.');
    expect(session.original!.focalLength35, isNull);
    session.focalPreference = FocalLengthMode.actual;
    session.resolve(dictionary);
    expect(session.metadata!.focalText, '40mm');
    session.useDisplayNames = false;
    session.resolve(dictionary, preserveEdits: false);
    session.focalPreference = FocalLengthMode.equivalent;
    session.resolve(dictionary);
    expect(session.metadata!.focalText, '65.5mm eq.');
    session.load(
      const PhotoMetadata(focalLength: 30, focalLength35: 45),
      dictionary,
    );
    expect(session.manualEquivalent, isNull);
    expect(session.metadata!.focalLength35, 45);
  });

  test('写真変更で共通設定を保持し、8項目の修正は全て破棄する', () {
    final session = EditSession()
      ..mode = OutputMode.sns
      ..showLogos = false
      ..showMetadata = false
      ..useDisplayNames = false
      ..focalPreference = FocalLengthMode.equivalent;
    session.load(
      const PhotoMetadata(
        cameraMaker: 'Sony',
        cameraModel: 'A',
        focalLength: 35,
        focalLength35: 50,
      ),
      const GearDictionary(),
    );
    session.edit({
      for (final key in EditSession.fields(session.metadata!).keys) key: '変更',
    });
    expect(session.metadata!.overrides.length, 8);
    session.load(
      const PhotoMetadata(
        cameraMaker: 'SHARP',
        cameraModel: 'B',
        focalLength: 7,
        focalLength35: 28,
      ),
      const GearDictionary(),
    );
    expect(session.metadata!.overrides, isEmpty);
    expect(session.metadata!.focalText, '7mm'); // 未登録区分は写真ごとに実値を選び直す
    expect(session.mode, OutputMode.sns);
    expect(session.showLogos, isFalse);
    expect(session.showMetadata, isFalse);
    expect(session.useDisplayNames, isFalse);
  });
  test('選択した値が次の写真にない場合は取得できる焦点距離へフォールバックする', () {
    final session = EditSession()..focalPreference = FocalLengthMode.actual;
    session.load(
      const PhotoMetadata(focalLength35: 28),
      const GearDictionary(),
    );
    expect(session.metadata!.focalText, '28mm eq.');
    expect(session.focalPreference, FocalLengthMode.automatic);
    session.load(const PhotoMetadata(focalLength: 20), const GearDictionary());
    expect(session.metadata!.focalText, '20mm');
  });
  test('空欄の非表示・復元・新しいセッションの初期値', () {
    final session = EditSession();
    session.load(
      const PhotoMetadata(cameraMaker: 'Sony', cameraModel: 'A', iso: 100),
      const GearDictionary(),
    );
    session.edit({
      ...EditSession.fields(session.metadata!),
      'cameraMaker': '',
      'iso': '',
    });
    expect(session.metadata!.cameraMakerText, '');
    expect(session.metadata!.isoText, '');
    session.resetEdits();
    expect(session.metadata!.isoText, 'ISO 100');
    final restarted = EditSession();
    expect(restarted.mode, OutputMode.hq);
    expect(restarted.showLogos, isTrue);
    expect(restarted.focalPreference, FocalLengthMode.automatic);
    expect(restarted.original, isNull);
  });
}
