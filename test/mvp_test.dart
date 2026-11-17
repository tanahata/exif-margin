import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_frame/src/caption.dart';
import 'package:photo_frame/src/display_settings.dart';
import 'package:photo_frame/src/frame.dart';
import 'package:photo_frame/src/gear_dictionary.dart';
import 'package:photo_frame/src/logo_store.dart';
import 'package:photo_frame/src/public_edition.dart';
import 'package:photo_frame/src/photo_metadata.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('登録名とEXIF名を切り替えても機材区分と換算焦点距離を保持する', () {
    const original = PhotoMetadata(
      cameraMaker: 'Maker',
      cameraModel: 'Code',
      lensMaker: 'LensMaker',
      lensModel: 'LensCode',
      focalLength: 8,
      focalLength35: 24,
    );
    const dictionary = GearDictionary(
      cameras: [
        GearEntry(
          'Maker',
          'Code',
          'Friendly',
          'Short',
          DeviceType.compact,
          'maker.svg',
          'model.svg',
        ),
      ],
      lenses: [
        GearEntry('LensMaker', 'LensCode', 'Friendly Lens', 'Lens', null),
      ],
    );
    final registered = dictionary.resolve(original);
    final raw = dictionary.resolve(original, useDisplayNames: false);
    expect(registered.camera, 'Maker Friendly');
    expect(raw.camera, 'Maker Code');
    expect(registered.lens, 'LensMaker Friendly Lens');
    expect(raw.lens, 'LensMaker LensCode');
    expect(raw.focalText, '24mm eq.');
    expect(raw.cameraMakerLogo, 'maker.svg');
    expect(raw.cameraModelLogo, isEmpty);
    expect(dictionary.resolve(raw).camera, registered.camera);
    expect(const GearDictionary().resolve(original).camera, raw.camera);
  });
  test('未登録機種も登録メーカーのロゴを使い、機種名と機材区分は推測しない', () {
    const dictionary = GearDictionary(
      cameras: [
        GearEntry(
          'OLYMPUS IMAGING CORP.',
          'E-PM2',
          'PEN mini E-PM2',
          '',
          DeviceType.interchangeable,
          'olympus.svg',
          '',
          'OLYMPUS',
          false,
          1.2,
        ),
        GearEntry(
          'OLYMPUS IMAGING CORP.',
          'E-PL1s',
          'PEN Lite E-PL1s',
          '',
          DeviceType.interchangeable,
          'olympus.svg',
          '',
          'OLYMPUS',
          false,
          1.2,
        ),
      ],
    );
    const raw = PhotoMetadata(
      cameraMaker: 'OLYMPUS IMAGING CORP.  ',
      cameraModel: 'E-M10',
      focalLength: 25,
      focalLength35: 50,
    );
    for (final display in [true, false]) {
      final m = dictionary.resolve(raw, useDisplayNames: display);
      expect(m.cameraMakerLogo, 'olympus.svg');
      expect(m.cameraMakerLogoScale, 1.2);
      expect(m.cameraModel, 'E-M10');
      expect(m.cameraModelLogo, isEmpty);
      expect(m.deviceType, isNull);
      expect(m.focalText, '25mm');
      expect(m.cameraMaker, display ? 'OLYMPUS' : raw.cameraMaker);
    }
    expect(
      dictionary
          .resolve(
            const PhotoMetadata(cameraMaker: 'UNKNOWN', cameraModel: 'E-M10'),
          )
          .cameraMakerLogo,
      isEmpty,
    );
  });
  test('メーカーのロゴ候補が複数なら選ばず、機種別の明示指定は優先する', () {
    const d = GearDictionary(
      cameras: [
        GearEntry('Maker', 'A', 'A', '', null, 'one.svg', '', '', false, 1.3),
        GearEntry('Maker', 'B', 'B', '', null, 'two.svg'),
      ],
    );
    expect(
      d
          .resolve(const PhotoMetadata(cameraMaker: 'Maker', cameraModel: 'C'))
          .cameraMakerLogo,
      isEmpty,
    );
    final exact = d.resolve(
      const PhotoMetadata(cameraMaker: 'Maker', cameraModel: 'A'),
    );
    expect(exact.cameraMakerLogo, 'one.svg');
    expect(exact.cameraMakerLogoScale, 1.3);
  });
  test('機種専用の例外ロゴを未登録の同メーカー機種へ流用しない', () {
    const csv =
        'exif_make,exif_model,display_name,short_name,device_type,maker_logo,model_logo,maker_display_name,maker_logo_scale,maker_logo_fallback\n'
        'SHARP,A504SH,R9 Pro,,smartphone,aquos.svg,,AQUOS,1,true\n'
        'SHARP,LP-03,Leitz Phone 3,,smartphone,leitz.svg,,Leitz,1.3,false\n';
    final d = GearDictionary(cameras: GearDictionary.parse(csv, camera: true));
    for (final display in [true, false]) {
      final phone = d.resolve(
        const PhotoMetadata(cameraMaker: 'SHARP', cameraModel: 'LP-03'),
        useDisplayNames: display,
      );
      expect(phone.cameraMakerLogo, 'leitz.svg');
      expect(phone.cameraMakerLogoScale, 1.3);
      expect(phone.cameraModel, display ? 'Leitz Phone 3' : 'LP-03');
      final unknown = d.resolve(
        const PhotoMetadata(cameraMaker: 'SHARP', cameraModel: 'Unknown'),
        useDisplayNames: display,
      );
      expect(unknown.cameraMakerLogo, 'aquos.svg');
      expect(unknown.cameraMakerLogoScale, 1);
    }
    expect(
      () => GearDictionary.parse(
        csv.replaceAll(',false\n', ',invalid\n'),
        camera: true,
      ),
      throwsFormatException,
    );
  });
  test('ロゴ時専用のモデル文字列は任意CSV列で登録しEXIF名では使わない', () {
    const csv =
        'exif_make,exif_model,display_name,short_name,device_type,maker_logo,model_logo,maker_display_name,model_text_with_logo\n'
        'SHARP,LP-03,Leitz Phone 3,Leitz Phone 3,smartphone,leitz.svg,,Leitz,Leitz Phone 3\n';
    final d = GearDictionary(cameras: GearDictionary.parse(csv, camera: true));
    final m = d.resolve(
      const PhotoMetadata(cameraMaker: 'SHARP', cameraModel: 'LP-03'),
    );
    expect(m.camera, 'Leitz Phone 3');
    expect(m.cameraModelTextWithLogo, 'Leitz Phone 3');
    expect(
      m.withFocalLengthMode(FocalLengthMode.actual).cameraModelTextWithLogo,
      'Leitz Phone 3',
    );
    expect(
      d
          .resolve(
            const PhotoMetadata(cameraMaker: 'SHARP', cameraModel: 'LP-03'),
            useDisplayNames: false,
          )
          .cameraModelTextWithLogo,
      isEmpty,
    );
  });
  test('メーカーと機種を別々に変更・非表示にできる', () {
    const original = PhotoMetadata(
      cameraMaker: 'SONY',
      cameraModel: 'SONY Alpha',
      lensMaker: 'Lens Maker',
      lensModel: 'Lens Maker Zoom',
    );
    expect(original.cameraModelText, 'Alpha');
    final edited = original.withOverrides({
      'cameraMaker': 'My Maker',
      'lensModel': 'My Lens',
    });
    expect(edited.camera, 'My Maker Alpha');
    expect(edited.lens, 'Lens Maker My Lens');
    expect(edited.cameraModelText, 'Alpha');
    expect(original.withOverrides({'cameraMaker': ''}).camera, 'Alpha');
    expect(original.withOverrides({'cameraModel': ''}).camera, 'SONY');
  });
  test('CSVのメーカー表示名でLeicaを登録しEXIF名へ戻せる', () {
    final entries = GearDictionary.parse(
      'exif_make,exif_model,display_name,short_name,device_type,maker_logo,model_logo,maker_display_name\nLEICA CAMERA AG,D-Lux 7,D-Lux 7,D-Lux 7,compact,leica.svg,,Leica\n',
      camera: true,
    );
    final dictionary = GearDictionary(cameras: entries);
    const original = PhotoMetadata(
      cameraMaker: 'LEICA CAMERA AG',
      cameraModel: 'D-Lux 7',
    );
    expect(dictionary.resolve(original).camera, 'Leica D-Lux 7');
    expect(
      dictionary.resolve(original, useDisplayNames: false).camera,
      'LEICA CAMERA AG D-Lux 7',
    );
  });
  test('旧ロゴ別倍率を読み込めるが共通高さで描画する', () {
    final settings = DisplaySettings.parse(
      '{"schemaVersion":1,"logoScales":{"sony.svg":0.6}}',
    );
    expect(settings.logoScales['sony.svg'], .6);
    expect(settings.logoScales['leica.svg'] ?? 1, 1);
    for (final value in ['null', '[]', '{"sony.svg":0}', '{"sony.svg":3}']) {
      expect(
        () => DisplaySettings.parse('{"schemaVersion":1,"logoScales":$value}'),
        throwsFormatException,
      );
    }
  });
  test('左の文字の実描画高さをロゴに合わせ右側の文字サイズを維持する', () {
    const metadata = PhotoMetadata(
      cameraMaker: 'SONY',
      cameraModel: 'Alpha',
      cameraMakerLogo: 'sony.svg',
      lensModel: 'Lens',
      iso: 400,
    );
    final lines = layoutCaption(
      metadata,
      FrameGeometry.forPhoto(7008, 4672),
      settings: const DisplaySettings(logoScales: {'sony.svg': .6}),
    );
    final camera = lines.firstWhere((line) => line.role == 'camera');
    final model = camera.parts.last;
    expect(camera.parts.first.fontSize, closeTo(model.fontSize!, .001));
    expect(model.fontSize, greaterThan(4672 * .024));
    expect(
      camera.parts.first.bounds.bottom,
      closeTo(model.bounds.bottom, .001),
    );
    expect(model.fontSize! * .7, closeTo(4672 * .021, .001));
    expect(
      lines.firstWhere((line) => line.role == 'settings').fontSize,
      closeTo(4672 * .018, .001),
    );
    expect(
      lines.firstWhere((line) => line.role == 'lensModel').fontSize,
      closeTo(4672 * .019, .001),
    );
  });
  test('実焦点距離なし・換算値だけなら機材区分によらず自動で換算値を使う', () {
    for (final type in [null, ...DeviceType.values]) {
      final metadata = PhotoMetadata(
        cameraMaker: 'Insta360',
        cameraModel: 'Luna Ultra',
        focalLength35: 20,
        deviceType: type,
      );
      expect(metadata.usesEquivalent, isTrue);
      expect(metadata.focalText, '20mm eq.');
      expect(
        metadata.withFocalLengthMode(FocalLengthMode.actual).focalText,
        isEmpty,
      );
    }
    const ordinary = PhotoMetadata(focalLength: 25, focalLength35: 50);
    expect(ordinary.focalText, '25mm');
  });
  test('メーカー込みの機種ロゴ設定をCSVから読み取れる', () {
    const csv =
        'exif_make,exif_model,display_name,short_name,device_type,maker_logo,model_logo,model_logo_includes_maker\nInsta360,Luna Ultra,Luna Ultra,Luna Ultra,compact,,luna-ultra.svg,true\n';
    final dictionary = GearDictionary(
      cameras: GearDictionary.parse(csv, camera: true),
    );
    final metadata = dictionary.resolve(
      const PhotoMetadata(
        cameraMaker: 'Insta360',
        cameraModel: 'Luna Ultra',
        focalLength35: 20,
      ),
    );
    expect(metadata.cameraModelLogoIncludesMaker, isTrue);
    expect(metadata.copyWith().cameraModelLogoIncludesMaker, isTrue);
    expect(metadata.focalText, '20mm eq.');
    expect(
      () => GearDictionary.parse(
        csv.replaceFirst(',true', ',invalid'),
        camera: true,
      ),
      throwsFormatException,
    );
  });
  test('ロゴ倍率をCSVで独立指定でき既存CSVは1倍になる', () {
    const csv =
        'exif_make,exif_model,display_name,short_name,device_type,maker_logo,model_logo,maker_logo_scale,model_logo_scale\nInsta360,Luna Ultra,Luna Ultra,,compact,,luna.svg,1,2.2\nLEICA CAMERA AG,D-Lux 7,D-Lux 7,,compact,leica.svg,,1.1,1\n';
    final dictionary = GearDictionary(
      cameras: GearDictionary.parse(csv, camera: true),
    );
    final luna = dictionary.resolve(
      const PhotoMetadata(cameraMaker: 'Insta360', cameraModel: 'Luna Ultra'),
    );
    expect(luna.cameraModelLogoScale, 2.2);
    expect(luna.withOverrides({'iso': 'ISO100'}).cameraModelLogoScale, 2.2);
    final leica = dictionary.resolve(
      const PhotoMetadata(
        cameraMaker: 'LEICA CAMERA AG',
        cameraModel: 'D-Lux 7',
      ),
    );
    expect(leica.cameraMakerLogoScale, 1.1);
    expect(leica.cameraModelLogoScale, 1);
    for (final value in ['0', '-1', 'NaN', 'Infinity', '6', 'text']) {
      expect(
        () => GearDictionary.parse(
          csv.replaceFirst(',2.2\n', ',$value\n'),
          camera: true,
        ),
        throwsFormatException,
      );
    }
    expect(const GearEntry('M', 'C', 'C', '', null).makerLogoScale, 1);
    const lensCsv = 'exif_make,exif_model,display_name,short_name\nM,L,L,\n';
    final lens = GearDictionary(
      lenses: GearDictionary.parse(lensCsv, camera: false),
    ).resolve(const PhotoMetadata(lensModel: 'L'));
    expect(lens.lensMaker, 'M');
  });
  setUpAll(() async {
    await (FontLoader(
      'ShareTech',
    )..addFont(rootBundle.load('assets/fonts/ShareTech-Regular.ttf'))).load();
  });
  test('カメラのメーカーと機種は同じ1行に重複なく並ぶ', () {
    final lines = layoutCaption(
      const PhotoMetadata(cameraMaker: 'SONY', cameraModel: 'SONY α7C II'),
      FrameGeometry.forPhoto(600, 400),
    );
    expect(lines.length, 1);
    expect(lines.single.role, 'camera');
    expect(lines.single.text, 'SONY α7C II');
  });
  test('一時修正・空欄・元に戻す操作は元の機材情報を変えない', () {
    const original = PhotoMetadata(
      cameraMaker: 'LEICA CAMERA AG',
      cameraModel: 'D-Lux 7',
      lensModel: 'Lens',
      focalLength: 15.9,
      focalLength35: 35,
      fNumber: 2.3,
    );
    final edited = original.withOverrides({
      'camera': 'LEICA D-Lux 7',
      'lens': '',
      'focal': '35mm eq.',
      'aperture': 'F4',
      'iso': 'ISO800',
    });
    expect(edited.camera, 'LEICA D-Lux 7');
    expect(edited.lens, '');
    expect(edited.settings, '35mm eq.  F4  ISO800');
    expect(original.fNumber, 2.3);
    expect(original.camera, 'LEICA CAMERA AG D-Lux 7');
    expect(edited.withOverrides({}).settings, original.settings);
    expect(
      edited.withFocalLengthMode(FocalLengthMode.actual).focalText,
      '15.9mm',
    );
    expect(
      edited.withFocalLengthMode(FocalLengthMode.actual).apertureText,
      'F4',
    );
  });
  test('HQは元画素数、SNSはフレーム込み長辺2048pxで小画像を拡大しない', () {
    final photo = img.Image(width: 1600, height: 1000);
    img.fill(photo, color: img.ColorRgb8(30, 100, 160));
    final input = img.encodePng(photo);
    final g = FrameGeometry.forPhoto(1600, 1000);
    {
      final hq = img.decodeImage(renderExport(ExportRequest(input)))!;
      final sns = img.decodeImage(
        renderExport(ExportRequest(input, mode: OutputMode.sns)),
      )!;
      expect([hq.width, hq.height], [g.width, g.height]);
      // This input is below 2048px after framing and must not be enlarged.
      expect([sns.width, sns.height], [g.width, g.height]);
      expect(hq.exif.imageIfd.isEmpty, isTrue);
    }
    final large = FrameGeometry.forPhoto(4928, 3288);
    final sns = outputDimensions(large, OutputMode.sns);
    expect(sns.width, 2048);
    expect(sns.height, closeTo(large.height * 2048 / large.width, 1));
  });
  test('SNSで文字を含む全体が縮小され、JPEG形式で保存する', () {
    final photo = img.Image(width: 2100, height: 100);
    img.fill(photo, color: img.ColorRgb8(30, 100, 160));
    final g = FrameGeometry.forPhoto(2100, 100);
    final layer = img.Image(width: g.width, height: g.bottom, numChannels: 4);
    img.fillRect(
      layer,
      x1: 10,
      y1: 5,
      x2: 100,
      y2: 20,
      color: img.ColorRgba8(0, 0, 0, 255),
    );
    final data = renderExport(
      ExportRequest(
        img.encodePng(photo),
        caption: img.encodePng(layer),
        mode: OutputMode.sns,
      ),
    );
    expect(data.take(2), [255, 216]);
    final output = img.decodeJpg(data)!;
    expect(output.width, 2048);
    expect(output.getPixel(30, output.height - 10).r, lessThan(100));
  });
  test('settings.jsonの不正値を拒否し、標準値は仕様と一致する', () {
    final s = DisplaySettings.parse(DisplaySettings.sample);
    expect(s.cameraTextScale, .024);
    expect(s.bottomOffsetScale, .04);
    for (final source in [
      '{"schemaVersion":2}',
      '{"schemaVersion":1,"cameraTextScale":-1}',
      '{"schemaVersion":1,"exifTextScale":null}',
      '{"schemaVersion":1,"typo":1}',
      '{"schemaVersion":1,"fontFamily":"missing"}',
    ]) {
      expect(() => DisplaySettings.parse(source), throwsFormatException);
    }
    final lines = layoutCaption(
      const PhotoMetadata(
        cameraMaker: 'Maker',
        cameraModel: 'Model',
        lensMaker: 'Lens maker',
        lensModel: 'Lens model',
        iso: 400,
      ),
      FrameGeometry.forPhoto(400, 600),
      settings: const DisplaySettings(
        cameraTextScale: .06,
        lensTextScale: .06,
        exifTextScale: .06,
        bottomOffsetScale: .15,
      ),
    );
    expect(lines.every((line) => line.bounds.top >= 0), isTrue);
  });
  test('不正なsettings.jsonを上書きせずに案内し標準値を使う', () async {
    final folder = await Directory.systemTemp.createTemp('frame_settings-');
    try {
      await GearConfiguration.load(folder);
      final file = File('${folder.path}/settings.json');
      await file.writeAsString('broken');
      final result = await GearConfiguration.load(folder);
      expect(result.warning, contains('settings.json'));
      expect(await file.readAsString(), 'broken');
    } finally {
      await folder.delete(recursive: true);
    }
  });
  test('HQと縮小したSNSでsRGBプロファイルをJPEGへ保持する', () {
    final fixture = img.decodePng(
      File('test/fixtures/srgb.png').readAsBytesSync(),
    )!;
    expect(fixture.iccProfile, isNotNull);
    final photo = img.Image(width: 2000, height: 2000)
      ..iccProfile = fixture.iccProfile!.clone();
    img.fill(photo, color: img.ColorRgb8(219, 94, 32));
    final source = img.encodePng(photo);
    for (final mode in OutputMode.values) {
      {
        final output = img.decodeImage(
          renderExport(ExportRequest(source, mode: mode)),
        )!;
        expect(output.iccProfile, isNotNull);
        expect(output.exif.imageIfd.isEmpty, isTrue);
        expect(output.height, mode == OutputMode.sns ? 2048 : 2540);
      }
    }
  });
  testWidgets('PNG・SVGロゴの混在と文字へのフォールバック', (tester) async {
    await tester.runAsync(() async {
      final folder = await Directory.systemTemp.createTemp('frame_logos-');
      final store = LogoStore(folder);
      try {
        final png = img.Image(width: 60, height: 20, numChannels: 4);
        img.fill(png, color: img.ColorRgba8(220, 40, 40, 255));
        await File('${folder.path}/maker.png').writeAsBytes(img.encodePng(png));
        await File('${folder.path}/model.svg').writeAsString(
          '<svg xmlns="http://www.w3.org/2000/svg" width="6" height="2"><rect width="6" height="2" fill="#228833"/></svg>',
        );
        const meta = PhotoMetadata(
          cameraMaker: 'Maker',
          cameraModel: 'Model',
          cameraMakerLogo: 'maker.png',
          cameraModelLogo: 'model.svg',
          lensMaker: 'Lens',
          iso: 400,
        );
        final g = FrameGeometry.forPhoto(600, 400);
        final leitz = meta.withEquipment(
          cameraMaker: 'Leitz',
          cameraModel: 'Leitz Phone 3',
          cameraModelLogo: '',
          cameraModelTextWithLogo: 'Leitz Phone 3',
        );
        final makerAsset = (await store.load('maker.png'))!;
        final withLogo = layoutCaption(
          leitz,
          g,
          logos: {'maker.png': makerAsset},
        ).first;
        expect(withLogo.parts.first.logo, isNotNull);
        expect(withLogo.parts.last.text, 'Leitz Phone 3');
        final withoutLogo = layoutCaption(leitz, g).first;
        expect(withoutLogo.parts.map((p) => p.text).join(' '), 'Leitz Phone 3');
        final editedLeitzLine = layoutCaption(
          leitz.withOverrides({'cameraModel': 'Custom Phone'}),
          g,
          logos: {'maker.png': makerAsset},
        ).first;
        expect(editedLeitzLine.parts.last.text, 'Custom Phone');

        final pngLayer = await renderCaption(meta, g, logoStore: store);
        final layer = img.decodePng(pngLayer!)!;
        expect(layer.any((p) => p.a > 0 && p.r > 180 && p.g < 100), isTrue);
        expect(layer.any((p) => p.a > 0 && p.g > 100 && p.r < 80), isTrue);
        expect(store.warnings, isEmpty);
        final camera = layoutCaption(
          meta,
          g,
          logos: {
            'maker.png': (await store.load('maker.png'))!,
            'model.svg': (await store.load('model.svg'))!,
          },
        ).first;
        expect(camera.parts.length, 2);
        final independentlyScaled = layoutCaption(
          meta.copyWith(cameraMakerLogoScale: 1.1, cameraModelLogoScale: 2.2),
          g,
          logos: {
            'maker.png': (await store.load('maker.png'))!,
            'model.svg': (await store.load('model.svg'))!,
          },
        ).first;
        expect(
          independentlyScaled.parts[0].bounds.height,
          closeTo(camera.parts[0].bounds.height * 1.1, .001),
        );
        expect(
          independentlyScaled.parts[1].bounds.height,
          closeTo(camera.parts[1].bounds.height * 2.2, .001),
        );

        final combined = meta.copyWith(cameraModelLogoIncludesMaker: true);
        final combinedLine = layoutCaption(
          combined,
          g,
          logos: {'model.svg': (await store.load('model.svg'))!},
        ).first;
        expect(combinedLine.parts.length, 1);
        expect(combinedLine.parts.single.logo, isNotNull);
        final textFallback = layoutCaption(combined, g).first;
        expect(textFallback.parts.length, 2);
        expect(textFallback.parts.first.text, 'Maker');
        final editedCombined = layoutCaption(
          combined.withOverrides({'cameraModel': 'Custom model'}),
          g,
          logos: {'model.svg': (await store.load('model.svg'))!},
        ).first;
        expect(editedCombined.parts.length, 2);

        // A small SVG must scale to the maker height; its original canvas is not a pixel limit.
        expect(
          camera.parts[1].bounds.height,
          closeTo(camera.parts[0].bounds.height, .001),
        );
        final big = layoutCaption(
          meta,
          FrameGeometry.forPhoto(7008, 4672),
          logos: {
            'maker.png': (await store.load('maker.png'))!,
            'model.svg': (await store.load('model.svg'))!,
          },
        ).first;
        expect(
          big.parts[1].bounds.height,
          closeTo(big.parts[0].bounds.height, .001),
        );

        expect(camera.parts.every((part) => part.logo != null), isTrue);
        expect(camera.bounds.height, closeTo(400 * .021, .001));
        final tones = img.decodePng(
          (await renderCaption(
            const PhotoMetadata(
              cameraMaker: 'SONY',
              cameraModel: 'Alpha',
              lensModel: 'Lens',
              iso: 400,
            ),
            FrameGeometry.forPhoto(3000, 2000),
          ))!,
        )!;
        expect(
          tones.any(
            (p) =>
                p.x < tones.width / 2 &&
                p.a == 255 &&
                p.r == 0 &&
                p.g == 0 &&
                p.b == 0,
          ),
          isTrue,
        );
        expect(
          tones.any(
            (p) =>
                p.x > tones.width / 2 &&
                p.a == 255 &&
                p.r == 68 &&
                p.g == 72 &&
                p.b == 68,
          ),
          isTrue,
        );
        final textModel = PhotoMetadata(
          cameraMaker: 'Maker',
          cameraModel: 'GX7 II',
          cameraMakerLogo: 'maker.png',
        );
        final aligned = img.decodePng(
          (await renderCaption(
            textModel,
            FrameGeometry.forPhoto(3000, 2000),
            logoStore: store,
          ))!,
        )!;
        expect(
          aligned.any(
            (pixel) =>
                pixel.a == 255 && pixel.r == 0 && pixel.g == 0 && pixel.b == 0,
          ),
          isTrue,
          reason: '文字色は純黒',
        );
        var logoBottom = -1, textBottom = -1;
        for (final pixel in aligned) {
          if (pixel.a < 32) continue;
          if (pixel.r > 180 && pixel.g < 100) logoBottom = pixel.y;
          if (pixel.r < 120 && pixel.g < 120 && pixel.b < 120) {
            textBottom = pixel.y;
          }
        }
        var logoTop = aligned.height, textTop = aligned.height;
        for (final pixel in aligned) {
          if (pixel.a < 32) continue;
          if (pixel.r > 180 && pixel.g < 100 && pixel.y < logoTop) {
            logoTop = pixel.y;
          }
          if (pixel.r < 120 &&
              pixel.g < 120 &&
              pixel.b < 120 &&
              pixel.y < textTop) {
            textTop = pixel.y;
          }
        }
        expect(
          textBottom - textTop,
          closeTo(logoBottom - logoTop, 1),
          reason: '見える文字高さをロゴに合わせる',
        );
        expect(logoBottom, greaterThan(0));
        expect(
          textBottom,
          closeTo(logoBottom, 2),
          reason: 'ロゴの見える下端とGX7 IIの下端',
        );

        final reduced = layoutCaption(
          meta,
          g,
          settings: const DisplaySettings(
            logoScales: {'maker.png': .6, 'model.svg': .6},
          ),
          logos: {
            'maker.png': (await store.load('maker.png'))!,
            'model.svg': (await store.load('model.svg'))!,
          },
        ).first;
        expect(reduced.bounds.height, closeTo(camera.bounds.height, .001));

        await File('${folder.path}/bad.svg').writeAsString('<bad');
        expect(await store.load('bad.svg'), isNull);
        expect(await store.load('../outside.png'), isNull);
        await File('${folder.path}/external.svg').writeAsString(
          '<svg><image href="https://example.com/image.png"/></svg>',
        );
        expect(await store.load('external.svg'), isNull);
        final edited = meta.withOverrides({'camera': 'Custom name'});
        expect(
          layoutCaption(
            edited,
            g,
            logos: {'maker.png': (await store.load('maker.png'))!},
          ).first.parts,
          isEmpty,
        );
      } finally {
        store.dispose();
        await folder.delete(recursive: true);
      }
    });
  }, skip: kPublicTextOnly);
}
