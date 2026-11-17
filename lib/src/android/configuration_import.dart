import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../display_settings.dart';
import '../gear_dictionary.dart';
import '../logo_store.dart';

const zipByteLimit = 32 * 1024 * 1024;
const expandedByteLimit = 64 * 1024 * 1024;
const entryByteLimit = 16 * 1024 * 1024;
const entryCountLimit = 256;

/// No arbitrary extraction: names and headers are checked before decompression.
String extractConfiguration((String, String) request) {
  final (zipPath, rootPath) = request;
  final source = File(zipPath);
  if (source.lengthSync() > zipByteLimit) {
    throw const FormatException('ZIPは32MiB以下にしてください。');
  }
  final bytes = source.readAsBytesSync();
  final view = ByteData.sublistView(bytes);
  var end = -1;
  for (var i = bytes.length - 22; i >= 0 && i >= bytes.length - 65557; i--) {
    if (view.getUint32(i, Endian.little) == 0x06054b50 &&
        i + 22 + view.getUint16(i + 20, Endian.little) == bytes.length) {
      end = i;
      break;
    }
  }
  if (end < 0 ||
      view.getUint16(end + 4, Endian.little) != 0 ||
      view.getUint16(end + 6, Endian.little) != 0 ||
      view.getUint16(end + 8, Endian.little) !=
          view.getUint16(end + 10, Endian.little) ||
      view.getUint16(end + 10, Endian.little) > entryCountLimit * 2 ||
      view.getUint32(end + 16, Endian.little) +
              view.getUint32(end + 12, Endian.little) >
          end) {
    throw const FormatException('ZIPのディレクトリ構造が正しくありません。');
  }
  final input = InputMemoryStream(bytes);
  final directory = ZipDirectory()..read(input);
  final headers = directory.fileHeaders;
  if (headers.isEmpty ||
      headers.length > entryCountLimit * 2 ||
      directory.totalCentralDirectoryEntries != headers.length ||
      directory.numberOfThisDisk != 0 ||
      directory.diskWithTheStartOfTheCentralDirectory != 0) {
    throw const FormatException('ZIPの構造またはファイル数が正しくありません。');
  }
  final names = <String>{};
  final files = <ZipFileHeader>[];
  var total = 0;
  for (final header in headers) {
    final name = header.filename;
    final parts = name.split('/');
    if (name.isEmpty ||
        name.length > 300 ||
        name.contains('\\') ||
        name.contains(':') ||
        name.startsWith('/') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name) ||
        parts.any((s) => s == '.' || s == '..') ||
        parts.take(parts.length - 1).any((s) => s.isEmpty) ||
        !names.add(name.toLowerCase()) ||
        ((header.externalFileAttributes >> 16) & 0xf000) == 0xa000 ||
        header.generalPurposeBitFlag & 1 != 0 ||
        header.file == null ||
        header.file!.filename != name ||
        header.file!.flags & 1 != 0 ||
        (header.compressionMethod != 0 && header.compressionMethod != 8) ||
        header.uncompressedSize < 0 ||
        header.uncompressedSize > entryByteLimit) {
      throw const FormatException('ZIPに危険なパス・重複・非対応形式があります。');
    }
    total += header.uncompressedSize;
    if (total > expandedByteLimit) {
      throw const FormatException('展開サイズは64MiB以下にしてください。');
    }
    if (!name.endsWith('/')) files.add(header);
  }
  if (files.length > entryCountLimit) {
    throw const FormatException('ファイルは256件以下にしてください。');
  }
  bool ignored(String name) =>
      name.split('/').contains('__MACOSX') ||
      p.posix.basename(name) == '.DS_Store';
  final useful = files.where((h) => !ignored(h.filename)).toList();
  String prefix = '';
  if (!useful.any((h) => h.filename == 'cameras.csv')) {
    final roots = useful.map((h) => h.filename.split('/').first).toSet();
    if (roots.length != 1) {
      throw const FormatException('設定ファイルは直下か1つの親フォルダにまとめてください。');
    }
    prefix = '${roots.single}/';
  }
  final stage = Directory(rootPath).createTempSync('generation-');
  final accepted = <String>{};
  try {
    for (final header in useful) {
      if (!header.filename.startsWith(prefix)) {
        throw const FormatException('ZIPのフォルダ構成が正しくありません。');
      }
      final name = header.filename.substring(prefix.length);
      final allowed =
          ['cameras.csv', 'lenses.csv', 'settings.json'].contains(name) ||
          (name.startsWith('logos/') &&
              name.split('/').length == 2 &&
              ['.svg', '.png'].contains(p.posix.extension(name).toLowerCase()));
      if (!allowed) {
        continue; // Unknown content is never decompressed or written.
      }
      final output = OutputMemoryStream();
      header.file!.decompress(
        output,
      ); // archive 4.5.2 enforces the header output bound.
      final bytes = output.getBytes();
      if (bytes.length != header.uncompressedSize ||
          getCrc32(bytes) != header.crc32) {
        throw const FormatException('ZIPのデータが破損しています。');
      }
      if (name.toLowerCase().endsWith('.png')) {
        final decoder = img.PngDecoder();
        final info = decoder.startDecode(bytes);
        if (info == null ||
            info.width <= 0 ||
            info.height <= 0 ||
            info.width > 4096 ||
            info.height > 4096 ||
            info.width * info.height > 4000000 ||
            info.numFrames > 1) {
          throw const FormatException('PNGロゴは400万画素・一辺4096px以内の静止画にしてください。');
        }
      }
      if (name.toLowerCase().endsWith('.svg')) {
        final text = utf8.decode(bytes);
        if (RegExp(
          r'<!DOCTYPE|<!ENTITY|<script|<foreignObject',
          caseSensitive: false,
        ).hasMatch(text)) {
          throw const FormatException('自己完結したSVGロゴを使用してください。');
        }
      }
      final file = File(p.joinAll([stage.path, ...name.split('/')]));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes, flush: true);
      accepted.add(name);
    }
    if (!accepted.containsAll(['cameras.csv', 'lenses.csv', 'settings.json'])) {
      throw const FormatException('cameras.csv・lenses.csv・settings.jsonが必要です。');
    }
    // prepareZip validates CSV/JSON and logos before activating this staging folder.
    return stage.path;
  } catch (_) {
    stage.deleteSync(recursive: true);
    rethrow;
  } finally {
    input.closeSync();
  }
}

