import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_frame/src/caption.dart';
import 'package:photo_frame/src/frame.dart';
import 'package:photo_frame/src/gear_dictionary.dart';
import 'package:photo_frame/src/photo_metadata.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('ShareTech')
      ..addFont(rootBundle.load('assets/fonts/ShareTech-Regular.ttf'));
    await loader.load();
  });

  test('撮影設定の表記を確定仕様に揃える', () {
    expect(
      const PhotoMetadata(
        focalLength: 40,
        fNumber: 2.8,
        exposureTime: 1 / 160,
        iso: 400,
      ).settings,
      '40mm  F2.8  1/160  ISO 400',
    );
    expect(PhotoMetadata.shutter(0.029993), '1/33');
    expect(PhotoMetadata.shutter(0.03), '1/33');
    expect(PhotoMetadata.shutter(0.0080001), '1/125');
    expect(
      const PhotoMetadata(
        focalLength: 85,
        fNumber: 1.4,
        exposureTime: .001,
        iso: 1000,
      ).settings,
      '85mm  F1.4  1/1000  ISO 1000',
    );
    expect(const PhotoMetadata(exposureTime: 2).settings, '2.0sec');
    expect(const PhotoMetadata(exposureTime: 1).settings, '1.0sec');
    expect(const PhotoMetadata(fNumber: 4).settings, 'F4');
  });

  test('CSVの機材区分で換算焦点距離を選び、F値は換算しない', () {
    const raw = PhotoMetadata(
      cameraMaker: 'example',
      cameraModel: ' sample ',
      focalLength: 8.9,
      focalLength35: 24,
      fNumber: 2.8,
    );
    final dictionary = GearDictionary(
      cameras: GearDictionary.parse(
        '${GearConfiguration.cameraSample}Example,Sample,Example Camera,Example,smartphone,,,1,1\n',
        camera: true,
      ),
    );
    expect(dictionary.resolve(raw).settings, '24mm eq.  F2.8');
    expect(
      raw.withEquipment(deviceType: DeviceType.interchangeable).settings,
      '8.9mm  F2.8',
    );
    expect(
      raw.withEquipment(deviceType: DeviceType.compact).settings,
      '24mm eq.  F2.8',
    );
    expect(
      const PhotoMetadata(
        deviceType: DeviceType.smartphone,
        focalLength: 8.9,
      ).settings,
      '8.9mm',
    );
    expect(const PhotoMetadata(deviceType: DeviceType.smartphone).settings, '');
  });

  for (final dimensions in [(600, 400), (400, 600), (400, 400)]) {
    test('左右の文字配置・下端位置・文字サイズ ${dimensions.$1}×${dimensions.$2}', () {
      const metadata = PhotoMetadata(
        cameraMaker: 'SONY',
        cameraModel: 'SONY α7C II',
        lensMaker: 'TAMRON',
        lensModel: 'TAMRON 20-40mm F2.8',
        focalLength: 40,
        fNumber: 2.8,
        exposureTime: 1 / 160,
        iso: 400,
      );
      final g = FrameGeometry.forPhoto(dimensions.$1, dimensions.$2);
      final s = 400.0;
      final lines = layoutCaption(metadata, g);
      expect(lines.map((line) => line.role), [
        'camera',
        'lensModel',
        'settings',
      ]);
      expect(
        lines.firstWhere((line) => line.role == 'lensModel').text,
        'TAMRON 20-40mm F2.8',
      );
      for (final line in lines) {
        expect(line.bounds.top, greaterThanOrEqualTo(0));
        expect(
          line.bounds.bottom,
          lessThanOrEqualTo(g.bottom - s * 0.04 + 0.001),
        );
        if (line.role.startsWith('camera')) {
          expect(line.bounds.left, g.side);
          expect(line.fontSize, closeTo(s * 0.024, 0.001));
        } else {
          expect(line.bounds.right, closeTo(g.side + g.photoWidth, 0.001));
          expect(
            line.fontSize,
            closeTo(s * (line.role == 'settings' ? 0.018 : 0.019), 0.001),
          );
        }
      }
      final left = lines.where((line) => line.role.startsWith('camera'));
      final right = lines.where((line) => !line.role.startsWith('camera'));
      for (final a in left) {
        for (final b in right) {
          expect(a.bounds.overlaps(b.bounds), isFalse);
        }
      }
      expect(lines[0].bounds.bottom, closeTo(g.bottom - s * 0.04, 0.001));
      expect(lines.last.bounds.bottom, closeTo(g.bottom - s * 0.04, 0.001));
      expect(lines[0].text, 'SONY α7C II');
    });
  }

  test('長い名称は短縮名を使い、収まらないレンズ名より撮影情報を優先', () {
    final g = FrameGeometry.forPhoto(400, 600);
    final metadata = PhotoMetadata(
      cameraModel: 'A' * 200,
      cameraShort: 'α7C II',
      lensMaker: 'TAMRON',
      lensModel: 'B' * 240,
      focalLength: 40,
      iso: 400,
    );
    final lines = layoutCaption(metadata, g);
    expect(lines.first.text, 'α7C II');
    expect(lines.any((line) => line.role == 'lensModel'), isFalse);
    expect(lines.last.text, '40mm  ISO 400');
  });

  test('CSVはBOM・引用符・大小文字と連続空白を扱う', () {
    final csv =
        '\uFEFFexif_make,exif_model,display_name,short_name,device_type,maker_logo,model_logo\r\n'
        'SONY,ILCE-7CM2,"SONY α7C II, special",α7C II,interchangeable,,\r\n';
    final dictionary = GearDictionary(
      cameras: GearDictionary.parse(csv, camera: true),
    );
    final resolved = dictionary.resolve(
      const PhotoMetadata(cameraMaker: '  sony ', cameraModel: 'ilce-7cm2'),
    );
    expect(resolved.cameraModel, 'SONY α7C II, special');
    expect(normalizedGearName(' A   B '), 'a b');
    expect(
      dictionary
          .resolve(
            const PhotoMetadata(cameraMaker: 'SONY', cameraModel: 'ILCE-7CM'),
          )
          .cameraModel,
      'ILCE-7CM',
    );
  });

  test('メーカー不明のレンズは一意の完全一致だけを使う', () {
    final entries = GearDictionary.parse(
      '${GearConfiguration.lensSample}ExampleMaker,Zoom Model,Example Zoom,Zoom\n',
      camera: false,
    );
    const raw = PhotoMetadata(lensModel: 'Zoom Model');
    expect(
      GearDictionary(lenses: entries).resolve(raw).lensMaker,
      'ExampleMaker',
    );
    final ambiguous = [
      ...entries,
      GearEntry('OTHER', entries.first.model, 'Other lens', '', null),
    ];
    expect(GearDictionary(lenses: ambiguous).resolve(raw).lensMaker, '');
    expect(
      GearDictionary(lenses: entries)
          .resolve(const PhotoMetadata(lensModel: '20-40mm'))
          .lensMaker,
      '',
    );
  });

  test('不正なCSVと重複キーを拒否する', () {
    expect(
      () => GearDictionary.parse('make,model\nx,y', camera: true),
      throwsFormatException,
    );
    final duplicate =
        '${GearConfiguration.cameraSample}Example,Model,First,,compact,,,1,1\n'
        'example, model ,Second,,compact,,,1,1\n';
    expect(
      () => GearDictionary.parse(duplicate, camera: true),
      throwsFormatException,
    );
    final invalid =
        '${GearConfiguration.cameraSample}Example,Model,Example,,invalid,,,1,1\n';
    expect(
      () => GearDictionary.parse(invalid, camera: true),
      throwsFormatException,
    );
  });

  test('初回CSV生成と再起動時の読み込みでユーザー設定を上書きしない', () async {
    final folder = await Directory.systemTemp.createTemp('exif_margin_config-');
    try {
      final first = await GearConfiguration.load(folder);
      expect(first.warning, isNull);
      expect(first.dictionary.cameras, isEmpty);
      expect(first.dictionary.lenses, isEmpty);
      final file = File('${folder.path}/cameras.csv');
      final custom =
          '${GearConfiguration.cameraSample}Example,Model,Custom Camera,Custom,compact,,,1,1\n';
      await file.writeAsString(custom);
      final second = await GearConfiguration.load(folder);
      expect(second.dictionary.cameras.single.display, 'Custom Camera');
      expect(await file.readAsString(), custom);
      await file.writeAsString('invalid csv');
      final third = await GearConfiguration.load(folder);
      expect(third.warning, contains('cameras.csv'));
      expect(await file.readAsString(), 'invalid csv');
      expect(third.dictionary.lenses, isEmpty);
    } finally {
      await folder.delete(recursive: true);
    }
  });
}
