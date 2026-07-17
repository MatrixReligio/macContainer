---
source_revision: f94970774a25e899b7fb4a623d35c555d11f12e2
language: zh-Hant
document_id: installation
---

<a id="installation"></a>
# 安裝

[英文來源文件](../en/INSTALLATION.md) · 來源版本 `f94970774a25e899b7fb4a623d35c555d11f12e2`

MacContainer 需要 Apple 晶片和 macOS 26 或更新版本。未安裝 Apple container 執行階段時仍可開啟應用程式，但容器操作會保持無法使用。

<a id="before-installing"></a>
## 安裝前

只從標準 GitHub Release 下載 MacContainer，並確認 macOS 將應用程式識別為已簽章和公證。移到「應用程式」後正常開啟。不要略過 Gatekeeper 警告；如無法驗證，請刪除該副本並重新下載。

應用程式不會在背景安裝執行階段。開啟**設定 → 執行階段**，即可在任何權限操作前查看候選版本、來源、簽章者、SHA-256、磁碟影響和相容性狀態。

<a id="runtime-package"></a>
## 執行階段套件驗證

內嵌目錄目前允許 MacContainer 0.1.x 使用 Apple container 1.1.0。已審查身分為：資源 `container-1.1.0-installer-signed.pkg`；安裝團隊 `UPBK2H6LZM`；簽章者 `Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)`；收據 `com.apple.container-installer`；SHA-256 `0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714`。

下載會進入私人暫存目錄。應用程式拒絕連結與非預期檔案類型，檢查位元組數和摘要，再驗證安裝程式簽章與收據，之後才啟用**檢查並安裝**。只符合中繼資料並不足夠。

<a id="administrator-approval"></a>
## 管理員核准

只有完成下載、驗證和最後檢查，且真正開始安裝時才會要求管理員核准。特殊權限輔助程式只接受固定的型別安全操作與已審查路徑，不接受任意 shell 文字。取消核准會保持目前執行階段不變並清除暫存目錄。活動中心記錄持久交易階段；中斷後，應用程式只提供已驗證的復原操作。

<a id="post-install"></a>
## 安裝後相容性

安裝程式成功不代表安裝完成。應用程式還會驗證執行階段健康狀態，以及容器、映像檔、建置器、網路、儲存卷宗、映像檔登錄庫、虛擬機器、磁碟用量、設定和能力。全部通過後狀態才會變成**已就緒**。升級探測失敗時會還原回復點並重新驗證舊執行階段；首次安裝後置檢查失敗會顯示未完成與復原操作。

<a id="app-updates"></a>
## 更新 MacContainer

應用程式更新與 Apple container 執行階段更新彼此獨立。應用程式更新使用簽章 Sparkle Feed 並保留設定；執行階段遵循更嚴格的[執行階段更新](RUNTIME_UPDATES.md)政策。移除選項請參閱[完整解除安裝](COMPLETE_UNINSTALLATION.md)，簽章或授權問題請參閱[疑難排解](TROUBLESHOOTING.md)。
