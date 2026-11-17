import 'dart:convert';

class DisplaySettings {
  const DisplaySettings({
    this.cameraTextScale = .024,
    this.lensTextScale = .019,
    this.exifTextScale = .018,
    this.logoHeightScale = .021,
    this.logoMaxWidthScale = .25,
    this.bottomOffsetScale = .04,
    this.logoScales = const {},
    this.cameraGlyphHeightScale,
    this.typographyUsesPhotoWidth = false,
  });
  // An explicit camera glyph height keeps text sizing independent of logo sizing.
  final double? cameraGlyphHeightScale;
  final bool typographyUsesPhotoWidth;
  final Map<String, double> logoScales;

  DisplaySettings withSizeMultipliers({
    required double text,
    required double logo,
  }) => DisplaySettings(
    cameraTextScale: cameraTextScale * text,
    lensTextScale: lensTextScale * text,
    exifTextScale: exifTextScale * text,
    logoHeightScale: logoHeightScale * logo,
    logoMaxWidthScale: logoMaxWidthScale * logo,
    bottomOffsetScale: bottomOffsetScale,
    logoScales: logoScales,
    cameraGlyphHeightScale: (cameraGlyphHeightScale ?? logoHeightScale) * text,
    typographyUsesPhotoWidth: typographyUsesPhotoWidth,
  );
  final double cameraTextScale, lensTextScale, exifTextScale;
  final double logoHeightScale, logoMaxWidthScale, bottomOffsetScale;

  factory DisplaySettings.parse(String source) {
    final data = jsonDecode(source);
    if (data is! Map || data['schemaVersion'] != 1) {
      throw const FormatException('settings.jsonのschemaVersionは1にしてください。');
    }
    if (data['fontFamily'] != null &&
        !['ShareTech', 'ShareTechMono'].contains(data['fontFamily'])) {
      throw const FormatException('fontFamilyはShareTechにしてください。');
    }
    const keys = {
      'schemaVersion',
      'fontFamily',
      'cameraTextScale',
      'lensTextScale',
      'exifTextScale',
      'logoHeightScale',
      'logoMaxWidthScale',
      'bottomOffsetScale',
      'logoScales',
    };
    if (data.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('settings.jsonに不明な項目があります。項目名を確認してください。');
    }
    double number(String key, double fallback, double min, double max) {
      final value = data.containsKey(key) ? data[key] : fallback;
      if (value is! num || !value.isFinite || value < min || value > max) {
        throw FormatException('$keyは$min〜$maxの数値にしてください。');
      }
      return value.toDouble();
    }

    final scales = <String, double>{};
    if (data.containsKey('logoScales')) {
      final values = data['logoScales'];
      if (values is! Map) {
        throw const FormatException('logoScalesはファイル名と倍率の組にしてください。');
      }
      for (final entry in values.entries) {
        final value = entry.value;
        if (entry.key is! String ||
            (entry.key as String).isEmpty ||
            value is! num ||
            !value.isFinite ||
            value < .1 ||
            value > 2) {
          throw const FormatException('ロゴ倍率は0.1〜2の数値にしてください。');
        }
        scales[entry.key as String] = value.toDouble();
      }
    }
    return DisplaySettings(
      logoScales: Map.unmodifiable(scales),
      cameraTextScale: number('cameraTextScale', .024, .005, .06),
      lensTextScale: number('lensTextScale', .019, .005, .06),
      exifTextScale: number('exifTextScale', .018, .005, .06),
      logoHeightScale: number('logoHeightScale', .021, .005, .08),
      logoMaxWidthScale: number('logoMaxWidthScale', .25, .01, .45),
      bottomOffsetScale: number('bottomOffsetScale', .04, 0, .15),
    );
  }

  static const sample = '''{
  "schemaVersion": 1,
  "fontFamily": "ShareTech",
  "cameraTextScale": 0.024,
  "lensTextScale": 0.019,
  "exifTextScale": 0.018,
  "logoHeightScale": 0.021,
  "logoMaxWidthScale": 0.25,
  "bottomOffsetScale": 0.04
}
''';
}
