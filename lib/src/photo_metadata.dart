import 'package:image/image.dart' as img;

enum DeviceType { interchangeable, compact, smartphone }

enum FocalLengthMode { automatic, actual, equivalent }

class PhotoMetadata {
  const PhotoMetadata({
    this.cameraMaker = '',
    this.cameraModel = '',
    this.cameraShort = '',
    this.lensMaker = '',
    this.lensModel = '',
    this.lensShort = '',
    this.focalLength,
    this.focalLength35,
    this.fNumber,
    this.exposureTime,
    this.iso,
    this.deviceType,
    this.focalLengthMode = FocalLengthMode.automatic,
    this.cameraMakerLogo = '',
    this.cameraModelLogo = '',
    this.cameraModelTextWithLogo = '',
    this.cameraModelLogoIncludesMaker = false,
    this.cameraMakerLogoScale = 1,
    this.cameraModelLogoScale = 1,
    this.overrides = const {},
  });

  factory PhotoMetadata.fromExif(img.ExifData exif) {
    final image = exif.imageIfd;
    final photo = exif.exifIfd;
    var iso = _positive(photo[0x8827]);
    if (iso == null || iso >= 65535) iso = _positive(photo[0x8833]);
    return PhotoMetadata(
      cameraMaker: _text(image['Make']),
      cameraModel: _text(image['Model']),
      lensMaker: _text(photo['LensMake']),
      lensModel: _text(photo['LensModel']),
      focalLength: _positive(photo[0x920a]),
      focalLength35: _positive(photo[0xa405]),
      fNumber: _positive(photo[0x829d]),
      exposureTime: _positive(photo[0x829a]),
      iso: iso,
    );
  }

  final String cameraMaker;
  final String cameraModel;
  final String cameraShort;
  final String lensMaker;
  final String lensModel;
  final String lensShort;
  final double? focalLength;
  final double? focalLength35;
  final double? fNumber;
  final double? exposureTime;
  final double? iso;
  final DeviceType? deviceType;
  final FocalLengthMode focalLengthMode;
  final String cameraMakerLogo, cameraModelLogo;
  final String cameraModelTextWithLogo;
  final bool cameraModelLogoIncludesMaker;
  final double cameraMakerLogoScale, cameraModelLogoScale;
  final Map<String, String> overrides;

  String get cameraMakerText => overrides['cameraMaker'] ?? cameraMaker;
  String get cameraModelText =>
      overrides['cameraModel'] ?? withoutMaker(cameraMaker, cameraModel);
  String get lensMakerText => overrides['lensMaker'] ?? lensMaker;
  String get lensModelText =>
      overrides['lensModel'] ?? withoutMaker(lensMaker, lensModel);
  bool get editedCamera =>
      overrides.containsKey('cameraMaker') ||
      overrides.containsKey('cameraModel');
  bool get editedLensParts =>
      overrides.containsKey('lensMaker') || overrides.containsKey('lensModel');
  String get camera =>
      overrides['camera'] ?? _joinName(cameraMakerText, cameraModelText);
  String get cameraShortDisplay => cameraShort.isEmpty || editedCamera
      ? ''
      : _joinName(cameraMakerText, cameraShort);
  String get lens =>
      overrides['lens'] ?? _joinName(lensMakerText, lensModelText);
  String get cameraDisplayModel =>
      withoutMaker(cameraMakerText, cameraModelText);
  String get lensDisplayModel => withoutMaker(lensMakerText, lensModelText);
  List<String> get lines =>
      [camera, lens, settings].where((s) => s.isNotEmpty).toList();
  bool get isEmpty => lines.isEmpty;

  bool get usesEquivalent =>
      focalLength35 != null &&
      switch (focalLengthMode) {
        FocalLengthMode.actual => false,
        FocalLengthMode.equivalent => true,
        FocalLengthMode.automatic =>
          focalLength == null ||
              deviceType == DeviceType.smartphone ||
              deviceType == DeviceType.compact,
      };

  PhotoMetadata withFocalLengthMode(FocalLengthMode mode) => copyWith(
    focalLengthMode: mode,
    overrides: {...overrides}..remove('focal'),
  );

  String get focalText =>
      overrides['focal'] ??
      ((usesEquivalent ? focalLength35 : focalLength) == null
          ? ''
          : '${number((usesEquivalent ? focalLength35 : focalLength)!)}mm${usesEquivalent ? ' eq.' : ''}');
  String get apertureText =>
      overrides['aperture'] ?? (fNumber == null ? '' : 'F${number(fNumber!)}');
  String get shutterText =>
      overrides['shutter'] ??
      (exposureTime == null ? '' : shutter(exposureTime!));
  String get isoText =>
      overrides['iso'] ?? (iso == null ? '' : 'ISO ${iso!.round()}');
  String get settings => [
    focalText,
    apertureText,
    shutterText,
    isoText,
  ].where((s) => s.isNotEmpty).join('  ');

