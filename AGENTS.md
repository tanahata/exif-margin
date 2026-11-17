# EXIF Margin — Codex作業ルール（公開用）

## 正本・優先順位

- 本リポジトリ`tanahata/exif-margin`はロゴ画像なしの**公開用EXIF Margin**。**初回公開前は開発リポジトリの`main`が旧版のことがあるため、`main`を無条件に正本としない**。作業開始時に実ブランチ・HEAD・未コミット変更・検証済みの最新ブランチとの差分を確認する。初回公開後は、履歴を整理した公開リポジトリの`main`とReleaseタグを正本とする。非公開の開発用PRは公開リポジトリに引き継がない。
- 個人用ロゴ版**EXIF Margin Logo**は別管理。個人用のメーカーCSV・SVG・ロゴ・署名・設定・アイコンを本リポジトリに取り込まない。
- 利用者向け仕様は[README.md](README.md)、現行コードの責務分離は[docs/maintenance.md](docs/maintenance.md)。リリース文章の下書きは**作業手順の正本ではない**。過去PR、旧設計案、古い引継ぎ内容より現在の実装・テストを優先し、古いコードを復元しない。

## 守る仕様（先祖返り禁止）

- 初期の機材辞書は**空**。公開用`assets/config/cameras.csv`と`lenses.csv`のヘッダーだけを維持し、個人用カメラ・レンズの登録行を戻さない。既存端末の機材記憶・設定を勝手に削除・上書きしない。
- JPEG/PNG入力、写真の非破壊編集。余白は短辺基準で左右各**2%**・上**7%**・下**20%**。HQ JPEG品質95／SNS品質90、両方**4:2:0**、SNS完成画像の長辺2048px以下。標準撮影EXIFは保持し、GPS・MakerNote・XMP・元サムネイルを除外する。
- `kPublicTextOnly=true`で撮影情報は文字表示のみ。非公開版のロゴ表示UIやメーカーSVGを復活させない。表示名は**EXIF Margin**、公開アプリID/Bundle IDは`net.tameha.exifmargin`。
- Mac/Androidの編集8項目は`lib/src/metadata_fields.dart`の共通ラベルとキーを使う。Androidの入力UIは`lib/src/android/android_caption_editor.dart`、設定UIは`lib/src/android/android_settings_panel.dart`が担当する。親`android_frame_page.dart`はコントローラー・非同期処理・保存を担当する。分離したUI部品を親画面に貼り戻さない。
- 既存のDart package`photo_frame`、Kotlin/MethodChannel`local.photoframe`は内部識別子であり、公開アプリIDではない。名称整理を理由に一括変更してビルドを壊さない。

## 作業と検証

- 小さな差分と既存ライブラリを優先。無用の状態管理層・互換コード・新しいUI画面を増やさない。旧PRや別版のファイルを丸ごとコピーしない。版別の契約・入出力・機材辞書・画像形式を現行テストと照合してから最小差分だけ取り込む。
- Macローカルで`dart format lib test`、`flutter analyze`、関係する`flutter test`を実行。UI整理時は`test/android_caption_editor_test.dart`、`test/android_settings_panel_test.dart`、`test/android_keyboard_test.dart`、`test/android_configuration_test.dart`などを確認する。結果は未実行／実行済みを区別する。
- Android版は**Google Play・他ストアに登録せず、GitHub Releasesで署名済みAPKのみ直接配布**する（2026-11-17本人確定）。Play Console登録、Play Store審査、掲載画像、AAB、Playストア専用の申告・ポリシー対応を初回公開の作業に加えない。Androidのrelease署名鍵と固定applicationId、versionCode増加、APKのSHA-256、手動更新時の設定保持は維持する。Googleの**ストア外アプリ向け開発者確認制度**はPlay登録とは別の将来課題とし、2027年以降の制度変更時だけ再評価する。
- macOS版はDeveloper ID署名・公証を行わず、ad-hoc署名ZIPで配布する（2026-11-17本人確定）。Apple Developer Program登録、公証サービス、独自インストーラを公開条件として追加しない。最終ZIPの署名・SHA-256と、通常ダウンロード後のGatekeeper初回起動を別々に確認する。起動の案内にはApple公式のアプリ個別許可を用い、OS全体の保護無効化や警告の一律回避を促さない。
- GitHub Actionsの自動実行を避ける。Draft PRを維持し、本人の明示承認前にmain統合・Public化・Git履歴の上書き・Release公開・配布物添付を行わない。
- 公開ソースに個人用素材・署名鍵・パスワード・秘密情報・ローカルパスを追加しない。公開時は現行の検証済みスナップショットから新しいクリーン履歴を作り、古いPrivate開発履歴・内部文書を移さない。
- 作業の判断・結果・未確認事項は作業記録に簡潔に残し、GitHubの公開コード・README・Releaseを現行仕様の正本とする。
