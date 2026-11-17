import 'package:flutter/material.dart';

import '../caption_sizes.dart';
import '../frame.dart';
import '../photo_metadata.dart';

/// Android display settings. Parent callbacks own state and persistence.
class AndroidSettingsPanel extends StatelessWidget {
  const AndroidSettingsPanel({
    super.key,
    required this.busy,
    required this.hasConfiguration,
    required this.hasPreferences,
    required this.hasPhoto,
    required this.showLogoOption,
    required this.showMetadata,
    required this.showLogos,
    required this.useDisplayNames,
    required this.focalLengthMode,
    required this.margins,
    required this.sizes,
    required this.onMetadataChanged,
    required this.onLogosChanged,
    required this.onNameSourceChanged,
    required this.onFocalChanged,
    required this.onAdjustMargins,
    required this.onAdjustSizes,
  });

  final bool busy;
  final bool hasConfiguration;
  final bool hasPreferences;
  final bool hasPhoto;
  final bool showLogoOption;
  final bool showMetadata;
  final bool showLogos;
  final bool useDisplayNames;
  final FocalLengthMode focalLengthMode;
  final FrameMargins margins;
  final CaptionSizes sizes;
  final ValueChanged<bool> onMetadataChanged;
  final ValueChanged<bool> onLogosChanged;
  final ValueChanged<bool> onNameSourceChanged;
  final ValueChanged<FocalLengthMode> onFocalChanged;
  final VoidCallback onAdjustMargins;
  final VoidCallback onAdjustSizes;

  static bool _largeSettingText(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(14) > 18;

  static String _percent(double ratio) => '${(ratio * 100).round()}%';

  Widget _settingRow(BuildContext context, String title, Widget control) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final label = Text(
              title,
              style: Theme.of(context).textTheme.labelLarge,
            );
            if (constraints.maxWidth < 310 || _largeSettingText(context)) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [label, const SizedBox(height: 4), control],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 80,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 15),
                    child: label,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: control),
              ],
            );
          },
        ),
      );

  Widget _segments<T>(
    BuildContext context,
    String title,
    T value,
    Map<T, String> items,
    ValueChanged<T> onChanged, {
    bool enabled = true,
  }) {
    final control = SegmentedButton<T>(
      expandedInsets: EdgeInsets.zero,
      showSelectedIcon: false,
      segments: [
        for (final entry in items.entries)
          ButtonSegment(
            value: entry.key,
            label: Text(entry.value, textAlign: TextAlign.center),
          ),
      ],
      selected: {value},
      onSelectionChanged: !enabled || busy || !hasConfiguration
          ? null
          : (selection) => onChanged(selection.single),
    );
    return _settingRow(context, title, control);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingLabel = theme.textTheme.labelLarge;
    final sectionTitle = theme.textTheme.titleMedium?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w600,
    );
    final metadata = SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(showLogoOption ? '撮影情報表示' : '撮影情報を表示', style: settingLabel),
      value: showMetadata,
      onChanged: busy ? null : onMetadataChanged,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('表示設定', style: sectionTitle),
        LayoutBuilder(
          builder: (context, constraints) {
            if (!showLogoOption) return metadata;
            final logos = SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('ロゴで表示', style: settingLabel),
              value: showLogos,
              onChanged: busy ? null : onLogosChanged,
            );
            if (constraints.maxWidth < 310 || _largeSettingText(context)) {
              return Column(children: [metadata, logos]);
            }
            return Row(
              children: [
                Expanded(child: metadata),
                const SizedBox(width: 24),
                Expanded(child: logos),
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        _segments<bool>(context, '機材名', useDisplayNames, const {
          true: '記憶した名前',
          false: 'EXIF名',
        }, onNameSourceChanged),
        _segments<FocalLengthMode>(
          context,
          '焦点距離',
          focalLengthMode,
          const {
            FocalLengthMode.actual: '実焦点',
            FocalLengthMode.equivalent: '35mm換算',
          },
          onFocalChanged,
          enabled: hasPhoto,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('余白'),
          subtitle: Text(
            '左右${_percent(margins.side)}・上${_percent(margins.top)}'
            '・下${_percent(margins.bottom)}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: busy || !hasPreferences ? null : onAdjustMargins,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(showLogoOption ? '文字・ロゴサイズ' : '文字サイズ'),
          subtitle: Text('左${_percent(sizes.left)}・右${_percent(sizes.right)}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: busy || !hasPreferences ? null : onAdjustSizes,
        ),
      ],
    );
  }
}
