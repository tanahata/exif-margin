import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../caption.dart';
import '../public_edition.dart';
import '../frame.dart';
import '../gear_dictionary.dart';
import '../logo_store.dart';
import '../photo_metadata.dart';
import '../metadata_fields.dart';
import 'android_caption_editor.dart';
import 'android_settings_panel.dart';
import 'android_platform.dart';
import 'configuration_import.dart';
import 'edit_session.dart';
import '../jpeg_profile.dart';
import '../editor_preferences.dart';
import '../margin_dialog.dart';
import '../size_dialog.dart';
import '../display_settings.dart';
import '../manual_focal_dialog.dart';

PreparedPhoto prepareAndroidPhoto(String path) =>
    preparePhoto(File(path).readAsBytesSync());

String exportAndroidPhoto(
  (String, String, Uint8List?, OutputMode, Uint8List, FrameMargins) request,
) {
  final (source, output, caption, mode, icc, margins) = request;
  final bytes = renderExport(
    ExportRequest(
      File(source).readAsBytesSync(),
      caption: caption,
      mode: mode,
      iccProfile: icc,
      margins: margins,
    ),
  );
  File(output).writeAsBytesSync(standardizeJpegIcc(bytes, icc), flush: true);
  return output;
}

class AndroidFramePage extends StatefulWidget {
  const AndroidFramePage({super.key, this.platform});
  final AndroidPlatform? platform;
  @override
  State<AndroidFramePage> createState() => _AndroidFramePageState();
}

