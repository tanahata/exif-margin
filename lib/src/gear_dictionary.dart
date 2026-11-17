import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;

import 'photo_metadata.dart';
import 'display_settings.dart';

String normalizedGearName(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

class GearEntry {
  const GearEntry(
    this.make,
    this.model,
    this.display,
    this.shortName,
    this.deviceType, [
    this.makerLogo = '',
    this.modelLogo = '',
    this.makerDisplay = '',
    this.modelLogoIncludesMaker = false,
    this.makerLogoScale = 1,
    this.modelLogoScale = 1,
    this.makerLogoFallback = true,
    this.modelTextWithLogo = '',
  ]);
  final String make;
  final String model;
  final String display;
  final String shortName;
  final DeviceType? deviceType;
  final String makerLogo, modelLogo, makerDisplay;
  final bool modelLogoIncludesMaker;
  final bool makerLogoFallback;
  final String modelTextWithLogo;
  final double makerLogoScale, modelLogoScale;
}

class GearDictionary {
  const GearDictionary({this.cameras = const [], this.lenses = const []});
  final List<GearEntry> cameras;
  final List<GearEntry> lenses;

  static List<GearEntry> parse(String input, {required bool camera}) {
    final normalized = input
        .replaceFirst(RegExp('^\uFEFF'), '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final rows =
        const CsvToListConverter(
              eol: '\n',
              shouldParseNumbers: false,
              allowInvalid: false,
            )
            .convert(normalized)
            .where((row) => row.any((v) => v.toString().trim().isNotEmpty))
            .toList();
    if (rows.isEmpty) throw const FormatException('CSVにヘッダーがありません。');
    final header = rows.first.map((v) => v.toString().trim()).toList();
    final required = [
      'exif_make',
      'exif_model',
      'display_name',
      'short_name',
      if (camera) 'device_type',
      if (camera) 'maker_logo',
      if (camera) 'model_logo',
    ];
    if (header.toSet().length != header.length ||
        required.any((name) => !header.contains(name))) {
      throw const FormatException('CSVの列名が仕様と一致しません。');
    }
    final result = <GearEntry>[];
    final keys = <(String, String)>{};
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length != header.length) {
        throw FormatException('CSV ${i + 1}行目の列数が正しくありません。');
      }
      String field(String key) =>
          PhotoMetadata.cleanText(row[header.indexOf(key)].toString());
      final make = field('exif_make');
      final model = field('exif_model');
      if (model.isEmpty || (camera && make.isEmpty)) {
        throw FormatException('CSV ${i + 1}行目の機材名が空です。');
      }
      final key = (normalizedGearName(make), normalizedGearName(model));
      if (!keys.add(key)) throw FormatException('CSV ${i + 1}行目の機材が重複しています。');
      DeviceType? type;
      if (camera) {
        type = switch (field('device_type')) {
          'interchangeable' => DeviceType.interchangeable,
          'compact' => DeviceType.compact,
          'smartphone' => DeviceType.smartphone,
          _ => throw FormatException('CSV ${i + 1}行目のdevice_typeが正しくありません。'),
        };
      }
      final combinedLogo =
          camera && header.contains('model_logo_includes_maker')
          ? field('model_logo_includes_maker')
          : '';
      if (!['', 'true', 'false'].contains(combinedLogo)) {
        throw FormatException(
          'CSV ${i + 1}行目のmodel_logo_includes_makerはtrueまたはfalseにしてください。',
        );
      }
      final fallback = camera && header.contains('maker_logo_fallback')
          ? field('maker_logo_fallback')
          : '';
      if (!['', 'true', 'false'].contains(fallback)) {
        throw FormatException(
          'CSV ${i + 1}行目のmaker_logo_fallbackはtrueまたはfalseにしてください。',
        );
      }
      double logoScale(String name) {
        final raw = header.contains(name) ? field(name) : '';
        if (raw.isEmpty) return 1;
        final value = double.tryParse(raw);
        if (value == null || !value.isFinite || value < .1 || value > 5) {
          throw FormatException('CSV ${i + 1}行目の$nameは0.1〜5の数値にしてください。');
        }
        return value;
      }

      result.add(
        GearEntry(
          make,
          model,
          field('display_name'),
          field('short_name'),
          type,
          camera ? field('maker_logo') : '',
          camera ? field('model_logo') : '',
          header.contains('maker_display_name')
              ? field('maker_display_name')
              : '',
          combinedLogo == 'true',
          camera ? logoScale('maker_logo_scale') : 1,
          camera ? logoScale('model_logo_scale') : 1,
          fallback != 'false',
          camera && header.contains('model_text_with_logo')
              ? field('model_text_with_logo')
              : '',
        ),
      );
    }
    return result;
  }

  PhotoMetadata resolve(PhotoMetadata original, {bool useDisplayNames = true}) {
    GearEntry? exact(List<GearEntry> entries, String make, String model) {
      final matches = entries
          .where(
            (entry) =>
                normalizedGearName(entry.make) == normalizedGearName(make) &&
                normalizedGearName(entry.model) == normalizedGearName(model),
          )
          .toList();
      return matches.length == 1 ? matches.single : null;
    }

    final camera = exact(cameras, original.cameraMaker, original.cameraModel);
    // Manufacturer defaults are independent of the model registration.
    final makerEntries = cameras.where(
      (entry) =>
          entry.makerLogoFallback &&
          normalizedGearName(entry.make) ==
              normalizedGearName(original.cameraMaker),
    );
    final makerLogos = makerEntries
        .map((entry) => entry.makerLogo)
        .where((name) => name.isNotEmpty)
        .toSet();
    final fallbackLogo = makerLogos.length == 1 ? makerLogos.single : '';
    final makerScales = makerEntries
        .where((entry) => entry.makerLogo == fallbackLogo)
        .map((entry) => entry.makerLogoScale)
        .toSet();
    final fallbackScale = makerScales.length == 1 ? makerScales.single : 1.0;
    final makerNames = makerEntries
        .map((entry) => entry.makerDisplay)
        .where((name) => name.isNotEmpty)
        .toSet();
    final makerDisplay = camera?.makerDisplay.isNotEmpty == true
        ? camera!.makerDisplay
        : makerNames.length == 1
        ? makerNames.single
        : '';
    final exactLogo = camera?.makerLogo.isNotEmpty == true;
    var lens = exact(lenses, original.lensMaker, original.lensModel);
    if (original.lensMaker.isEmpty && original.lensModel.isNotEmpty) {
      final matches = lenses
          .where(
            (entry) =>
                normalizedGearName(entry.model) ==
                normalizedGearName(original.lensModel),
          )
          .toList();
      lens = matches.length == 1 ? matches.single : null;
    }
    return original.withEquipment(
      cameraMaker: useDisplayNames && makerDisplay.isNotEmpty
          ? makerDisplay
          : null,
      cameraModel: useDisplayNames && camera?.display.isNotEmpty == true
          ? camera!.display
          : null,
      cameraShort: useDisplayNames ? camera?.shortName : '',
      deviceType: camera?.deviceType,
      lensMaker: useDisplayNames
          ? (lens?.makerDisplay.isNotEmpty == true
                ? lens!.makerDisplay
                : lens?.make)
          : null,
      lensModel: useDisplayNames && lens?.display.isNotEmpty == true
          ? lens!.display
          : null,
      lensShort: useDisplayNames ? lens?.shortName : '',
      cameraMakerLogo: exactLogo ? camera!.makerLogo : fallbackLogo,
      cameraModelLogo: useDisplayNames ? camera?.modelLogo : '',
      cameraModelLogoIncludesMaker: camera?.modelLogoIncludesMaker ?? false,
      cameraMakerLogoScale: exactLogo ? camera!.makerLogoScale : fallbackScale,
      cameraModelLogoScale: camera?.modelLogoScale ?? 1,
      cameraModelTextWithLogo: useDisplayNames
          ? camera?.modelTextWithLogo ?? ''
          : '',
    );
  }
}

