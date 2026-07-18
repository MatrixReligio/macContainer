---
source_revision: f94970774a25e899b7fb4a623d35c555d11f12e2
language: zh-Hans
document_id: readme
---

<a id="maccontainer"></a>
# MacContainer

MacContainer 是 Apple `container` 运行时的原生 macOS 控制中心。它用 SwiftUI 呈现完整的已审查功能，同时保留高级参数、明确的安全门禁和真实的恢复信息。

> **预发布版本：** 0.1.8 需要 Apple 芯片与 macOS 26 或更高版本。请为重要的容器数据保留独立备份，并在执行破坏性操作前检查所有值。

[English](README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

英文源版本：`f94970774a25e899b7fb4a623d35c555d11f12e2`。

<a id="why"></a>
## 为什么使用 MacContainer

- 原生管理容器、镜像、构建、虚拟机、网络、存储卷、镜像仓库和系统操作。
- 八种安全场景模板，运行前可检查每个生成值。
- 首次使用时自动准备经过启动验证的 Alpine 3.22 虚拟机镜像，创建后可直接使用内嵌终端。
- 容器向导会在同一个可检查流程中关联 OCI 镜像、容器网络和命名持久卷。
- 通过已审查的 Apple 库和协议直接进行类型安全调用；生产代码不调用 `container` CLI。
- 安装、升级、回滚和完全卸载有独立的权限边界。
- 未知运行时版本在通过签名实体测试和全部兼容性探测前不会自动安装。
- 默认仅在本地处理，不发送分析或遥测数据。
- 完全卸载会验证 15 类产品可控残留。

<a id="requirements"></a>
## 系统要求

- Apple 芯片与 macOS 26 或更高版本
- 安装、更新、回滚或完全卸载运行时时需要管理员账户
- 只有 GitHub、镜像仓库或已批准更新源相关操作才需要网络

仅开发时需要 Xcode 26。

<a id="documentation"></a>
## 文档

- [用户指南](docs/zh-Hans/USER_GUIDE.md)
- [安装](docs/zh-Hans/INSTALLATION.md)
- [运行时更新](docs/zh-Hans/RUNTIME_UPDATES.md)
- [完全卸载](docs/zh-Hans/COMPLETE_UNINSTALLATION.md)
- [故障排除](docs/zh-Hans/TROUBLESHOOTING.md)
- [架构](ARCHITECTURE.md)、[隐私](PRIVACY.md)与[安全](SECURITY.md)

所有普通用户流程都可在应用内完成，无需终端。

<a id="development"></a>
## 开发

仓库固定使用项目本地工具，并检查生成文件、供应链元数据、格式、测试、辅助功能和发布策略。开发者请阅读[开发说明](DEVELOPMENT.md)和[贡献指南](CONTRIBUTING.md)。规范仓库为 `matrixreligio/macContainer`。

<a id="security-support"></a>
## 安全与支持

不要在公开 Issue 中披露漏洞，请按照[安全策略](SECURITY.md)私下报告。产品问题请查看[支持说明](SUPPORT.md)或发送邮件至 [contact@matrixreligio.com](mailto:contact@matrixreligio.com)。MacContainer 采用 Apache-2.0 许可证；参见 [LICENSE](LICENSE)、[NOTICE](NOTICE) 与[第三方声明](THIRD_PARTY_NOTICES)。
