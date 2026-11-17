import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../frame.dart';
import '../editor_preferences.dart';
import '../margin_dialog.dart';
import '../size_dialog.dart';
import '../manual_focal_dialog.dart';
import '../caption.dart';
import '../safe_save.dart';
import '../gear_dictionary.dart';
import '../photo_metadata.dart';
import '../metadata_fields.dart';
import '../display_settings.dart';
import '../logo_store.dart';
import '../native_photo.dart';
import '../jpeg_profile.dart';
import '../public_edition.dart';
import '../app_theme.dart';

import 'mac_settings_panel.dart';

class PhotoFrameApp extends StatelessWidget {
  const PhotoFrameApp({
    super.key,
    this.configuration,
    this.configurationWarning,
  });
  final GearConfiguration? configuration;
  final String? configurationWarning;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'EXIF Margin',
    debugShowCheckedModeBanner: false,
    // The personal Photo Frame edition keeps its existing theme.
    theme: kPublicTextOnly
        ? yamabukiAppTheme(Brightness.light)
        : ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff506456),
            ),
            scaffoldBackgroundColor: const Color(0xfff7f7f3),
          ),
    darkTheme: kPublicTextOnly ? yamabukiAppTheme(Brightness.dark) : null,
    themeMode: kPublicTextOnly ? ThemeMode.system : ThemeMode.light,
    home: FramePage(
      configuration: configuration,
      configurationWarning: configurationWarning,
    ),
  );
}

class FramePage extends StatefulWidget {
  const FramePage({super.key, this.configuration, this.configurationWarning});
  final GearConfiguration? configuration;
  final String? configurationWarning;
  @override
  State<FramePage> createState() => _FramePageState();
}

class _FramePageState extends State<FramePage> {
  GearConfiguration? _configuration;
  EditorPreferences? _preferences;
  late final Future<void> _preferencesReady;
  bool _preferencesWritable = true;
  FrameMargins _margins = editorDefaultMargins;
  CaptionSizes _sizes = const CaptionSizes();
  FrameGeometry? get _geometry => _photo == null
      ? null
      : FrameGeometry.forPhoto(
          _photo!.geometry.photoWidth,
          _photo!.geometry.photoHeight,
          margins: _margins,
        );

  Uint8List? _workingPixels, _captionPreview, _icc, _originalBytes;
  PreparedPhoto? _photo;
  PhotoMetadata? _metadata, _baseMetadata, _originalMetadata;
  bool _useDisplayNames = true;
  String? _sourcePath, _name;
  String _status = '';
  bool _busy = false,
      _dragging = false,
      _showMetadata = true,
      _showLogos = true,
      _captionPending = false;
  LogoStore? _logos;
  Timer? _editTimer;
  int _revision = 0;
  final _fields = <String, TextEditingController>{
    for (final key in editableMetadataFieldLabels.keys)
      key: TextEditingController(),
  };
  DisplaySettings get _settings =>
      _sizes.applyTo(_configuration?.settings ?? const DisplaySettings());
  @override
  void initState() {
    super.initState();
    _configuration = widget.configuration;
    if (_configuration != null) {
      _preferences = EditorPreferences(
        File(p.join(_configuration!.folder.path, 'mac-preferences.json')),
      );
    }
    _preferencesReady = _loadPreferences();
    if (_configuration != null) {
      _logos = LogoStore(
        Directory(p.join(_configuration!.folder.path, 'logos')),
      );
    }
  }

  Future<void> _loadPreferences() async {
    try {
      await _preferences?.load();
      if (mounted) {
        setState(() {
          _margins = _preferences?.margins ?? editorDefaultMargins;
          _sizes = _preferences?.sizes ?? const CaptionSizes();
        });
      }
    } catch (_) {
      _preferencesWritable = false;
      _message('記憶した設定を読み込めません。設定ファイルを確認してください。元のファイルは保持します。');
    }
  }