class GearConfiguration {
  const GearConfiguration(
    this.folder,
    this.dictionary, {
    this.warning,
    this.settings = const DisplaySettings(),
  });
  final Directory folder;
  final GearDictionary dictionary;
  final String? warning;
  final DisplaySettings settings;

  static Future<GearConfiguration> load(Directory folder) async {
    await folder.create(recursive: true);
    await Directory(p.join(folder.path, 'logos')).create();
    Future<void> createMissing(String name, String contents) async {
      final file = File(p.join(folder.path, name));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        return;
      }
      try {
        await file.create(exclusive: true);
        await file.writeAsString(contents, flush: true);
      } on PathExistsException {
        // Another instance created it; never replace it.
      }
    }

    await createMissing('cameras.csv', cameraSample);
    await createMissing('lenses.csv', lensSample);
    await createMissing('settings.json', DisplaySettings.sample);
    final warnings = <String>[];
    Future<List<GearEntry>> read(String name, bool camera) async {
      try {
        return GearDictionary.parse(
          await File(p.join(folder.path, name)).readAsString(),
          camera: camera,
        );
      } catch (error) {
        warnings.add('$name を読み込めません。$error');
        return [];
      }
    }

    final cameras = await read('cameras.csv', true);
    final lenses = await read('lenses.csv', false);
    var settings = const DisplaySettings();
    try {
      settings = DisplaySettings.parse(
        await File(p.join(folder.path, 'settings.json')).readAsString(),
      );
    } catch (error) {
      warnings.add('settings.jsonを読み込めません。標準設定を使用します。$error');
    }
    return GearConfiguration(
      folder,
      GearDictionary(cameras: cameras, lenses: lenses),
      warning: warnings.isEmpty ? null : warnings.join('\n'),
      settings: settings,
    );
  }

  static const cameraSample =
      'exif_make,exif_model,display_name,short_name,device_type,maker_logo,model_logo,maker_logo_scale,model_logo_scale\n';
  static const lensSample = 'exif_make,exif_model,display_name,short_name\n';
}
