import '../frame.dart';
import '../gear_dictionary.dart';
import '../photo_metadata.dart';
import '../metadata_fields.dart';

/// Preferences exist only in memory; photo-specific overrides never cross loads.
class EditSession {
  OutputMode mode = OutputMode.hq;
  bool showMetadata = true, showLogos = true, useDisplayNames = true;
  FocalLengthMode focalPreference = FocalLengthMode.automatic;
  PhotoMetadata? original, base, metadata;
  double? manualEquivalent;

  void load(PhotoMetadata value, GearDictionary dictionary) {
    original = value;
    manualEquivalent = null;
    focalPreference = FocalLengthMode.automatic;
    resolve(dictionary, preserveEdits: false);
  }

  void resolve(GearDictionary dictionary, {bool preserveEdits = true}) {
    if (original == null) return;
    var resolved = dictionary.resolve(
      original!,
      useDisplayNames: useDisplayNames,
    );
    if (manualEquivalent != null) {
      resolved = resolved.copyWith(focalLength35: manualEquivalent);
    }
    final available = switch (focalPreference) {
      FocalLengthMode.actual when resolved.focalLength == null =>
        FocalLengthMode.automatic,
      FocalLengthMode.equivalent when resolved.focalLength35 == null =>
        FocalLengthMode.automatic,
      _ => focalPreference,
    };
    base = resolved.withFocalLengthMode(available);
    metadata = base!.withOverrides(
      preserveEdits ? metadata?.overrides ?? {} : {},
    );
  }

  void setEquivalent(double value, GearDictionary dictionary) {
    if (!value.isFinite || value <= 0) {
      throw const FormatException('0より大きい数値を入力してください。');
    }
    if (original == null) return;
    manualEquivalent = value;
    focalPreference = FocalLengthMode.equivalent;
    final edits = {...?metadata?.overrides}..remove('focal');
    resolve(dictionary);
    metadata = base!.withOverrides(edits);
  }

  void resetEdits() => metadata = base;
  void edit(Map<String, String> values) {
    if (base == null) return;
    metadata = applyMetadataFields(base!, values);
  }

  static Map<String, String> fields(PhotoMetadata value) =>
      metadataFields(value);
}
