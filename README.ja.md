# gimme-remote

[English](README.md) | [简体中文](README.zh-CN.md) | **日本語** | [한국어](README.ko.md)

**テレビにつないだ Mac を、スマートフォンで操作。** QR コードをスキャンして使える、ローカルネットワーク接続のリモコンです。Mac 側の Swift ネイティブメニューバーアプリが、スマートフォン用の Web インターフェースを提供します。iOS アプリのインストールは不要です。

対応機能：IINA / ブラウザの再生操作、タッチパッド（ダブルクリック、スクロール、ドラッグ）、Unicode テキスト入力、ブラウザのショートカット、QR コードによるペアリング、キーチェーンで保存する端末ごとのトークン、権限とロック状態の案内、再接続、ログイン時の起動、接続中の画面スリープ防止、中国語 / 英語 / 日本語 / 韓国語のインターフェース、およびローカルの `gimme` CLI。

今後の予定：スクリーンショット上のクリック操作と、端末ごとの管理。

## インストール

Homebrew でインストール：

```bash
brew install --cask lucientong/tap/gimme-remote
open -a GimmeRemote
```

[GitHub Releases](https://github.com/lucientong/gimme-remote/releases/latest) から直接ダウンロードすることもできます。**Assets** を開き、`GimmeRemote-<version>-universal.zip` をダウンロードして展開し、`GimmeRemote.app` を「アプリケーション」に移動してください。その後「アプリケーション」から起動します。同じ ZIP が Apple Silicon と Intel の両方に対応し、Homebrew や Node は不要です。

最新のテスト版は [testing リリース](https://github.com/lucientong/gimme-remote/releases/tag/testing) からダウンロードできます。`master` のチェックに合格すると更新され、正式版にまだ含まれていない変更が入る場合があります。

メニューバーアプリを開き、アクセシビリティを許可してください。スマートフォンと Mac を同じ Wi-Fi に接続し、QR コードをスキャンします。ホーム画面から使いたい場合は、先にスマートフォンの Chrome で **共有 → ホーム画面に追加** を選び、追加したアイコンから開いてペアリングコードを入力してください。iOS のホーム画面 Web アプリとブラウザはデータを個別に保存するため、Chrome でのペアリングはホーム画面のアプリに引き継がれません。

Mac アプリとスマートフォンの画面は、それぞれのシステム言語に合わせて中国語、英語、日本語、韓国語を表示します。その他の言語では英語になります。手動で変更するには、Mac のパネルで **一般 → 言語** を選ぶか、スマートフォンのページ上部にある接続状態をタップし、**設定 → 言語** を選んでください。選択は保存され、表示中のエラーメッセージもすぐに切り替わります。スマートフォンではペアリング前にも変更でき、接続や入力中のテキストは維持されます。**システムに合わせる** を選ぶと自動検出に戻ります。中国語の地域・文字体系の違いは、現在すべて簡体字で表示します。

音量ボタンは **プレーヤーの音量** を調整します。テレビ全体の音量はテレビのリモコンで調整してください。Web プレーヤーのショートカットはページのフォーカスやサイトの対応状況に依存します。タッチパッドを使って、テレビに表示されている操作ボタンをクリックすることもできます。Service Worker、クラウド中継、任意のスクリプト実行は使用しません。

ブラウザの **戻る / 進む** は閲覧履歴を移動します（⌘[ / ⌘]）。新しい履歴がなければ「進む」は何も行いません。プレーヤーの **早送り / 巻き戻し** は右 / 左矢印キーを送信します。**前のエピソード / 次のエピソード** のアイコンは、現在の Web プレーヤーのアクセシビリティツリーで、再生・一時停止ボタンの近くに対応する操作ボタンを識別できた場合にのみ表示されます。サイトのボタンを直接呼び出し、先頭・末尾などで無効になっているボタンは無効のままです。既存のアクセシビリティ権限を使い、ブラウザとサイトが名前付きの操作ボタンを公開していることが必要です。識別できない場合や複数の候補がある場合は、エピソードのボタンを表示しません。

信頼できる家庭内ネットワークで使用してください。リモコンのページは LAN 内で平文 HTTP により提供され、TLS ではなく、一度限りのペアリングコードと端末ごとのトークンで保護されます。公共・共有 Wi-Fi での使用は避けてください。

macOS 14 以降が必要です。リリースは Apple Silicon / Intel 対応の Universal アプリで、Apple Developer ID を使用せず GitHub Releases で配布します。Apple による公証は受けていません。

初回起動が macOS によってブロックされた場合は、**システム設定 → プライバシーとセキュリティ → このまま開く** から GimmeRemote の起動を許可してください。リモート入力にはアクセシビリティ権限が必要です。更新後、GimmeRemote が有効になっていても入力できない場合は、**プライバシーとセキュリティ → アクセシビリティ** の一覧で選択し、**−** で削除してから再度追加するか、アプリを開き直してください。

## 開発

Swift 6.2 以降と Node 22.12 以降が必要です。ネイティブの全テストを実行するには Xcode が必要です。Command Line Tools でもアプリのビルドとコアのセキュリティチェックを実行できます。

```bash
npm --prefix web ci
npm --prefix web test
npm --prefix web run build
swift build --package-path mac --jobs 4 --disable-index-store
bash scripts/test-core.sh
bash scripts/test-menu-panel.sh
swift run --package-path mac --jobs 4 --disable-index-store TransportChecks

# Xcode がインストールされた環境
swift test --package-path mac --jobs 4
```

`TransportChecks` は一時的なページとメモリ内のトークンを使い、実際の HTTP / WebSocket 動作を検証します。個人のキーチェーンにはアクセスせず、システムへの入力も行いません。

ネイティブアプリをデバッグするには、Xcode で `mac/Package.swift` を開いてください。Bundle ID は `com.lucientong.GimmeRemote` に統一します。インストール、入力権限、ログイン時の起動は、`scripts/build-release.sh` が生成する App バンドルで確認してください。Swift Package Manager の単独実行ファイルは、インストール済みのアプリではありません。

フロントエンドだけをホットリロード付きで起動：

```bash
npm --prefix web run dev
```

Mac に接続せず画面を確認するには、Vite の URL に `/?preview=browser` を付けて開くか（通常は `http://localhost:5173/?preview=browser`）、ページ上部の **リモコンをプレビュー** をクリックしてください。`npm --prefix web run dev:preview` で Vite を起動し、プレビューを自動で開くこともできます。バックエンドやペアリングは不要です。シリーズ動画、単独の動画、最初・最後のエピソード、IINA、汎用、一時停止、ロックの各状態を切り替えられます。ボタン操作は Mac に送信されません。上部の接続状態から四つの言語も確認できます。このプレビューは Vite の開発モードでのみ有効です。

スマートフォンの翻訳は `web/src/i18n.ts`、Mac の翻訳は `mac/Sources/GimmeRemote/Localization.swift` にあります。両方のカタログで翻訳の網羅性とプレースホルダーの一致を検証します。ネイティブパネルのチェックは、四つの言語でペアリングの展開・折りたたみ、権限案内、高さ制限時のスクロールを確認します。`mac/Resources/*.lproj/InfoPlist.strings` のシステム権限説明は、システムで設定したアプリの言語に従い、リリーススクリプトでコピーされます。翻訳はアプリと Web バンドルに含まれ、追加のリソースダウンロードは不要です。

`TransportChecks` は HTTP / WebSocket の回帰テストを実行して終了します。ポート `19371` はテスト中だけ使用され、フロントエンド用の常駐バックエンドではありません。

アプリはデフォルトでポート `9271` を使用します。Vite は `/ws` を `127.0.0.1:9271` にプロキシします。開発中のネイティブアプリには、次の環境変数を設定してください：

```text
GIMME_WEB_ROOT=/absolute/path/to/gimme-remote/web/dist
GIMME_DEV_ORIGINS=http://localhost:5173,http://192.168.1.2:5173
```

二つ目の Origin は、Vite を動かす Mac の実際の LAN IP アドレスに置き換えます。開発用 Origin は明示的に許可リストへ追加する必要があります。スマートフォンから Vite にアクセスする際も Mac の IP アドレスを使ってください。`VITE_REMOTE_URL=http://mac.local:9271` でネイティブサービスへ直接接続することもできますが、その場合も Vite ページの Origin を許可リストに追加する必要があります。

リリースビルドは `web/dist` を `GimmeRemote.app/Contents/Resources/Web` にコピーします。ページと WebSocket は同じ Origin を使い、本番環境では Node は不要です。ネットワークが変わると、メニューバーの接続アドレスも更新されます。新しいローカル IP のページでは再ペアリングが必要な場合があるため、安定した `.local` アドレスを保存することをお勧めします。

## CLI

```bash
gimme status   # サービス、権限、接続数、アクセス URL を表示
gimme pair     # 一度限りのペアリングコードを更新し、アクセス URL を表示
gimme stop     # リモート入力を一時停止
gimme resume   # リモート入力を再開
gimme --version
```

CLI は、現在のユーザー専用ディレクトリ内の Unix ソケットで通信します。メニューバーでは、入力の一時停止、端末の切断、すべてのペアリングの解除、ログイン時の起動、接続中の画面スリープ防止を設定できます。一時停止中もスマートフォンの接続は維持され、再開すると操作可能になります。端末を切断してもペアリングは保存されますが、スマートフォンで **再接続** をタップする必要があります。ペアリングを解除した場合は、再度ペアリングしてください。

## リリース

プルリクエストではチェックを実行します。プルリクエストの取り込みを含む `master` への push は、チェックに合格すると `testing` プレリリースを公開します。`vMAJOR.MINOR.PATCH` 形式のタグは正式リリースを公開し、Homebrew tap を更新します。プレリリースの接尾辞付きタグはプレリリースを公開しますが、正式版の Cask は更新しません。

ビルドに Apple Developer のメンバーシップは不要です。設定が必須のカスタムリポジトリシークレットは、`lucientong/gimme-remote` の `HOMEBREW_TAP_TOKEN` だけです。GitHub の fine-grained PAT を使い、**`lucientong/homebrew-tap` のみに Contents: Read and write** を許可してください。リリース公開用のトークンは GitHub が自動で提供します。

リリースはデフォルトで ad-hoc 署名されるため、更新のたびに macOS がアクセシビリティの許可を解除する場合があります。許可を維持するには、自己署名のコード署名証明書を使い、二つの任意シークレットを設定してください：`MACOS_SIGNING_P12_BASE64`（`.p12` の base64）と `MACOS_SIGNING_P12_PASSWORD`。Apple アカウントは不要ですが、リリース間で同じ証明書を使う必要があります。秘密鍵をリポジトリに保存しないでください。

macOS 上でローカルのリリースビルドを作成：

```bash
bash scripts/build-release.sh
```

デフォルトでは `build/` に Universal の `GimmeRemote.app`、ZIP、`SHA256SUMS` を生成します。再ビルド時は `GIMME_OUTPUT_DIR` で新しい出力先を指定してください。既存のアプリは置き換えません。`GIMME_SIGNING_IDENTITY`（必要なら `GIMME_SIGNING_KEYCHAIN` も）を指定すると、ad-hoc の代わりに固定の署名 ID を使えます。`--unsigned` はバンドル構造の検証専用で、配布用 ZIP は生成しません。

## プロジェクト構成

```text
mac/        Swift ネイティブアプリ、サーバー、入力処理、CLI、コアテスト
web/        Preact / TypeScript / Vite のスマートフォン用画面
shared/     プロトコルの JSON Schema
scripts/    ビルド、コアチェック、Homebrew Cask 生成
```

ブラウザ、iPhone、HDMI ディスプレイ、システム権限の実際の動作は、実機で確認する必要があります。自動テストはすべてのプレーヤーの状況を網羅するものではありません。

アイコンは `swift scripts/make-icons.swift` で `mac/AppIcon.icns` と `web/public/icons/` に生成します。変更した場合は再生成し、生成物をコミットしてください。

名前は英語の口語表現 *gimme the remote*（リモコンを渡して）に由来します。
