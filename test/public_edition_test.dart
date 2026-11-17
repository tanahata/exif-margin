import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_frame/src/caption.dart';
import 'package:photo_frame/src/frame.dart';
import 'package:photo_frame/src/gear_dictionary.dart';
import 'package:photo_frame/src/logo_store.dart';
import 'package:photo_frame/src/macos/mac_frame_page.dart';
import 'package:photo_frame/src/photo_metadata.dart';
import 'package:photo_frame/src/public_edition.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('公開版のロゴ非対応モードを固定', () {
    expect(kPublicTextOnly, isTrue);
  });

  test('公開版の同梱CSV・初回生成CSVはヘッダーのみ', () {
    for (final camera in [true, false]) {
      final path = camera
          ? 'assets/config/cameras.csv'
          : 'assets/config/lenses.csv';
      final bundled = File(path).readAsStringSync();
      final generated = camera
          ? GearConfiguration.cameraSample
          : GearConfiguration.lensSample;
      for (final csv in [bundled, generated]) {
        expect(
          csv.split(RegExp(r'\r?\n')).where((line) => line.trim().isNotEmpty),
          hasLength(1),
          reason: '公開用の初期CSVに登録行を追加しない: $path',
        );
        expect(GearDictionary.parse(csv, camera: camera), isEmpty);
      }
    }
  });

  test('AndroidとmacOSの公開アプリIDを固定', () {
    final android = File('android/app/build.gradle.kts').readAsStringSync();
    final mac = File('macos/Runner/Configs/AppInfo.xcconfig')
        .readAsStringSync();
    expect(android, contains('applicationId = "net.tameha.exifmargin"'));
    expect(mac, contains('PRODUCT_BUNDLE_IDENTIFIER = net.tameha.exifmargin'));
  });

  testWidgets('EXIF Marginの表示名と公開モードのロゴ操作制限', (tester) async {
    await tester.pumpWidget(const PhotoFrameApp());
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'EXIF Margin',
    );
    expect(find.text('ロゴで表示'), kPublicTextOnly ? findsNothing : findsOneWidget);
    expect(find.text('文字サイズ'), kPublicTextOnly ? findsOneWidget : findsNothing);
  });

  testWidgets('公開版は文字だけ、個人用は従来のロゴを表示できる', (tester) async {
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('photo-frame-public-');
      final store = LogoStore(dir);
      try {
        await File('${dir.path}/sample.svg').writeAsString(
          '<svg xmlns="http://www.w3.org/2000/svg" width="60" height="20">'
          '<rect width="60" height="20" fill="#cc2233"/></svg>',
        );
        const metadata = PhotoMetadata(
          cameraMaker: 'Camera',
          cameraModel: 'Model',
          cameraMakerLogo: 'sample.svg',
        );
        final geometry = FrameGeometry.forPhoto(600, 400);
        final textOnly = await renderCaption(metadata, geometry);
        final withStore = await renderCaption(
          metadata,
          geometry,
          logoStore: store,
        );
        expect(textOnly, isNotNull);
        expect(withStore, isNotNull);
        if (kPublicTextOnly) {
          expect(withStore, orderedEquals(textOnly!));
        } else {
          expect(withStore, isNot(orderedEquals(textOnly!)));
        }
      } finally {
        store.dispose();
        await dir.delete(recursive: true);
      }
    });
  });
}