  PhotoMetadata withOverrides(Map<String, String> values) =>
      copyWith(overrides: values);

  PhotoMetadata withEquipment({
    String? cameraMaker,
    String? cameraModel,
    String? cameraShort,
    String? lensMaker,
    String? lensModel,
    String? lensShort,
    DeviceType? deviceType,
    String? cameraMakerLogo,
    String? cameraModelLogo,
    String? cameraModelTextWithLogo,
    bool? cameraModelLogoIncludesMaker,
    double? cameraModelLogoScale,
    double? cameraMakerLogoScale,
  }) => copyWith(
    cameraMaker: cameraMaker,
    cameraModel: cameraModel,
    cameraShort: cameraShort,
    lensMaker: lensMaker,
    lensModel: lensModel,
    lensShort: lensShort,
    deviceType: deviceType,
    cameraMakerLogo: cameraMakerLogo,
    cameraModelLogo: cameraModelLogo,
    cameraModelTextWithLogo: cameraModelTextWithLogo,
    cameraModelLogoIncludesMaker: cameraModelLogoIncludesMaker,
    cameraModelLogoScale: cameraModelLogoScale,
    cameraMakerLogoScale: cameraMakerLogoScale,
  );

  PhotoMetadata copyWith({
    String? cameraMaker,
    String? cameraModel,
    String? cameraShort,
    String? lensMaker,
    String? lensModel,
    String? lensShort,
    DeviceType? deviceType,
    FocalLengthMode? focalLengthMode,
    double? focalLength35,
    String? cameraMakerLogo,
    String? cameraModelLogo,
    String? cameraModelTextWithLogo,
    bool? cameraModelLogoIncludesMaker,
    double? cameraModelLogoScale,
    double? cameraMakerLogoScale,
    Map<String, String>? overrides,
  }) => PhotoMetadata(
    cameraMaker: cameraMaker ?? this.cameraMaker,
    cameraModel: cameraModel ?? this.cameraModel,
    cameraShort: cameraShort ?? this.cameraShort,
    lensMaker: lensMaker ?? this.lensMaker,
    lensModel: lensModel ?? this.lensModel,
    lensShort: lensShort ?? this.lensShort,
    focalLength: focalLength,
    focalLength35: focalLength35 ?? this.focalLength35,
    fNumber: fNumber,
    exposureTime: exposureTime,
    iso: iso,
    deviceType: deviceType ?? this.deviceType,
    focalLengthMode: focalLengthMode ?? this.focalLengthMode,
    cameraMakerLogo: cameraMakerLogo ?? this.cameraMakerLogo,
    cameraModelLogo: cameraModelLogo ?? this.cameraModelLogo,
    cameraModelTextWithLogo:
        cameraModelTextWithLogo ?? this.cameraModelTextWithLogo,
    cameraModelLogoIncludesMaker:
        cameraModelLogoIncludesMaker ?? this.cameraModelLogoIncludesMaker,
    cameraModelLogoScale: cameraModelLogoScale ?? this.cameraModelLogoScale,
    cameraMakerLogoScale: cameraMakerLogoScale ?? this.cameraMakerLogoScale,
    overrides: overrides == null
        ? this.overrides
        : Map.unmodifiable(overrides.map((k, v) => MapEntry(k, cleanText(v)))),
  );

  static String withoutMaker(String maker, String model) {
    if (maker.isEmpty) return model;
    if (model.toLowerCase() == maker.toLowerCase()) return '';
    if (model.toLowerCase().startsWith('${maker.toLowerCase()} ')) {
      return model.substring(maker.length).trim();
    }
    return model;
  }

  static String _joinName(String maker, String model) =>
      [maker, withoutMaker(maker, model)].where((s) => s.isNotEmpty).join(' ');

  static String cleanText(String text) => String.fromCharCodes(
    text
        .replaceAll(RegExp(r'[\x00-\x1f\x7f-\x9f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .runes
        .take(240),
  );

  static String _text(img.IfdValue? value) =>
      value?.type == img.IfdValueType.ascii ? cleanText(value.toString()) : '';

  static double? _positive(img.IfdValue? value) {
    if (value == null ||
        value.length == 0 ||
        value.type == img.IfdValueType.ascii) {
      return null;
    }
    try {
      final number = switch (value.type) {
        img.IfdValueType.rational ||
        img.IfdValueType.sRational ||
        img.IfdValueType.single ||
        img.IfdValueType.double => value.toDouble(),
        _ => value.toInt().toDouble(),
      };
      return number.isFinite && number > 0 ? number : null;
    } catch (_) {
      return null;
    }
  }

  static String number(double value) =>
      value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  static String shutter(double seconds) {
    if (seconds >= 1) return '${seconds.toStringAsFixed(1)}sec';
    return '1/${(1 / seconds).round()}';
  }
}