GearConfiguration readConfigurationStrict(Directory folder) {
  final cameras = GearDictionary.parse(
    File(p.join(folder.path, 'cameras.csv')).readAsStringSync(),
    camera: true,
  );
  final lenses = GearDictionary.parse(
    File(p.join(folder.path, 'lenses.csv')).readAsStringSync(),
    camera: false,
  );
  final settings = DisplaySettings.parse(
    File(p.join(folder.path, 'settings.json')).readAsStringSync(),
  );
  Directory(p.join(folder.path, 'logos')).createSync();
  for (final camera in cameras) {
    for (final name in [
      camera.makerLogo,
      camera.modelLogo,
    ].where((s) => s.isNotEmpty)) {
      if (p.basename(name) != name ||
          name.contains('\\') ||
          !['.svg', '.png'].contains(p.extension(name).toLowerCase()) ||
          !File(p.join(folder.path, 'logos', name)).existsSync()) {
        throw const FormatException('辞書が参照するロゴが見つかりません。');
      }
    }
  }
  return GearConfiguration(
    folder,
    GearDictionary(cameras: cameras, lenses: lenses),
    settings: settings,
  );
}

class ConfigurationRepository {
  ConfigurationRepository(this.root);
  final Directory root;
  File get _pointer => File(p.join(root.path, 'active.txt'));

  Future<GearConfiguration> initialize() async {
    await root.create(recursive: true);
    if (await _pointer.exists()) {
      final name = (await _pointer.readAsString()).trim();
      if (!RegExp(r'^generation-[a-zA-Z0-9]+$').hasMatch(name)) {
        throw const FormatException('設定参照が正しくありません。');
      }
      return readConfigurationStrict(Directory(p.join(root.path, name)));
    }
    final stage = await root.createTemp('generation-');
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      for (final asset in manifest.listAssets().where(
        (s) => s.startsWith('assets/config/'),
      )) {
        final relative = asset.substring('assets/config/'.length);
        final file = File(p.join(stage.path, relative));
        await file.parent.create(recursive: true);
        final data = await rootBundle.load(asset);
        await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      }
      final configuration = readConfigurationStrict(stage);
      await _validateLogos(configuration);
      await _activate(stage);
      return configuration;
    } catch (_) {
      await stage.delete(recursive: true);
      rethrow;
    }
  }

  Future<GearConfiguration> prepareZip(File source) async {
    await root.create(recursive: true);
    final path = await compute(extractConfiguration, (source.path, root.path));
    final stage = Directory(path);
    try {
      final configuration = readConfigurationStrict(stage);
      await _validateLogos(configuration);
      return configuration;
    } catch (_) {
      await stage.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> activate(GearConfiguration configuration) =>
      _activate(configuration.folder);

  Future<GearConfiguration> importZip(File source) async {
    final configuration = await prepareZip(source);
    try {
      await activate(configuration);
      return configuration;
    } catch (_) {
      await configuration.folder.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> _validateLogos(GearConfiguration config) async {
    final folder = Directory(p.join(config.folder.path, 'logos'));
    final store = LogoStore(folder);
    try {
      await for (final entry in folder.list()) {
        if (entry is File) {
          final asset = await store.load(p.basename(entry.path));
          if (asset == null ||
              asset.size.width > 20000 ||
              asset.size.height > 20000) {
            throw const FormatException('表示できないロゴがあります。');
          }
        }
      }
    } finally {
      store.dispose();
    }
  }

  Future<void> _activate(Directory stage) async {
    final temporary = File(p.join(root.path, 'active.next'));
    await temporary.writeAsString(p.basename(stage.path), flush: true);
    await temporary.rename(_pointer.path); // same-filesystem atomic publication
  }

  Future<void> cleanOldGenerations(Directory active) async {
    await for (final entry in root.list()) {
      if (entry is Directory &&
          p.basename(entry.path).startsWith('generation-') &&
          entry.path != active.path) {
        await entry.delete(recursive: true);
      }
    }
  }
}
