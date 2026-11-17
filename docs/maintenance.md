# EXIF Margin：コード構成と保守方針

作業時の優先ルールは[AGENTS.md](../AGENTS.md)。古いUIコードや個人用機材データを復活させないこと。

公開用の文字表示版。個人用ロゴ対応版（EXIF Margin Logo）とは別管理にし、個人用の素材や設定を公開版へ混入させない。

## 主な構成

| 対象 | 変更先 |
| --- | --- |
| フレーム余白・画像描画・JPEG出力 | `lib/src/frame.dart` |
| EXIF表示値と文字・ロゴ配置 | `lib/src/photo_metadata.dart`／`caption.dart` |
| 編集できる8項目の共通ラベル・差分処理 | `lib/src/metadata_fields.dart` |
| 機材辞書、初期CSV | `lib/src/gear_dictionary.dart`／`assets/config/` |
| 設定の永続化、旧形式の読み込み | `lib/src/editor_preferences.dart` |
| Androidの写真読込・画面状態・保存 | `lib/src/android/android_frame_page.dart` |
| Androidの撮影情報入力欄 | `lib/src/android/android_caption_editor.dart` |
| Androidの表示設定 | `lib/src/android/android_settings_panel.dart` |
| macOSの画面状態・保存 | `lib/src/macos/mac_frame_page.dart` |
| macOSの表示設定 | `lib/src/macos/mac_settings_panel.dart` |
| Android固有のEXIF・保存処理 | `android/app/src/main/kotlin/` |
| macOS固有のEXIF・画像正規化 | `macos/Runner/` |

Androidの設定・入力Widgetは表示専用。状態・ファイル保存・写真の読み込みは親画面が担当する。両OSの共通演算は共有し、OS固有の操作は無理に共通化しない。

旧`mac_preferences.dart`／`android_preferences.dart`、各OS別の余白／サイズダイアログの薄い別名ファイル、`android/jpeg_profile.dart`は削除済み。テスト・新規コードは`editor_preferences.dart`、`caption_sizes.dart`、`margin_dialog.dart`、`size_dialog.dart`、`jpeg_profile.dart`を直接参照する。過去ブランチから互換入口をコピーして戻さない。

公開用は`kPublicTextOnly = true`。ロゴ表示を使用せず、個人用の初期機材CSVや画像ロゴを同梱しない。既存の`photo_frame`、`local.photoframe`は内部のFlutter/Kotlin/MethodChannel識別子で、公開アプリIDは`net.tameha.exifmargin`。内部名の機械的な変更は行わない。

## 2リポジトリのコード差分を扱う方針（2026-11-13照合）

現在の保守用ブランチを照合したところ、同じ相対パスのDartファイル48件のうち**30件がGit blob SHAまで一致**し、**18件は異なる実装・テスト**でした。共通ファイルが多くても、片方のフォルダを一括コピー・同期しないでください。

- **共通維持が望ましい実装**：`caption.dart`、`photo_metadata.dart`、`caption_sizes.dart`、`display_settings.dart`、`metadata_fields.dart`、`android/android_caption_editor.dart`、`android/android_settings_panel.dart`、`safe_save.dart`、`jpeg_profile.dart`など。変更する場合は両リポジトリで必要性を評価し、各々テストする。
- **絶対に同一化しない相違**：`frame.dart`のJPEG色差形式（公開版**4:2:0**、Logo版**4:4:4**）、`public_edition.dart`の公開フラグ（公開版true／Logo版false）、公開版の空の機材辞書とLogo版の個人機材CSV、両版のアプリID／表示名／保存場所。
- **Logo版固有**：`android/edit_session.dart`や`editor_preferences.dart`に含む特定機種向け35mm換算焦点距離の補完、個人用ロゴ表示／設定。公開版へ無断移植しない。
- **OS・画面差分**：`android/android_frame_page.dart`、`macos/mac_frame_page.dart`、`macos/mac_settings_panel.dart`は版ごとの違いを保持する。共通化する場合は小さいWidget・演算部分だけに限定する。
- **回帰テスト**：公開版の`test/public_edition_test.dart`は文字表示版フラグとロゴ非表示、初期辞書の空状態を検証する。公開版の`test/android_export_quality_test.dart`はHQ/SNSともJPEG SOFの**4:2:0**を検証する。Logo版の**4:4:4**は別リポジトリのテストで確認する。版別の期待値を同じものに書き換えない。

以上の照合件数は2026-11-13のスナップショット基準であり、今後の変更で増減する。将来は必要時に両ブランチの同一相対パスを比較し、**共通にすべき差分と意図的な差分を確認してから**一方の修正をもう一方へ適用する。

## 先祖返りしやすい互換経路

- 公開版のMac／Androidの保存処理は`renderExport()`を使用し、HQ品質95／SNS品質90・双方4:2:0とする。`frame.dart`の`renderJpeg()`は旧来の簡易画像処理／テスト用の別関数で品質98・4:4:4のまま残る。**保存処理を`renderJpeg()`へ切り替えない**。削除する場合は呼び出し元テストを先に整理し、書き出し回帰を実行する。
- 公開版でも`logo_store.dart`と`flutter_svg`は現在のコードから参照される。公開用にロゴ画像を同梱しない方針と、実装の依存関係を削除してよいかは別問題。一括削除はしない。
- 空の初期辞書には2つの入口がある。Macの初回生成用`GearConfiguration.cameraSample`／`lensSample`と、Androidに同梱する`assets/config/cameras.csv`／`lenses.csv`は**ヘッダー列の数が現時点では異なる**（Macはカメラ9列／レンズ4列、同梱CSVはカメラ13列／レンズ5列）。いずれもヘッダーのみで、パーサーは任意列を許容する。今後どちらかの初期辞書に登録行や個人情報を戻さない。両入口の空状態を`test/public_edition_test.dart`で確認する。列の統一は既存辞書互換性を確認してから別途判断する。
- ビルド番号は`pubspec.yaml`の既定値と、ビルド時指定・最終APK/ZIP表示を混同しない。初回公開時は両OSの候補をそれぞれソースコミット、実際のビルド番号、署名、SHA-256で照合する。

