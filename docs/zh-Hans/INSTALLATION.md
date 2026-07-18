---
source_revision: f94970774a25e899b7fb4a623d35c555d11f12e2
language: zh-Hans
document_id: installation
---

<a id="installation"></a>
# 安装

[英文源文档](../en/INSTALLATION.md) · 源版本 `f94970774a25e899b7fb4a623d35c555d11f12e2`

MacContainer 需要 Apple 芯片和 macOS 26 或更高版本。未安装 Apple container 运行时时仍可打开应用，但容器操作会保持不可用。

<a id="before-installing"></a>
## 安装前

只从规范 GitHub Release 下载 MacContainer，并确认 macOS 将应用识别为已签名和公证。将应用移到“应用程序”后正常打开。不要绕过 Gatekeeper 警告；如无法验证，请删除该副本并重新下载。

应用不会静默安装运行时。打开**设置 → 运行时**，可在任何权限操作前查看候选版本、来源、签名方、SHA-256、磁盘影响和兼容性状态。

<a id="runtime-package"></a>
## 运行时软件包验证

内嵌目录目前允许 MacContainer 0.1.x 使用 Apple container 1.1.0。已审查身份为：资源 `container-1.1.0-installer-signed.pkg`；安装团队 `UPBK2H6LZM`；签名方 `Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)`；收据 `com.apple.container-installer`；SHA-256 `0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714`。

下载进入私有暂存目录。应用会拒绝链接和意外文件类型，校验字节数与摘要，并验证安装器签名和收据，随后才启用**检查并安装**。只匹配元数据绝不够。

<a id="administrator-approval"></a>
## 管理员批准

只有完成下载、验证和最终检查，并真正开始安装时才会请求管理员批准。特权帮助程序只接受固定的类型安全操作与已审查路径，不接受任意 shell 文本。取消批准会保持当前运行时不变并清理暂存目录。活动中心记录持久事务阶段；中断后，应用只提供经过验证的恢复操作。

首次使用时，macOS 可能还会要求你在**系统设置 → 通用 → 登录项**中允许 MacContainer 帮助程序。运行时页面会明确显示此状态并打开正确的设置页；批准一次后返回 MacContainer，点击**检查批准**，再重试安装。

<a id="post-install"></a>
## 安装后兼容性

安装器成功不等于安装完成。应用还会验证运行时健康以及容器、镜像、构建器、网络、存储卷、镜像仓库、虚拟机、磁盘占用、配置和能力。如果全部通过，状态才变为**已就绪**。升级探测失败时会恢复回滚点并重新验证旧运行时；首次安装后置检查失败会显示未完成及恢复操作。

<a id="app-updates"></a>
## 更新 MacContainer

应用更新与 Apple container 运行时更新彼此独立。应用更新使用签名的 Sparkle Feed 并保留设置；运行时遵循更严格的[运行时更新](RUNTIME_UPDATES.md)策略。移除选项参见[完全卸载](COMPLETE_UNINSTALLATION.md)，签名或授权问题参见[故障排除](TROUBLESHOOTING.md)。
