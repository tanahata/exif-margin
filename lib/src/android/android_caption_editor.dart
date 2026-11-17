import 'package:flutter/material.dart';

import '../metadata_fields.dart';

/// Editable EXIF caption fields. The parent owns controllers and save actions.
class AndroidCaptionEditor extends StatelessWidget {
  const AndroidCaptionEditor({
    super.key,
    required this.fields,
    required this.busy,
    required this.hasPhoto,
    required this.useDisplayNames,
    required this.onEditChanged,
    required this.onReset,
    required this.onRemember,
  });

  final Map<String, TextEditingController> fields;
  final bool busy;
  final bool hasPhoto;
  final bool useDisplayNames;
  final VoidCallback onEditChanged;
  final VoidCallback onReset;
  final VoidCallback onRemember;

  Widget _editor(String key) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      key: ValueKey('android_edit_$key'),
      controller: fields[key],
      enabled: !busy && hasPhoto,
      maxLength: 120,
      scrollPadding: const EdgeInsets.only(bottom: 32),
      textInputAction: TextInputAction.next,
      onChanged: (_) => onEditChanged(),
      decoration: InputDecoration(
        labelText: editableMetadataFieldLabels[key],
        floatingLabelBehavior: FloatingLabelBehavior.always,
        counterText: '',
        border: const OutlineInputBorder(),
      ),
    ),
  );

  Widget _editorPair(String left, String right) => Row(
    children: [
      Expanded(child: _editor(left)),
      const SizedBox(width: 8),
      Expanded(child: _editor(right)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sectionTitle = theme.textTheme.titleMedium?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w600,
    );
    final settingLabel = theme.textTheme.labelLarge;
    final supportingText = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('表示文字を修正', style: sectionTitle),
            Text('空欄は表示しません。', style: supportingText),
          ],
        ),
        const SizedBox(height: 8),
        Text('カメラ', style: settingLabel),
        _editor('cameraMaker'),
        _editor('cameraModel'),
        const SizedBox(height: 12),
        Text('レンズ', style: settingLabel),
        _editor('lensMaker'),
        _editor('lensModel'),
        const SizedBox(height: 12),
        Text('撮影条件', style: settingLabel),
        _editorPair('focal', 'aperture'),
        _editorPair('shutter', 'iso'),
        TextButton(
          onPressed: busy || !hasPhoto ? null : onReset,
          child: const Text('読み取り内容に戻す'),
        ),
        OutlinedButton(
          style: ButtonStyle(
            side: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? null
                  : BorderSide(color: theme.colorScheme.primary),
            ),
          ),
          onPressed: busy || !hasPhoto || !useDisplayNames ? null : onRemember,
          child: const Tooltip(
            message: '同じ元EXIFの機材に再利用します。撮影条件は記憶しません。',
            child: Text('機材名を記憶する'),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
