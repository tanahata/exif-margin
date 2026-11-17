import 'photo_metadata.dart';

/// Labels for the eight editable caption fields, shared across platforms.
/// Keep their order aligned with [metadataFields].
const editableMetadataFieldLabels = <String, String>{
  'cameraMaker': 'メーカー',
  'cameraModel': '機種名',
  'lensMaker': 'メーカー',
  'lensModel': 'レンズ名',
  'focal': '焦点距離',
  'aperture': 'F値',
  'shutter': 'シャッター速度',
  'iso': 'ISO',
};

/// The eight editable caption values. They never rewrite source EXIF.
Map<String, String> metadataFields(PhotoMetadata value) => {
  'cameraMaker': value.cameraMakerText,
  'cameraModel': value.cameraModelText,
  'lensMaker': value.lensMakerText,
  'lensModel': value.lensModelText,
  'focal': value.focalText,
  'aperture': value.apertureText,
  'shutter': value.shutterText,
  'iso': value.isoText,
};

PhotoMetadata applyMetadataFields(
  PhotoMetadata base,
  Map<String, String> values,
) {
  final defaults = metadataFields(base);
  return base.withOverrides({
    for (final entry in values.entries)
      if (PhotoMetadata.cleanText(entry.value) != defaults[entry.key])
        entry.key: entry.value,
  });
}
