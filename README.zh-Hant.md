---
source_revision: f94970774a25e899b7fb4a623d35c555d11f12e2
language: zh-Hant
document_id: readme
---

<a id="maccontainer"></a>
# MacContainer

MacContainer 是 Apple `container` 執行階段的原生 macOS 控制中心。它以 SwiftUI 呈現完整且已審查的功能，同時保留進階參數、明確的安全關卡和真實的復原資訊。

> **預先發佈版本：** 0.1.4 需要 Apple 晶片與 macOS 26 或更新版本。請為重要的容器資料保留獨立備份，並在執行破壞性操作前檢查所有值。

[English](README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

英文來源版本：`f94970774a25e899b7fb4a623d35c555d11f12e2`。

<a id="why"></a>
## 為什麼使用 MacContainer

- 原生管理容器、映像檔、建置、虛擬機器、網路、儲存卷宗、映像檔登錄庫和系統操作。
- 八種安全情境範本，執行前可檢查每個產生的值。
- 透過已審查的 Apple 程式庫和通訊協定直接進行型別安全呼叫；正式環境程式碼不呼叫 `container` CLI。
- 安裝、升級、回復與完整解除安裝都有獨立的權限界線。
- 未知執行階段版本在通過簽章實機測試及全部相容性探測前不會自動安裝。
- 預設僅在本機處理，不傳送分析或遙測資料。
- 完整解除安裝會驗證 15 類產品可控制的殘留項目。

<a id="requirements"></a>
## 系統需求

- Apple 晶片與 macOS 26 或更新版本
- 安裝、更新、回復或完整解除安裝執行階段時需要管理員帳號
- 只有 GitHub、映像檔登錄庫或已核准更新來源相關操作才需要網路

只有開發時需要 Xcode 26。

<a id="documentation"></a>
## 文件

- [使用者指南](docs/zh-Hant/USER_GUIDE.md)
- [安裝](docs/zh-Hant/INSTALLATION.md)
- [執行階段更新](docs/zh-Hant/RUNTIME_UPDATES.md)
- [完整解除安裝](docs/zh-Hant/COMPLETE_UNINSTALLATION.md)
- [疑難排解](docs/zh-Hant/TROUBLESHOOTING.md)
- [架構](ARCHITECTURE.md)、[隱私權](PRIVACY.md)與[安全性](SECURITY.md)

所有一般使用流程都可在應用程式內完成，不需要終端機。

<a id="development"></a>
## 開發

儲存庫固定使用專案本機工具，並檢查產生的檔案、供應鏈中繼資料、格式、測試、輔助使用與發佈政策。開發者請閱讀[開發說明](DEVELOPMENT.md)和[貢獻指南](CONTRIBUTING.md)。標準儲存庫為 `matrixreligio/macContainer`。

<a id="security-support"></a>
## 安全性與支援

請勿在公開 Issue 揭露漏洞，應依照[安全性政策](SECURITY.md)私下回報。產品問題請查看[支援說明](SUPPORT.md)或寄信至 [contact@matrixreligio.com](mailto:contact@matrixreligio.com)。MacContainer 採用 Apache-2.0 授權；請參閱 [LICENSE](LICENSE)、[NOTICE](NOTICE) 與[第三方聲明](THIRD_PARTY_NOTICES)。