class _AndroidFramePageState extends State<AndroidFramePage>
    with WidgetsBindingObserver {
  late final AndroidPlatform _platform = widget.platform ?? AndroidPlatform();
  final _session = EditSession();
  final _fields = <String, TextEditingController>{
    for (final key in editableMetadataFieldLabels.keys)
      key: TextEditingController(),
  };
  GearConfiguration? _config;
  ConfigurationRepository? _repository;
  LogoStore? _logos;
  PreparedPhoto? _photo;
  File? _pixels, _original;
  EditorPreferences? _preferences;
  bool _preferencesLoaded = false;
  FrameMargins get _margins => _preferences?.margins ?? editorDefaultMargins;
  DisplaySettings get _display =>
      (_preferences?.sizes ?? const CaptionSizes()).applyTo(_config!.settings);
  FrameGeometry _geometry(PreparedPhoto photo) => FrameGeometry.forPhoto(
    photo.geometry.photoWidth,
    photo.geometry.photoHeight,
    margins: _margins,
  );
  void _remembered(EditSession session) {
    if (session.original != null && session.useDisplayNames) {
      session.metadata = session.metadata!.withOverrides({
        ...?_preferences?.overrides(session.original!),
        ...session.metadata!.overrides,
      });
    }
  }

  Uint8List? _icc, _caption;
  String? _cache, _name, _savedUri;
  String _status = '';
  bool _busy = true,
      _captionPending = false,
      _draining = false,
      _incomingAgain = false;
  Timer? _editTimer;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AndroidPlatform.channel.setMethodCallHandler((call) async {
      if (call.method == 'incoming') {
        _incomingAgain = true;
        unawaited(_drainIncoming());
      }
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final paths = await _platform.paths();
      _cache = paths['cache']!;
      _repository = ConfigurationRepository(
        Directory(p.join(paths['files']!, 'configuration')),
      );
      _config = await _repository!.initialize();
      _preferences = EditorPreferences(
        File(p.join(paths['files']!, 'android-preferences.json')),
      );
      await _preferences!.load();
      _session.mode = _preferences!.outputMode;
      _preferencesLoaded = true;
      _logos = LogoStore(Directory(p.join(_config!.folder.path, 'logos')));
      // Only expired files from previous sessions are removed; never current shares.
      final cutoff = DateTime.now().subtract(const Duration(days: 1));
      for (final directory in ['imports', 'exports']) {
        final folder = Directory(p.join(_cache!, directory));
        await folder.create(recursive: true);
        await for (final file in folder.list()) {
          if (file is File && (await file.stat()).modified.isBefore(cutoff)) {
            await file.delete();
          }
        }
      }
    } catch (error) {
      _status = '設定を準備できませんでした。${_error(error)}';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    unawaited(_drainIncoming());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_drainIncoming());
  }

  Future<void> _drainIncoming() async {
    if (_busy || _draining || !mounted || _config == null) return;
    _draining = true;
    _incomingAgain = false;
    try {
      while (mounted && !_busy) {
        final item = await _platform.nextIncoming();
        if (item == null || !mounted) break;
        if (item['error'] != null) {
          setState(() => _status = item['error'] as String);
          continue;
        }
        final file = ImportedFile.fromMap(item);
        if (item['kind'] == 'zip') {
          await _perform(() => _importConfiguration(file));
        } else {
          await _perform(() => _load(file));
        }
      }
    } catch (error) {
      if (mounted) setState(() => _status = _error(error));
    } finally {
      _draining = false;
      if (_incomingAgain && mounted && !_busy) unawaited(_drainIncoming());
    }
  }

  String _error(Object error) => error is PlatformException
      ? error.message ?? '操作を完了できませんでした。'
      : error is FormatException
      ? error.message
      : '処理できませんでした。空き容量を確認して再度お試しください。';

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy || !mounted) return;
    final pendingEdit = _captionPending;
    _editTimer?.cancel();
    ++_revision;
    setState(() {
      _busy = true;
      _captionPending = false;
    });
    try {
      if (pendingEdit) _caption = await _draw();
      await action();
    } catch (error) {
      if (mounted) setState(() => _status = _error(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        unawaited(_drainIncoming());
      }
    }
  }

  void _syncFields() {
    if (_session.metadata == null) return;
    for (final entry in EditSession.fields(_session.metadata!).entries) {
      _fields[entry.key]!.text = entry.value;
    }
  }

  Future<Uint8List?> _draw({int? maxWidth = 1600}) async {
    if (_photo == null || _session.metadata == null || !_session.showMetadata) {
      return null;
    }
    return renderCaption(
      _session.metadata!,
      _geometry(_photo!),
      maxWidth: maxWidth,
      settings: _display,
      logoStore: _session.showLogos ? _logos : null,
    );
  }

  Future<void> _load(ImportedFile source) async {
    if (_config == null) return;
    setState(() => _status = '写真の向き・色・撮影情報を読み込んでいます…');
    File? normalized;
    try {
      final native = await _platform.normalize(source.path);
      normalized = native.file;
      final prepared = await compute(prepareAndroidPhoto, native.file.path);
      if (!mounted) {
        await native.file.delete();
        return;
      }
      // Prepare caption before replacing the active photo, so a failed load preserves editing.
      final candidate = EditSession()
        ..showMetadata = _session.showMetadata
        ..showLogos = _session.showLogos
        ..useDisplayNames = _session.useDisplayNames
        ..focalPreference = _session.focalPreference;
      candidate.load(native.metadata, _config!.dictionary);
      _remembered(candidate);
      final caption = _session.showMetadata
          ? await renderCaption(
              candidate.metadata!,
              _geometry(prepared),
              maxWidth: 1600,
              settings: _display,
              logoStore: _session.showLogos ? _logos : null,
            )
          : null;
      if (!mounted) {
        await native.file.delete();
        return;
      }
      final previous = _pixels;
      final previousOriginal = _original;
      setState(() {
        _photo = prepared;
        _pixels = native.file;
        _original = File(source.path);
        _icc = native.icc;
        _session.load(native.metadata, _config!.dictionary);
        _remembered(_session);
        _caption = caption;
        _name = source.name;
        _savedUri = null;
        _status = '';
      });
      normalized = null;
      _syncFields();
      if (previous != null && await previous.exists()) await previous.delete();
      if (previousOriginal != null && await previousOriginal.exists()) {
        await previousOriginal.delete();
      }
    } finally {
      if (normalized != null && await normalized.exists()) {
        await normalized.delete();
      }
      if (_original?.path != source.path && await File(source.path).exists()) {
        await File(source.path).delete();
      }
    }
  }

  Future<void> _choose() => _perform(() async {
    final source = await _platform.pickPhoto();
    if (source != null) await _load(source);
  });

  void _editChanged() {
    if (_busy || _photo == null) return;
    _session.edit({
      for (final item in _fields.entries) item.key: item.value.text,
    });
    _editTimer?.cancel();
    final revision = ++_revision;
    setState(() => _captionPending = true);
    _editTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final caption = await _draw();
        if (mounted && revision == _revision) {
          setState(() {
            _caption = caption;
            _captionPending = false;
          });
        }
      } catch (error) {
        if (mounted && revision == _revision) {
          setState(() {
            _captionPending = false;
            _status = _error(error);
          });
        }
      }
    });
  }

  Future<void> _change(FutureOr<void> Function() change) => _perform(() async {
    await change();
    final caption = await _draw();
    if (mounted) setState(() => _caption = caption);
  });

  Future<void> _setOutputMode(OutputMode mode) => _perform(() async {
    final preferences = _preferences;
    if (preferences == null || !_preferencesLoaded || _session.mode == mode) {
      return;
    }
    final previous = _session.mode;
    _session.mode = mode;
    preferences.outputMode = mode;
    try {
      await preferences.save();
    } catch (_) {
      _session.mode = previous;
      preferences.outputMode = previous;
      throw const FormatException('保存サイズを記憶できませんでした。');
    }
  });

  Future<void> _export(bool share) => _perform(() async {
    if (_pixels == null || _photo == null || _cache == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _status = '完成JPEGを生成しています…');
    final output = await File(
      p.join(
        _cache!,
        'exports',
        'export-${DateTime.now().microsecondsSinceEpoch}.jpg',
      ),
    ).create();
    try {
      final caption = await _draw(maxWidth: null);
      await compute(exportAndroidPhoto, (
        _pixels!.path,
        output.path,
        caption,
        _session.mode,
        _icc!,
        _margins,
      ));
      await _platform.copyExif(_original!, output);
      final name =
          '${p.basenameWithoutExtension(_name ?? 'photo')}_frame_${_session.mode.name.toUpperCase()}.jpg';
      if (share) {
        await _platform.share(output, name);
        if (mounted) setState(() => _status = '共有シートを開きました。');
      } else {
        final saved = await _platform.save(output, name);
        if (mounted) {
          setState(() {
            _savedUri = saved['uri'];
            _status = '保存しました：${saved['name']}';
          });
        }
      }
    } finally {
      if (await output.exists()) await output.delete();
    }
  });

  Future<void> _importConfiguration(ImportedFile source) async {
    GearConfiguration? staged;
    LogoStore? nextLogos;
    try {
      final next = await _repository!.prepareZip(File(source.path));
      staged = next;
      nextLogos = LogoStore(Directory(p.join(next.folder.path, 'logos')));
      final candidate = EditSession()
        ..useDisplayNames = _session.useDisplayNames
        ..focalPreference = _session.focalPreference
        ..manualEquivalent = _session.manualEquivalent
        ..original = _session.original
        ..metadata = _session.metadata;
      candidate.resolve(next.dictionary);
      final caption =
          _photo == null || candidate.metadata == null || !_session.showMetadata
          ? null
          : await renderCaption(
              candidate.metadata!,
              _geometry(_photo!),
              maxWidth: 1600,
              settings: _preferences!.sizes.applyTo(next.settings),
              logoStore: _session.showLogos ? nextLogos : null,
            );
      if (!mounted) return;
      await _repository!.activate(next);
      staged = null;
      final previous = _logos;
      _config = next;
      _logos = nextLogos;
      nextLogos = null;
      _session.resolve(next.dictionary);
      if (mounted) {
        setState(() {
          _caption = caption;
          _status = '設定一式を取り込みました。';
        });
      }
      _syncFields();
      previous?.dispose();
      // Cleanup failure does not turn a successful atomic import into an error.
      try {
        await _repository!.cleanOldGenerations(next.folder);
      } on FileSystemException {
        /* Retry at a later import. */
      }
    } finally {
      nextLogos?.dispose();
      if (staged != null && await staged.folder.exists()) {
        await staged.folder.delete(recursive: true);
      }
      if (await File(source.path).exists()) await File(source.path).delete();
    }
  }

  Future<void> _chooseZip() => _perform(() async {
    final source = await _platform.pickZip();
    if (source != null) await _importConfiguration(source);
  });

  Widget _preview() {
    final photo = _photo;
    if (photo == null) return const SizedBox.shrink();
    final g = _geometry(photo);
    return Container(
      height: math.min(MediaQuery.sizeOf(context).height * .44, 400),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kPublicTextOnly
            ? Theme.of(context).colorScheme.surfaceContainerHigh
            : const Color(0xffe9e9e3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: FittedBox(
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
                  photo.preview,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                ),
              ),
              if (_session.showMetadata && _caption != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: g.bottom.toDouble(),
                  child: Image.memory(
                    _caption!,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settings() => AndroidSettingsPanel(
    busy: _busy,
    hasConfiguration: _config != null,
    hasPreferences: _preferences != null,
    hasPhoto: _photo != null,
    showLogoOption: !kPublicTextOnly,
    showMetadata: _session.showMetadata,
    showLogos: _session.showLogos,
    useDisplayNames: _session.useDisplayNames,
    focalLengthMode: _session.metadata == null
        ? FocalLengthMode.actual
        : (_session.metadata!.usesEquivalent
              ? FocalLengthMode.equivalent
              : FocalLengthMode.actual),
    margins: _margins,
    sizes: _preferences?.sizes ?? const CaptionSizes(),
    onMetadataChanged: (value) => _change(() => _session.showMetadata = value),
    onLogosChanged: (value) => _change(() => _session.showLogos = value),
    onNameSourceChanged: (value) => _change(() {
      _session.useDisplayNames = value;
      _session.resolve(_config!.dictionary, preserveEdits: false);
      _remembered(_session);
      _syncFields();
    }),
    onFocalChanged: (value) => _change(() async {
      final metadata = _session.metadata;
      if (metadata == null) return;
      if (value == FocalLengthMode.equivalent &&
          metadata.focalLength35 == null) {
        final equivalent = await showDialog<double>(
          context: context,
          builder: (_) => const ManualFocalDialog(),
        );
        if (equivalent == null || !mounted) return;
        _session.setEquivalent(equivalent, _config!.dictionary);
      } else {
        _session.focalPreference = value;
        final edits = {...metadata.overrides}..remove('focal');
        _session.resolve(_config!.dictionary);
        _session.metadata = _session.base?.withOverrides(edits);
      }
      _syncFields();
    }),
    onAdjustMargins: () async {
      final value = await showDialog<FrameMargins>(
        context: context,
        builder: (_) => MarginDialog(margins: _margins),
      );
      if (value != null && mounted) {
        await _change(() async {
          _preferences!.margins = value;
          await _preferences!.save();
        });
      }
    },
    onAdjustSizes: () async {
      final value = await showDialog<CaptionSizes>(
        context: context,
        builder: (_) => SizeDialog(sizes: _preferences!.sizes),
      );
      if (value != null && mounted) {
        await _change(() async {
          _preferences!.sizes = value;
          await _preferences!.save();
        });
      }
    },
  );

  Widget _exportSize() => Semantics(
    label: '保存サイズ',
    child: _outlinedDropdown(
      horizontalPadding: 8,
      child: DropdownButton<OutputMode>(
        style: Theme.of(context).textTheme.bodyMedium,
        itemHeight: null,
        value: _session.mode,
        isExpanded: true,
        menuWidth: math.min(250, MediaQuery.sizeOf(context).width - 32),
        selectedItemBuilder: (_) => [
          for (final label in ['元サイズ', 'SNS用'])
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Align(alignment: Alignment.centerLeft, child: Text(label)),
            ),
        ],
        items: const [
          DropdownMenuItem(value: OutputMode.hq, child: Text('元サイズ')),
          DropdownMenuItem(
            value: OutputMode.sns,
            child: Text('SNS用（長辺2048px以下）'),
          ),
        ],
        onChanged: _busy || !_preferencesLoaded
            ? null
            : (mode) {
                if (mode != null) unawaited(_setOutputMode(mode));
              },
      ),
    ),
  );

  Widget _exportControls(bool ready) => LayoutBuilder(
    builder: (context, constraints) {
      final size = _exportSize();
      final share = OutlinedButton(
        onPressed: ready ? () => _export(true) : null,
        child: const Text('共有'),
      );
      final save = FilledButton(
        onPressed: ready ? () => _export(false) : null,
        child: const Text('JPEG保存', textAlign: TextAlign.center),
      );
      final stackSize =
          constraints.maxWidth < 310 || _largeSettingText(context);
      final actions = Row(
        children: [
          if (!stackSize) ...[
            Expanded(flex: 3, child: size),
            const SizedBox(width: 8),
          ],
          Expanded(flex: 2, child: share),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: save),
        ],
      );
      if (!stackSize) return actions;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [size, const SizedBox(height: 4), actions],
      );
    },
  );

  bool _largeSettingText(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(14) > 18;

  Widget _outlinedDropdown({
    required Widget child,
    double horizontalPadding = 12,
  }) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outline),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: DropdownButtonHideUnderline(child: child),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ready = !_busy && !_captionPending && _photo != null;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('EXIF Margin'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'import') {
                unawaited(_chooseZip());
              } else {
                showLicensePage(
                  context: context,
                  applicationName: 'EXIF Margin',
                );
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'import',
                enabled: !_busy && _repository != null,
                child: const Text('設定を取り込む'),
              ),
              const PopupMenuItem(value: 'license', child: Text('ライセンス')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            if (_photo == null)
              FilledButton.tonalIcon(
                onPressed: _busy || _config == null ? null : _choose,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('写真を選択'),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy || _config == null ? null : _choose,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('別の写真を選ぶ'),
                ),
              ),
            const SizedBox(height: 12),
            _preview(),
            const SizedBox(height: 8),
            // Keep this list child in place while editing. Inserting a new
            // sibling here would recreate the unkeyed field wrappers below and
            // dispose the focused EditableText after the first keystroke.
            SizedBox(
              height: 4,
              child: _busy || _captionPending
                  ? const LinearProgressIndicator()
                  : null,
            ),
            Semantics(
              liveRegion: true,
              child: _status.isEmpty
                  ? const SizedBox.shrink()
                  : Text(_status, key: const ValueKey('android_status')),
            ),
            if (_savedUri != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () => _perform(() => _platform.open(_savedUri!)),
                  child: const Text('画像を開く'),
                ),
              ),
            if (_photo != null)
              Text(
                '${_photo!.geometry.photoWidth} × ${_photo!.geometry.photoHeight} px',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 20),
            _settings(),
            const SizedBox(height: 20),
            AndroidCaptionEditor(
              fields: _fields,
              busy: _busy,
              hasPhoto: _photo != null,
              useDisplayNames: _session.useDisplayNames,
              onEditChanged: _editChanged,
              onReset: () => _change(() {
                _session.resetEdits();
                _syncFields();
              }),
              onRemember: () => _change(() async {
                _preferences!.remember(_session.original!, _session.metadata!);
                await _preferences!.save();
                _status = '機材名を記憶しました。';
              }),
            ),
          ],
        ),
      ),
      bottomNavigationBar: keyboard
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: _exportControls(ready),
              ),
            ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AndroidPlatform.channel.setMethodCallHandler(null);
    _editTimer?.cancel();
    ++_revision;
    _logos?.dispose();
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }
}
