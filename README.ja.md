---
source_revision: f94970774a25e899b7fb4a623d35c555d11f12e2
language: ja
document_id: readme
---

<a id="maccontainer"></a>
# MacContainer

MacContainerは、Appleの`container`ランタイムを管理するネイティブmacOSコントロールセンターです。レビュー済みの全機能をSwiftUIで扱いやすくしながら、詳細パラメータ、明示的な安全ゲート、正確な復旧情報を維持します。

> **プレリリース：** バージョン0.1.4はAppleシリコンとmacOS 26以降が必要です。重要なコンテナデータは別途バックアップし、破壊的な操作の前にすべての値を確認してください。

[English](README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

英語ソースリビジョン：`f94970774a25e899b7fb4a623d35c555d11f12e2`

<a id="why"></a>
## MacContainerを使う理由

- コンテナ、イメージ、ビルド、マシン、ネットワーク、ボリューム、レジストリ、システム操作をネイティブに管理します。
- 8つの安全なシナリオテンプレートで、実行前にすべての生成値を確認できます。
- レビュー済みのAppleライブラリとプロトコルを型安全に直接使用し、本番コードから`container` CLIを呼び出しません。
- インストール、アップグレード、ロールバック、完全アンインストールには明確な権限境界があります。
- 未知のランタイムは、署名済み実機テストと全プローブに合格するまで自動インストールされません。
- 既定ではローカル処理のみで、分析やテレメトリを送信しません。
- 完全アンインストールは、製品が制御する15種類の残留項目を検証します。

<a id="requirements"></a>
## 動作要件

- Appleシリコン搭載MacとmacOS 26以降
- ランタイムのインストール、更新、ロールバック、完全アンインストールには管理者アカウント
- GitHub、レジストリ、承認済み更新フィードを明示的に利用する操作のみネットワークが必要

Xcode 26は開発時だけ必要です。

<a id="documentation"></a>
## ドキュメント

- [ユーザーガイド](docs/ja/USER_GUIDE.md)
- [インストール](docs/ja/INSTALLATION.md)
- [ランタイム更新](docs/ja/RUNTIME_UPDATES.md)
- [完全アンインストール](docs/ja/COMPLETE_UNINSTALLATION.md)
- [トラブルシューティング](docs/ja/TROUBLESHOOTING.md)
- [アーキテクチャ](ARCHITECTURE.md)、[プライバシー](PRIVACY.md)、[セキュリティ](SECURITY.md)

一般ユーザー向けの操作はすべてアプリ内で完結し、ターミナルは不要です。

<a id="development"></a>
## 開発

リポジトリはプロジェクトローカルのツールを固定し、生成ファイル、サプライチェーン情報、書式、テスト、アクセシビリティ、リリースポリシーを検証します。[開発ガイド](DEVELOPMENT.md)と[コントリビューションガイド](CONTRIBUTING.md)を参照してください。正規リポジトリは`matrixreligio/macContainer`です。

<a id="security-support"></a>
## セキュリティとサポート

脆弱性の詳細を公開Issueに投稿せず、[セキュリティポリシー](SECURITY.md)に従って非公開で報告してください。製品サポートは[サポート](SUPPORT.md)または [contact@matrixreligio.com](mailto:contact@matrixreligio.com) へ。MacContainerはApache-2.0で提供されます。[LICENSE](LICENSE)、[NOTICE](NOTICE)、[第三者通知](THIRD_PARTY_NOTICES)を参照してください。
