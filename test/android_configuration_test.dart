import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_frame/src/android/configuration_import.dart';
import 'package:photo_frame/src/display_settings.dart';
import 'package:photo_frame/src/gear_dictionary.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('config-test-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  // Synthetic import data; production defaults contain headers only.
  final sampleCameraCsv =
      '${GearConfiguration.cameraSample}Example,Model,Example Camera,Example,interchangeable,,,1,1\n';
  final sampleLensCsv =
      '${GearConfiguration.lensSample}ExampleLens,Lens,Example Lens,Lens\n';
  Archive valid({String prefix = ''}) => Archive()
    ..add(ArchiveFile.string('${prefix}cameras.csv', sampleCameraCsv))
    ..add(ArchiveFile.string('${prefix}lenses.csv', sampleLensCsv))
    ..add(ArchiveFile.string('${prefix}settings.json', DisplaySettings.sample));
  File zip(Archive archive) =>
      File('${root.path}/input.zip')
        ..writeAsBytesSync(ZipEncoder().encode(archive));
  for (final prefix in ['', 'EXIFMargin/']) {
    test('直下／単一親フォルダの設定ZIPを厳密に読み込める $prefix', () {
      final stage = extractConfiguration((
        zip(valid(prefix: prefix)).path,
        root.path,
      ));
      final config = readConfigurationStrict(Directory(stage));
      expect(config.dictionary.cameras.length, 1);
      expect(config.dictionary.lenses.length, 1);
    });
  }
  for (final name in [
    '../outside.csv',
    '/absolute.csv',
    'C:/bad.csv',
    r'logos\bad.png',
    'logos/../bad.svg',
  ]) {
    test('危険パスを拒否し何も展開しない $name', () {
      final archive = valid()..add(ArchiveFile.string(name, 'bad'));
      expect(
        () => extractConfiguration((zip(archive).path, root.path)),
        throwsFormatException,
      );
      expect(root.listSync().whereType<Directory>(), isEmpty);
    });
  }
  test('大文字小文字の衝突とシンボリックリンクを拒否する', () {
    expect(
      () => extractConfiguration((
        zip(valid()..add(ArchiveFile.string('CAMERAS.csv', 'bad'))).path,
        root.path,
      )),
      throwsFormatException,
    );
    final link = ArchiveFile.string('logos/outside.svg', '../../outside')
      ..mode = 0xa1ff;
    expect(
      () => extractConfiguration((zip(valid()..add(link)).path, root.path)),
      throwsFormatException,
    );
  });
  test('不正CSV・必須不足・欠けたロゴで旧設定を維持する', () async {
    final repo = ConfigurationRepository(Directory('${root.path}/repository'));
    final baseline = await repo.initialize();
    final pointer = File('${repo.root.path}/active.txt');
    final before = pointer.readAsStringSync();
    for (final archive in [
      Archive()..add(ArchiveFile.string('cameras.csv', 'broken')),
      valid()..add(ArchiveFile.string('cameras.csv', 'broken')),
      Archive()
        ..add(
          ArchiveFile.string(
            'cameras.csv',
            sampleCameraCsv.replaceFirst(
              'interchangeable,,,',
              'interchangeable,missing.svg,,',
            ),
          ),
        )
        ..add(ArchiveFile.string('lenses.csv', sampleLensCsv))
        ..add(ArchiveFile.string('settings.json', DisplaySettings.sample)),
    ]) {
      await expectLater(repo.importZip(zip(archive)), throwsA(anything));
      expect(pointer.readAsStringSync(), before);
      expect(baseline.folder.existsSync(), isTrue);
    }
  });
  test('ZIPサイズ・ファイル数上限を拒否する', () {
    final archive = valid();
    for (var i = 0; i < 256; i++) {
      archive.add(ArchiveFile.string('extra$i', 'x'));
    }
    expect(
      () => extractConfiguration((zip(archive).path, root.path)),
      throwsFormatException,
    );
    final big = File('${root.path}/big.zip')..writeAsBytesSync([0]);
    final handle = big.openSync(mode: FileMode.append)
      ..truncateSync(zipByteLimit + 1);
    handle.closeSync();
    expect(
      () => extractConfiguration((big.path, root.path)),
      throwsFormatException,
    );
  });
  test('取り込み成功時だけ世代を切替え、起動後も取り込み辞書を使う', () async {
    final repo = ConfigurationRepository(Directory('${root.path}/repository'));
    final original = await repo.initialize();
    expect(original.dictionary.cameras, isEmpty);
    expect(original.dictionary.lenses, isEmpty);
    final next = await repo.importZip(zip(valid()));
    expect(next.folder.path, isNot(original.folder.path));
    expect((await repo.initialize()).dictionary.cameras.length, 1);
  });
}