  Future<void> _rememberNames() async {
    if (_busy ||
        _originalMetadata == null ||
        _preferences == null ||
        !_useDisplayNames) {
      return;
    }
    setState(() => _busy = true);
    try {
      if (!_preferencesWritable) throw const FormatException();
      _preferences!.remember(_originalMetadata!, _metadata!);
      await _preferences!.save();
      _message('このカメラ・レンズの名前を記憶しました。同じ機材の写真で再利用します。');
    } catch (_) {
      _message('機材名を記憶できませんでした。設定フォルダを確認してください。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _adjustSizes() async {
    if (_busy || _captionPending) return;
    await _preferencesReady;
    if (!mounted) return;
    final chosen = await showDialog<CaptionSizes>(
      context: context,
      builder: (_) => SizeDialog(sizes: _sizes),
    );
    if (chosen == null || !mounted) return;
    final previous = _sizes;
    setState(() {
      _busy = true;
      _sizes = chosen;
    });
    try {
      final caption = _photo == null
          ? null
          : await _draw(_metadata!, _geometry!, maxWidth: 1600);
      if (!mounted) return;
      if (!_preferencesWritable) throw const FormatException();
      if (_preferences != null) {
        _preferences!.sizes = chosen;
        await _preferences!.save();
      }
      if (!mounted) return;
      setState(() => _captionPreview = caption);
      _message('文字・ロゴのサイズを変更しました。次回も同じサイズを使います。');
    } catch (_) {
      _preferences?.sizes = previous;
      if (mounted) setState(() => _sizes = previous);
      _message('サイズを変更できませんでした。設定フォルダを確認してください。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _adjustMargins() async {
    if (_busy || _captionPending) return;
    await _preferencesReady;
    if (!mounted) return;
    final chosen = await showDialog<FrameMargins>(
      context: context,
      builder: (_) => MarginDialog(margins: _margins),
    );
    if (chosen == null || !mounted) return;
    final previous = _margins;
    setState(() {
      _busy = true;
      _margins = chosen;
    });
    try {
      final caption = _photo == null
          ? null
          : await _draw(_metadata!, _geometry!, maxWidth: 1600);
      if (!mounted) return;
      setState(() => _captionPreview = caption);
      if (!_preferencesWritable) throw const FormatException();
      if (_preferences != null) {
        _preferences!.margins = chosen;
        await _preferences!.save();
      }
      _message('余白を変更しました。次の写真にも同じ余白を使います。');
    } catch (_) {
      // Keep the last usable preview; a persistence failure does not change the source photo.
      if (mounted) {
        setState(() => _margins = previous);
        _preferences?.margins = previous;
        if (_photo != null) {
          _captionPreview = await _draw(_metadata!, _geometry!, maxWidth: 1600);
        }
      }
      _message('余白を変更できませんでした。設定フォルダを確認してください。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _editTimer?.cancel();
    _revision++;
    _logos?.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<Uint8List?> _draw(PhotoMetadata m, FrameGeometry g, {int? maxWidth}) =>
      renderCaption(
        m,
        g,
        maxWidth: maxWidth,
        settings: _settings,
        logoStore: _showLogos ? _logos : null,
      );
  void _message(String text) {
    if (mounted) setState(() => _status = text);
  }

  void _syncFields(PhotoMetadata m) {
    final values = metadataFields(m);
    for (final item in values.entries) {
      _fields[item.key]!.text = item.value;
    }
  }

  PhotoMetadata _edited() {
    final base = _baseMetadata!.withFocalLengthMode(_metadata!.focalLengthMode);
    return applyMetadataFields(base, {
      for (final entry in _fields.entries) entry.key: entry.value.text,
    });
  }

  void _editChanged() {
    if (_photo == null || _busy) return;
    _editTimer?.cancel();
    final revision = ++_revision;
    setState(() {
      _metadata = _edited();
      _captionPending = true;
    });
    _editTimer = Timer(const Duration(milliseconds: 350), () async {
      try {
        final caption = await _draw(_metadata!, _geometry!, maxWidth: 1600);
        if (!mounted || revision != _revision) return;
        setState(() {
          _captionPreview = caption;
          _captionPending = false;
          _status = '表示文字を更新しました。この写真だけに適用されます。';
        });
      } catch (_) {
        if (mounted && revision == _revision) {
          setState(() {
            _captionPending = false;
            _status = '文字を描画できませんでした。入力内容を確認してください。';
          });
        }
      }
    });
  }

  Future<void> _changeLogoDisplay(bool value) async {
    if (_busy || _captionPending) return;
    final previous = _showLogos;
    setState(() {
      _showLogos = value;
      _busy = true;
    });
    try {
      final caption = _metadata == null
          ? null
          : await _draw(_metadata!, _geometry!, maxWidth: 1600);
      if (!mounted) return;
      setState(() {
        _captionPreview = caption;
        _status = value ? '登録ロゴで表示します。' : '機材名を文字で表示します。';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _showLogos = previous;
          _status = '表示を切り替えられませんでした。';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeFocalLength(FocalLengthMode mode) async {
    if (_busy || _metadata == null) return;
    final original = _originalMetadata;
    var base = _baseMetadata!;
    if (mode == FocalLengthMode.equivalent && base.focalLength35 == null) {
      final value = await showDialog<double>(
        context: context,
        builder: (_) => const ManualFocalDialog(),
      );
      if (!mounted ||
          value == null ||
          _busy ||
          !identical(original, _originalMetadata)) {
        return;
      }
      base = base.copyWith(focalLength35: value);
    }

    _editTimer?.cancel();
    _revision++;
    final metadata = _edited()
        .copyWith(focalLength35: base.focalLength35)
        .withFocalLengthMode(mode);
    setState(() {
      _busy = true;
      _captionPending = true;
    });
    try {
      final caption = await _draw(metadata, _geometry!, maxWidth: 1600);
      if (!mounted) return;
      setState(() {
        _baseMetadata = base;
        _metadata = metadata;
        _fields['focal']!.text = metadata.focalText;
        _captionPreview = caption;
        _status = '';
      });
    } catch (_) {
      _message('焦点距離の表示を変更できませんでした。');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _captionPending = false;
        });
      }
    }
  }

  Future<void> _changeNameSource(bool useDisplayNames) async {
    if (_busy || _originalMetadata == null) return;
    final base = (_configuration?.dictionary ?? const GearDictionary())
        .resolve(_originalMetadata!, useDisplayNames: useDisplayNames)
        .copyWith(focalLength35: _baseMetadata?.focalLength35);
    final remembered = useDisplayNames
        ? (_preferences?.overrides(_originalMetadata!) ?? <String, String>{})
        : <String, String>{};
    final metadata = base
        .withFocalLengthMode(_metadata!.focalLengthMode)
        .withOverrides({
          ...({..._metadata!.overrides}
            ..remove('camera')
            ..remove('lens')
            ..remove('cameraMaker')
            ..remove('cameraModel')
            ..remove('lensMaker')
            ..remove('lensModel')),
          ...remembered,
        });
    setState(() => _busy = true);
    _editTimer?.cancel();
    _revision++;
    try {
      final caption = await _draw(metadata, _geometry!, maxWidth: 1600);
      if (!mounted) return;
      _syncFields(metadata);
      setState(() {
        _useDisplayNames = useDisplayNames;
        _baseMetadata = base;
        _metadata = metadata;
        _captionPreview = caption;
        _status = '機材名の表記を変更しました。この写真だけに適用されます。';
      });
    } catch (_) {
      _message('機材名の表記を変更できませんでした。');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _captionPending = false;
        });
      }
    }
  }

  Future<void> _resetEdits() async {
    if (_busy || _baseMetadata == null) return;
    final metadata = _baseMetadata!.withFocalLengthMode(
      _metadata!.focalLengthMode,
    );
    _syncFields(metadata);
    _editChanged();
  }

  static const _photoTypes = XTypeGroup(
    label: 'JPEG・PNG',
    extensions: ['jpg', 'jpeg', 'png'],
    uniformTypeIdentifiers: ['public.jpeg', 'public.png'],
  );
  Future<void> _choose() async {
    if (_busy) return;
    try {
      final file = await openFile(acceptedTypeGroups: [_photoTypes]);
      if (file != null) await _load(file);
    } catch (_) {
      _message('写真を選べませんでした。もう一度お試しください。');
    }
  }

  Future<void> _load(XFile file) async {
    if (_busy) return;
    if (![
      '.jpg',
      '.jpeg',
      '.png',
    ].contains(p.extension(file.name).toLowerCase())) {
      _message('JPEGまたはPNGを選んでください。');
      return;
    }
    _editTimer?.cancel();
    _revision++;
    setState(() {
      _busy = true;
      _captionPending = false;
      _status = '写真の向きと色を確認しています…';
    });
    try {
      await _preferencesReady;
      final original = await file.readAsBytes();
      final native = await NativePhoto.normalize(original);
      _message('プレビューを作成しています…');
      final prepared = await compute(
        preparePhoto,
        native.png,
      ).timeout(const Duration(seconds: 90));
      _message('撮影情報を配置しています…');
      final base = (_configuration?.dictionary ?? const GearDictionary())
          .resolve(native.metadata);
      final automatic = base.withFocalLengthMode(FocalLengthMode.automatic);
      final metadata = automatic
          .withFocalLengthMode(
            automatic.usesEquivalent
                ? FocalLengthMode.equivalent
                : FocalLengthMode.actual,
          )
          .withOverrides(_preferences?.overrides(native.metadata) ?? {});
      final geometry = FrameGeometry.forPhoto(
        prepared.geometry.photoWidth,
        prepared.geometry.photoHeight,
        margins: _margins,
      );
      final caption = await _draw(
        metadata,
        geometry,
        maxWidth: 1600,
      ).timeout(const Duration(seconds: 30));
      if (!mounted) return;
      _syncFields(metadata);
      setState(() {
        _originalBytes = original;
        _workingPixels = native.png;
        _icc = native.icc;
        _photo = prepared;
        _metadata = metadata;
        _baseMetadata = base;
        _originalMetadata = native.metadata;
        _useDisplayNames = true;
        _captionPreview = caption;
        _sourcePath = file.path;
        _name = file.name;
        _status = '';
      });
    } on PlatformException catch (error) {
      _message(error.message ?? '写真を読み込めませんでした。');
    } catch (_) {
      _message('写真を読み込めませんでした。別のJPEGまたはPNGをお試しください。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reloadConfiguration() async {
    if (_busy || _configuration == null) return;
    _editTimer?.cancel();
    _revision++;
    setState(() {
      _busy = true;
      _captionPending = false;
    });
    LogoStore? nextLogos;
    try {
      final next = await GearConfiguration.load(_configuration!.folder);
      nextLogos = LogoStore(Directory(p.join(next.folder.path, 'logos')));
      final base = _originalMetadata == null
          ? null
          : next.dictionary
                .resolve(_originalMetadata!, useDisplayNames: _useDisplayNames)
                .copyWith(focalLength35: _baseMetadata?.focalLength35);
      final metadata = base
          ?.withFocalLengthMode(_metadata!.focalLengthMode)
          .withOverrides(_edited().overrides);
      final caption = metadata == null
          ? null
          : await renderCaption(
              metadata,
              _geometry!,
              maxWidth: 1600,
              settings: _sizes.applyTo(next.settings),
              logoStore: _showLogos ? nextLogos : null,
            );
      if (!mounted) {
        nextLogos.dispose();
        return;
      }
      final previous = _logos;
      setState(() {
        _configuration = next;
        _logos = nextLogos;
        _baseMetadata = base;
        _metadata = metadata;
        _captionPreview = caption;
        _status = next.warning == null
            ? '設定を再読み込みしました。'
            : '設定を再読み込みしました。警告を確認してください。';
      });
      if (metadata != null) _syncFields(metadata);
      previous?.dispose();
    } catch (_) {
      nextLogos?.dispose();
      _message('設定を再読み込みできませんでした。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openConfiguration() async {
    if (_configuration == null) return;
    try {
      final result = await Process.run('/usr/bin/open', [
        _configuration!.folder.path,
      ]);
      if (result.exitCode != 0) _message('設定フォルダを開けませんでした。');
    } catch (_) {
      _message('設定フォルダを開けませんでした。');
    }
  }

  Future<void> _save(OutputMode mode) async {
    if (_busy || _captionPending || _photo == null) return;
    setState(() => _busy = true);
    try {
      final location = await getSaveLocation(
        initialDirectory: p.dirname(_sourcePath!),
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'JPEG',
            extensions: ['jpg', 'jpeg'],
            uniformTypeIdentifiers: ['public.jpeg'],
          ),
        ],
        suggestedName:
            '${p.basenameWithoutExtension(_name!)}_frame_${mode.name.toUpperCase()}.jpg',
        confirmButtonText: '保存',
      );
      if (location == null || !mounted) return;
      if (![
        '.jpg',
        '.jpeg',
      ].contains(p.extension(location.path).toLowerCase())) {
        _message('拡張子を .jpg または .jpeg にしてください。');
        return;
      }
      final state = await inspectDestination(_sourcePath!, location.path);
      if (!mounted) return;
      if (state.exists) {
        final replace = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('同名のファイルがあります'),
            content: Text('${p.basename(location.path)} を置き換えますか？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('置き換える'),
              ),
            ],
          ),
        );
        if (replace != true) return;
      }
      _message('${mode.name.toUpperCase()}画像を作成しています…');
      final caption = _showMetadata
          ? await _draw(_metadata!, _geometry!)
          : null;
      final bytes = await compute(
        renderExport,
        ExportRequest(
          _workingPixels!,
          iccProfile: _icc,
          caption: caption,
          mode: mode,
          margins: _margins,
        ),
      );
      final withExif = await NativePhoto.copyExifWithoutGps(
        _originalBytes!,
        standardizeJpegIcc(bytes, _icc!),
      );
      await saveJpegSafely(
        sourcePath: _sourcePath!,
        destination: location.path,
        bytes: withExif,
        approvedState: state,
      );
      _message('保存しました：${location.path}');
    } on SaveConflict catch (error) {
      _message(error.message);
    } on PlatformException catch (error) {
      _message(error.message ?? '撮影情報を保存できませんでした。');
    } catch (_) {
      _message('保存できませんでした。空き容量と保存先の権限を確認してください。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _preview() {
    final g = _geometry;
    return DropTarget(
      enable: !_busy,
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) async {
        setState(() => _dragging = false);
        if (details.files.length != 1) {
          _message('写真は1枚ずつドロップしてください。');
          return;
        }
        await _load(details.files.single);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _dragging
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
        ),
        child: g == null
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.photo_outlined, size: 48),
                    SizedBox(height: 18),
                    Text('ここに写真をドロップ', style: TextStyle(fontSize: 21)),
                    SizedBox(height: 8),
                    Text('JPEG・PNG ／ 写真は1枚ずつ'),
                  ],
                ),
              )
            : FittedBox(
                fit: BoxFit.contain,
                child: Container(
                  width: g.width.toDouble(),
                  height: g.height.toDouble(),
                  color: Colors.white,
                  child: Stack(
                    children: [
                      Positioned(
                        left: g.side.toDouble(),
                        top: g.top.toDouble(),
                        width: g.photoWidth.toDouble(),
                        height: g.photoHeight.toDouble(),
                        child: Image.memory(
                          _photo!.preview,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                      if (_showMetadata && _captionPreview != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: g.bottom.toDouble(),
                          child: Image.memory(
                            _captionPreview!,
                            fit: BoxFit.fill,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = _geometry;
    final dimensions = g == null ? null : outputDimensions(g, OutputMode.hq);
    final warning = [
      _configuration?.warning,
      widget.configurationWarning,
      ...?_logos?.warnings,
    ].whereType<String>().join('\n');
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: _busy ? null : _choose,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('写真を選ぶ'),
                  ),
                  const SizedBox(width: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('save_hq'),
                        onPressed: _busy || _captionPending || _photo == null
                            ? null
                            : () => _save(OutputMode.hq),
                        icon: const Icon(Icons.file_download_outlined),
                        label: const Text('元サイズで保存'),
                      ),
                      Tooltip(
                        message: '完成画像の長辺2048px以下で保存',
                        child: FilledButton.icon(
                          key: const ValueKey('save_sns'),
                          onPressed: _busy || _captionPending || _photo == null
                              ? null
                              : () => _save(OutputMode.sns),
                          icon: const Icon(Icons.file_download_outlined),
                          label: const Text('SNS用に保存'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24, child: VerticalDivider(width: 24)),
                  IconButton(
                    onPressed: _busy || _configuration == null
                        ? null
                        : _reloadConfiguration,
                    tooltip: '設定を再読み込み',
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    onPressed: _configuration == null
                        ? null
                        : _openConfiguration,
                    tooltip: '設定フォルダを開く',
                    icon: const Icon(Icons.folder_open_outlined),
                  ),
                  IconButton(
                    onPressed: () => showLicensePage(
                      context: context,
                      applicationName: 'EXIF Margin',
                    ),
                    tooltip: 'ライセンス',
                    icon: const Icon(Icons.info_outline),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (warning.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    warning,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _preview()),
                    const SizedBox(width: 24),
                    MacSettingsPanel(
                      metadata: _metadata,
                      fields: _fields,
                      margins: _margins,
                      sizes: _sizes,
                      busy: _busy,
                      captionPending: _captionPending,
                      showMetadata: _showMetadata,
                      showLogos: _showLogos,
                      useDisplayNames: _useDisplayNames,
                      canRememberNames: _preferences != null,
                      onMetadataChanged: (value) =>
                          setState(() => _showMetadata = value),
                      onLogoChanged: _changeLogoDisplay,
                      onNameSourceChanged: _changeNameSource,
                      onFocalChanged: _changeFocalLength,
                      onEditChanged: _editChanged,
                      onAdjustMargins: _adjustMargins,
                      onAdjustSizes: _adjustSizes,
                      onReset: _resetEdits,
                      onRemember: _rememberNames,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (g != null)
                Text(
                  '$_name  ·  ${g.photoWidth} × ${g.photoHeight} → ${dimensions!.width} × ${dimensions.height} px（元サイズ）',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              if (_busy || _captionPending) ...[
                const SizedBox(height: 6),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (_status.isNotEmpty) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