## SDK・依存関係の整合

- `pubspec.lock`の実際の解決条件は**Dart 3.13.0以上・Flutter 3.47.0以上**。従来の`pubspec.yaml`は下限が古く、宣言とロックが食い違っていたため、両方の宣言をロックに合わせた。依存パッケージのバージョンは変更していない。
- Macで作業する際は先に`flutter --version`を確認する。SDKが下限未満の場合、テストを強行したり依存バージョンを無断で下げず、作業環境を確認してから対応する。
- 直接利用する`desktop_drop`・`file_selector`・`image`・`path`・`archive`・`csv`・`flutter_svg`は現行Dartのimportがある。特にSVG描画コードは公開版でも残るため、画像ロゴ非同梱を理由に依存を削除しない。
- ライセンスは公開版のMIT、同梱するShare Tech / Share Tech MonoのOFL文書、依存パッケージのNOTICE等を最終配布物の内容と照合する。

## macOSの標準ダイアログ言語（2026-11-15追加）

- Macの保存パネルで「Replace / Cancel」などが英語だった事例に対応し、`macos/Runner/Info.plist`の`CFBundleLocalizations`に`ja`と`en`を宣言した。従来のXcode開発言語`en`と`Base.lproj`は維持し、保存ロジック・署名・アプリIDは変更しない。
- `test/macos_localization_test.dart`はローカライズ宣言の先祖返りを防ぐ静的回帰テスト。**macOS build24では標準保存パネル・同名保存警告が日本語で表示されることを実画面で確認済み**。キャンセル後の既存ファイルのハッシュ不変も確認した。
- 2026-11-15に`plutil -lint`、Flutterのローカライズテスト、`flutter analyze`に合格。macOS build24のBundle ID、署名、ZIP展開と画面操作を確認した。新たなmacOS配布候補を作る場合だけ、組み込まれた`Contents/Info.plist`と日本語表示を再照合する。
- 旧build23はロールバック用に保持し、検証済みの新版build24を候補として管理する。新しい候補ごとにSHA-256とソースコミットを明記する。日本語化のために独自保存ダイアログやシステム全体のセキュリティ変更は不要。

## 公開用スナップショットと配布物の対応

- 初回公開用の独立Git履歴は、直前の検証済みソースから**公開してよいファイルだけ**を登録する。旧Private開発リポジトリの`.git/`、内部Release下書き`docs/release-v0.1.0-draft.md`、個人用ロゴ・写真・機材辞書、鍵・パスワード、ローカルパスを持ち込まない。Privateリポジトリの`main`から再生成しない。
- `android/.gitignore`はFlutterテンプレート由来で`gradlew`・`gradlew.bat`・`gradle-wrapper.jar`を除外する。**2026-11-17の公開候補v4ではこれら3ファイルを明示的にGit登録した**。次の独立スナップショット作成時も`git ls-files`で3件が追跡されていることを確認する。通常の`git add -A`だけでは脱落し得るため、Gradle wrapperの不要削除と誤判定しない。
- 公開直前の`README.md`と`AGENTS.md`を最終ソースに合わせる。内部Release下書きは**本文を手動転記するための資料**であり、公開ソースには入れない。公開用Gitの`main`と`v0.1.0`タグが同じ初期ソースに対応することを確認する。
- 配布APKとMac ZIPは、ソースGitコミット・アプリの実バージョン／ビルド番号・署名方式／証明書・バイト長・SHA-256を各ファイルごとに記録する。Flutterの`pubspec.yaml`内の既定ビルド番号が実配布候補と異なる場合、明示したビルド時指定の記録を残す。記録不明の過去APK/ZIPについて、厳密に再現一致したと断定しない。
- macOSはDeveloper ID署名・公証なしのad-hoc ZIP、Androidは専用release鍵で署名したAPKをGitHub Releasesのみで配布。Play審査・AAB・独自更新基盤は不要。最終ZIPのダウンロード後Gatekeeper初回起動と、APKの更新時署名互換性を確認する。ユーザー設定・既存写真を変更しない。

## 最小のローカル確認

```sh
dart format lib test
flutter analyze
flutter test test/android_caption_editor_test.dart test/android_settings_panel_test.dart
flutter test test/android_keyboard_test.dart test/android_configuration_test.dart
flutter test test/spec_layout_test.dart test/safe_save_test.dart
```

フレーム・Exif・JPEG処理を変更した場合は関連テストと実写真でのMac／Android保存を確認。アプリID、署名鍵、出力品質、設定ファイル形式は別の指示がない限り変更しない。GitHub Actionsは原則実行しない。

2026-11-15にmacOS build24の主要動作と日本語保存パネルを確認した。初回公開時は最終ソースと配布APK／ZIPの対応、アイコン原本の利用権、Gatekeeperのダウンロード後の初回起動を確認する。公開前の一時スナップショットのローカルパスと非公開Git履歴は公開リポジトリに引き継がない。履歴改変やリポジトリPublic化、Releaseは本人の明示承認まで実施しない。
