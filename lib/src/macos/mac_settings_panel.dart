import 'package:flutter/material.dart';

import '../frame.dart';
import '../photo_metadata.dart';
import '../caption_sizes.dart';
import '../public_edition.dart';

/// Mac layout only. Controllers and mutations belong to the parent page.
class MacSettingsPanel extends StatelessWidget {
  const MacSettingsPanel({
    super.key,
    required this.metadata,
    required this.fields,
    required this.margins,
    required this.sizes,
    required this.busy,
    required this.captionPending,
    required this.showMetadata,
    required this.showLogos,
    required this.useDisplayNames,
    required this.canRememberNames,
    required this.onMetadataChanged,
    required this.onLogoChanged,
    required this.onNameSourceChanged,
    required this.onFocalChanged,
    required this.onEditChanged,
    required this.onAdjustMargins,
    required this.onAdjustSizes,
    required this.onReset,
    required this.onRemember,
  });
  final PhotoMetadata? metadata;
  final Map<String, TextEditingController> fields;
  final FrameMargins margins;
  final CaptionSizes sizes;
  final bool busy,
      captionPending,
      showMetadata,
      showLogos,
      useDisplayNames,
      canRememberNames;
  final ValueChanged<bool> onMetadataChanged,
      onLogoChanged,
      onNameSourceChanged;
  final ValueChanged<FocalLengthMode> onFocalChanged;
  final VoidCallback onEditChanged,
      onAdjustMargins,
      onAdjustSizes,
      onReset,
      onRemember;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final section = theme.textTheme.titleMedium?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w600,
    );
    final label = theme.textTheme.labelLarge;
    final detail = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 18;

    Widget settingRow(String title, Widget control) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final heading = Text(title, style: label);
          if (largeText || constraints.maxWidth < 310) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [heading, const SizedBox(height: 4), control],
            );
          }
          return Row(
            children: [
              SizedBox(width: 80, child: heading),
              const SizedBox(width: 8),
              Expanded(child: control),
            ],
          );
        },
      ),
    );

    Widget selector<T>(
      String title,
      T value,
      Map<T, String> items,
      ValueChanged<T> onChanged, {
      Key? key,
    }) => settingRow(
      title,
      Semantics(
        label: title,
        child: SegmentedButton<T>(
          key: key,
          segments: [
            for (final entry in items.entries)
              ButtonSegment(
                value: entry.key,
                label: Text(entry.value, textAlign: TextAlign.center),
                tooltip: entry.value == 'EXIF名' ? 'EXIFに記録された名前' : null,
              ),
          ],
          selected: {value},
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          ),
          onSelectionChanged: busy
              ? null
              : (selected) => onChanged(selected.single),
        ),
      ),
    );

    Widget toggle(
      String title,
      bool value,
      ValueChanged<bool>? change, {
      Key? key,
    }) => SwitchListTile(
      key: key,
      contentPadding: EdgeInsets.zero,
      dense: true,
      minTileHeight: 36,
      title: Text(title, style: label),
      value: value,
      onChanged: change,
    );

    final metadataToggle = toggle(
      kPublicTextOnly ? '撮影情報を表示' : '撮影情報表示',
      showMetadata,
      busy ? null : onMetadataChanged,
    );
    final logoToggle = toggle(
      'ロゴで表示',
      showLogos,
      busy || captionPending ? null : onLogoChanged,
      key: const ValueKey('show_logos'),
    );
    String percent(double value) => '${(value * 100).round()}%';
    Widget adjustment(
      Key key,
      String title,
      String value,
      VoidCallback action,
    ) => settingRow(
      title,
      Row(
        children: [
          Expanded(child: Text(value, style: detail)),
          TextButton(
            key: key,
            onPressed: busy || captionPending ? null : action,
            child: Text('変更', semanticsLabel: '$titleを変更'),
          ),
        ],
      ),
    );
    Widget group(String title) => Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Text(title, style: label),
    );
    Widget editor(String key, String title) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: detail),
        const SizedBox(height: 2),
        Semantics(
          label: switch (key) {
            'cameraMaker' => 'カメラのメーカー',
            'lensMaker' => 'レンズのメーカー',
            _ => title,
          },
          child: TextField(
            key: ValueKey('edit_$key'),
            controller: fields[key],
            enabled: !busy,
            maxLength: 120,
            style: const TextStyle(fontSize: 14),
            onChanged: (_) => onEditChanged(),
            decoration: InputDecoration(
              semanticCounterText: title,
              counterText: '',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              border: const OutlineInputBorder(),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
          ),
        ),
      ],
    );
    Widget editorColumns(Widget left, Widget right) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 8),
        Expanded(child: right),
      ],
    );

    Widget editorRow(
      String leftKey,
      String leftLabel,
      String rightKey,
      String rightLabel,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: editorColumns(
        editor(leftKey, leftLabel),
        editor(rightKey, rightLabel),
      ),
    );
    return SizedBox(
      width: 330,
      child: SingleChildScrollView(
        key: const ValueKey('settings_scroll'),
        child: SizedBox(
          width: 330,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('表示設定', style: section),
              const SizedBox(height: 4),
              if (kPublicTextOnly)
                metadataToggle
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (largeText || constraints.maxWidth < 310) {
                      return Column(children: [metadataToggle, logoToggle]);
                    }
                    return Row(
                      children: [
                        Expanded(child: metadataToggle),
                        const SizedBox(width: 24),
                        Expanded(child: logoToggle),
                      ],
                    );
                  },
                ),
              const SizedBox(height: 8),
              if (metadata case final photo?) ...[
                selector(
                  '機材名の表示',
                  useDisplayNames,
                  const {true: '記憶した名前', false: 'EXIF名'},
                  onNameSourceChanged,
                  key: const ValueKey('name_source'),
                ),
                selector(
                  '焦点距離',
                  photo.usesEquivalent
                      ? FocalLengthMode.equivalent
                      : FocalLengthMode.actual,
                  const {
                    FocalLengthMode.actual: '実焦点',
                    FocalLengthMode.equivalent: '35mm換算',
                  },
                  onFocalChanged,
                  key: const ValueKey('focal_mode'),
                ),
              ],
              adjustment(
                const ValueKey('adjust_margins'),
                '余白',
                '左右${percent(margins.side)}・上${percent(margins.top)}・下${percent(margins.bottom)}',
                onAdjustMargins,
              ),
              adjustment(
                const ValueKey('adjust_sizes'),
                kPublicTextOnly ? '文字サイズ' : '文字・ロゴ',
                '左${percent(sizes.left)}・右${percent(sizes.right)}',
                onAdjustSizes,
              ),
              if (metadata != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('表示文字を修正', style: section),
                    Text('空欄は表示しません。', style: detail),
                  ],
                ),
                group('カメラ'),
                editorRow('cameraMaker', 'メーカー', 'cameraModel', '機種名'),
                group('レンズ'),
                editorRow('lensMaker', 'メーカー', 'lensModel', 'レンズ名'),
                group('撮影条件'),
                editorRow('focal', '焦点距離', 'aperture', 'F値'),
                editorRow('shutter', 'シャッター速度', 'iso', 'ISO'),
                const SizedBox(height: 8),
                editorColumns(
                  TextButton(
                    onPressed: busy ? null : onReset,
                    child: const Text('読み取り内容に戻す', textAlign: TextAlign.center),
                  ),
                  Tooltip(
                    message: 'このカメラのメーカー・機種名とレンズ名を次回も使います。',
                    child: OutlinedButton(
                      onPressed:
                          busy ||
                              captionPending ||
                              !useDisplayNames ||
                              !canRememberNames
                          ? null
                          : onRemember,
                      child: const Text('機材名を記憶', textAlign: TextAlign.center),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
