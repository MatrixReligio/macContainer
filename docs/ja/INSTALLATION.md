---
source_revision: f94970774a25e899b7fb4a623d35c555d11f12e2
language: ja
document_id: installation
---

<a id="installation"></a>
# インストール

[英語ソース](../en/INSTALLATION.md) · ソースリビジョン `f94970774a25e899b7fb4a623d35c555d11f12e2`

MacContainerはAppleシリコンとmacOS 26以降が必要です。Apple containerランタイムがなくてもアプリは開けますが、インストールまでコンテナ操作は利用できません。

<a id="before-installing"></a>
## インストール前

正規のGitHub Releaseからだけダウンロードし、macOSが署名・公証済みアプリとして認識することを確認してください。「アプリケーション」へ移して通常どおり開きます。Gatekeeper警告を回避せず、検証できない場合はそのコピーを削除して再ダウンロードしてください。

ランタイムは無断でインストールされません。**設定 → ランタイム**で、権限操作の前に候補バージョン、提供元、署名者、SHA-256、ディスク使用量、互換性を確認できます。

<a id="runtime-package"></a>
## ランタイムパッケージ検証

埋め込みカタログは現在、MacContainer 0.1.xに対してApple container 1.1.0を承認しています。レビュー済みIDは、アセット`container-1.1.0-installer-signed.pkg`、チーム`UPBK2H6LZM`、署名者`Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)`、レシート`com.apple.container-installer`、SHA-256 `0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714`です。

ダウンロードは非公開のステージング領域に保存されます。リンクや予期しない種類を拒否し、サイズとダイジェスト、インストーラ署名、レシートを検証してから**確認してインストール**を有効にします。メタデータの一致だけでは不十分です。

<a id="administrator-approval"></a>
## 管理者の承認

管理者承認はダウンロード、検証、最終確認が終わり、インストールを実際に開始するときだけ求められます。特権ヘルパーは固定された型付き操作とレビュー済みパスだけを受け取り、任意のシェル文字列を受け取りません。承認を取り消すと現在のランタイムを維持し、ステージングを消去します。アクティビティセンターは永続トランザクションを記録し、中断後は検証済み復旧操作だけを提示します。

<a id="post-install"></a>
## インストール後の互換性

インストーラ成功だけでは完了になりません。ランタイムの状態と、コンテナ、イメージ、ビルダー、ネットワーク、ボリューム、レジストリ、マシン、ディスク使用量、設定、機能を検証します。すべて合格して初めて**使用可能**になります。アップグレード後のプローブ失敗時はロールバックポイントを復元して旧ランタイムを再検証します。初回インストールのポストフライト失敗は未完了と復旧操作を表示します。

<a id="app-updates"></a>
## MacContainerの更新

アプリ更新とApple containerランタイム更新は別です。アプリは署名済みSparkleフィードで設定を保持して更新し、ランタイムはより厳格な[ランタイム更新](RUNTIME_UPDATES.md)ポリシーに従います。削除は[完全アンインストール](COMPLETE_UNINSTALLATION.md)、署名や承認の問題は[トラブルシューティング](TROUBLESHOOTING.md)を参照してください。
