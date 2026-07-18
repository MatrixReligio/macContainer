#!/usr/bin/swift
import Foundation

// Translation records remain one record per source string for review and deterministic regeneration.
// swiftlint:disable line_length

private let locales = ["en", "zh-Hans", "zh-Hant", "ja", "ko"]

private struct LocalizedValue {
    let en: String
    let zhHans: String
    let zhHant: String
    let ja: String
    let ko: String

    var values: [String: String] {
        ["en": en, "zh-Hans": zhHans, "zh-Hant": zhHant, "ja": ja, "ko": ko]
    }
}

private let core: [String: LocalizedValue] = [
    "Application language": .init(en: "Application language", zhHans: "应用语言", zhHant: "應用程式語言", ja: "アプリの言語", ko: "앱 언어"),
    "System Language": .init(en: "System Language", zhHans: "跟随系统", zhHant: "跟隨系統", ja: "システム言語", ko: "시스템 언어"),
    "Relaunch": .init(en: "Relaunch", zhHans: "重新启动", zhHant: "重新啟動", ja: "再起動", ko: "다시 실행"),
    "Cancel": .init(en: "Cancel", zhHans: "取消", zhHant: "取消", ja: "キャンセル", ko: "취소"),
    "Settings": .init(en: "Settings", zhHans: "设置", zhHant: "設定", ja: "設定", ko: "설정"),
    "General": .init(en: "General", zhHans: "通用", zhHant: "一般", ja: "一般", ko: "일반"),
    "Language": .init(en: "Language", zhHans: "语言", zhHant: "語言", ja: "言語", ko: "언어"),
    "Privacy": .init(en: "Privacy", zhHans: "隐私", zhHant: "隱私權", ja: "プライバシー", ko: "개인정보 보호"),
    "Overview": .init(en: "Overview", zhHans: "概览", zhHant: "概覽", ja: "概要", ko: "개요"),
    "Containers": .init(en: "Containers", zhHans: "容器", zhHant: "容器", ja: "コンテナ", ko: "컨테이너"),
    "Images": .init(en: "Images", zhHans: "镜像", zhHant: "映像檔", ja: "イメージ", ko: "이미지"),
    "Builds": .init(en: "Builds", zhHans: "构建", zhHant: "建置", ja: "ビルド", ko: "빌드"),
    "Machines": .init(en: "Machines", zhHans: "虚拟机", zhHant: "虛擬機器", ja: "マシン", ko: "머신"),
    "Networks": .init(en: "Networks", zhHans: "网络", zhHant: "網路", ja: "ネットワーク", ko: "네트워크"),
    "Volumes": .init(en: "Volumes", zhHans: "存储卷", zhHant: "儲存卷宗", ja: "ボリューム", ko: "볼륨"),
    "Registries": .init(en: "Registries", zhHans: "镜像仓库", zhHant: "映像檔登錄庫", ja: "レジストリ", ko: "레지스트리"),
    "System": .init(en: "System", zhHans: "系统", zhHant: "系統", ja: "システム", ko: "시스템"),
    "Runtime updates": .init(en: "Runtime updates", zhHans: "运行时更新", zhHant: "執行階段更新", ja: "ランタイム更新", ko: "런타임 업데이트"),
    "MacContainer runtime update": .init(en: "MacContainer runtime update", zhHans: "MacContainer 运行时更新", zhHant: "MacContainer 執行階段更新", ja: "MacContainer ランタイムアップデート", ko: "MacContainer 런타임 업데이트"),
    "Apple container %@ is compatibility-approved and ready to review.": .init(en: "Apple container %@ is compatibility-approved and ready to review.", zhHans: "Apple container %@ 已通过兼容性验证，可以查看。", zhHant: "Apple container %@ 已通過相容性驗證，可供檢視。", ja: "Apple container %@ は互換性が確認され、確認できます。", ko: "Apple container %@의 호환성 검증이 완료되어 검토할 수 있습니다."),
    "An approved runtime update is waiting. Open MacContainer for details.": .init(en: "An approved runtime update is waiting. Open MacContainer for details.", zhHans: "已批准的运行时更新正在等待。请打开 MacContainer 查看详情。", zhHant: "已核准的執行階段更新正在等候。請開啟 MacContainer 查看詳細資訊。", ja: "承認済みのランタイムアップデートが保留中です。詳細は MacContainer で確認してください。", ko: "승인된 런타임 업데이트가 대기 중입니다. MacContainer에서 세부 정보를 확인하십시오."),
    "A discovered runtime is held for safety. Open MacContainer for details.": .init(en: "A discovered runtime is held for safety. Open MacContainer for details.", zhHans: "检测到的运行时已为安全起见暂停。请打开 MacContainer 查看详情。", zhHant: "偵測到的執行階段已基於安全考量暫停。請開啟 MacContainer 查看詳細資訊。", ja: "検出されたランタイムは安全のため保留されています。詳細は MacContainer で確認してください。", ko: "발견된 런타임이 안전을 위해 보류되었습니다. MacContainer에서 세부 정보를 확인하십시오."),
    "The runtime update was rolled back. Open MacContainer for recovery details.": .init(en: "The runtime update was rolled back. Open MacContainer for recovery details.", zhHans: "运行时更新已回滚。请打开 MacContainer 查看恢复详情。", zhHant: "執行階段更新已回復。請開啟 MacContainer 查看復原詳細資訊。", ja: "ランタイムアップデートはロールバックされました。復旧の詳細は MacContainer で確認してください。", ko: "런타임 업데이트가 롤백되었습니다. MacContainer에서 복구 세부 정보를 확인하십시오."),
    "Runtime recovery requires attention in MacContainer.": .init(en: "Runtime recovery requires attention in MacContainer.", zhHans: "运行时恢复需要在 MacContainer 中处理。", zhHant: "執行階段復原需要在 MacContainer 中處理。", ja: "MacContainer でランタイムの復旧対応が必要です。", ko: "MacContainer에서 런타임 복구 조치가 필요합니다."),
    "Open MacContainer to review runtime update status.": .init(en: "Open MacContainer to review runtime update status.", zhHans: "请打开 MacContainer 查看运行时更新状态。", zhHant: "請開啟 MacContainer 查看執行階段更新狀態。", ja: "ランタイムアップデートの状態を MacContainer で確認してください。", ko: "MacContainer에서 런타임 업데이트 상태를 확인하십시오."),
    "Check now": .init(en: "Check now", zhHans: "立即检查", zhHant: "立即檢查", ja: "今すぐ確認", ko: "지금 확인"),
    "Install compatible update": .init(en: "Install compatible update", zhHans: "安装兼容更新", zhHant: "安裝相容更新", ja: "互換性確認済み更新をインストール", ko: "호환성 확인 업데이트 설치"),
    "Complete uninstall": .init(en: "Complete uninstall", zhHans: "完全卸载", zhHant: "完整解除安裝", ja: "完全アンインストール", ko: "완전 제거"),
    "Remove runtime and preserve data": .init(en: "Remove runtime and preserve data", zhHans: "移除运行时并保留数据", zhHant: "移除執行階段並保留資料", ja: "データを保持してランタイムを削除", ko: "데이터를 유지하고 런타임 제거"),
    "Review and install": .init(en: "Review and install", zhHans: "检查并安装", zhHant: "檢查並安裝", ja: "確認してインストール", ko: "검토 후 설치"),
    "Activity Center": .init(en: "Activity Center", zhHans: "活动中心", zhHant: "活動中心", ja: "アクティビティセンター", ko: "활동 센터"),
    "Retry after review": .init(en: "Retry after review", zhHans: "检查后重试", zhHant: "檢查後重試", ja: "確認後に再試行", ko: "검토 후 다시 시도"),
    "Required": .init(en: "Required", zhHans: "必填", zhHant: "必填", ja: "必須", ko: "필수"),
    "Optional": .init(en: "Optional", zhHans: "可选", zhHant: "選填", ja: "任意", ko: "선택 사항"),
    "Accepted values": .init(en: "Accepted values", zhHans: "可接受值", zhHant: "可接受值", ja: "使用可能な値", ko: "허용 값"),
    "Validation": .init(en: "Validation", zhHans: "校验", zhHant: "驗證", ja: "検証", ko: "유효성 검사"),
    "Security impact": .init(en: "Security impact", zhHans: "安全影响", zhHant: "安全性影響", ja: "セキュリティへの影響", ko: "보안 영향"),
    "No analytics or telemetry are sent by default.": .init(en: "No analytics or telemetry are sent by default.", zhHans: "默认不发送分析数据或遥测信息。", zhHant: "預設不會傳送分析資料或遙測資訊。", ja: "分析データやテレメトリは既定で送信されません。", ko: "기본적으로 분석 또는 원격 측정 데이터를 보내지 않습니다."),
    "Unknown version 1.2.0 is held — no automatic install": .init(en: "Unknown version 1.2.0 is held — no automatic install", zhHans: "未知版本 1.2.0 已暂停，不会自动安装", zhHant: "未知版本 1.2.0 已暫停，不會自動安裝", ja: "未確認のバージョン 1.2.0 は保留され、自動インストールされません", ko: "알 수 없는 버전 1.2.0은 보류되며 자동 설치되지 않습니다"),
    "Compatibility failed — rolled back to 1.0.0": .init(en: "Compatibility failed — rolled back to 1.0.0", zhHans: "兼容性检查失败，已回滚到 1.0.0", zhHant: "相容性檢查失敗，已回復到 1.0.0", ja: "互換性確認に失敗し、1.0.0 にロールバックしました", ko: "호환성 검사에 실패하여 1.0.0으로 롤백했습니다")
]

private func translation(
    _ en: String,
    _ zhHans: String,
    _ zhHant: String,
    _ ja: String,
    _ ko: String
) -> (String, LocalizedValue) {
    (en, .init(en: en, zhHans: zhHans, zhHant: zhHant, ja: ja, ko: ko))
}

private let additionalCore = Dictionary(uniqueKeysWithValues: [
    translation("About", "关于", "關於", "情報", "정보"),
    translation("Audit complete — %lld owned artifact categories are present", "审计完成——存在 %lld 个所属项目类别", "稽核完成——存在 %lld 個所屬項目類別", "監査完了 — 所有項目のカテゴリが %lld 件あります", "감사 완료 — 소유 항목 범주 %lld개가 있습니다"),
    translation("Audit complete — no owned residue detected", "审计完成——未检测到所属残留", "稽核完成——未偵測到所屬殘留", "監査完了 — 所有する残留項目は検出されませんでした", "감사 완료 — 소유 잔여 항목이 감지되지 않았습니다"),
    translation("Audit completed with %lld unverifiable categories", "审计完成，%lld 个类别无法验证", "稽核完成，%lld 個類別無法驗證", "監査完了 — %lld 件のカテゴリを検証できませんでした", "감사 완료 — 범주 %lld개를 확인할 수 없습니다"),
    translation("Auditing owned runtime residue…", "正在审计运行时所属残留…", "正在稽核執行階段所屬殘留…", "ランタイム所有の残留項目を監査中…", "런타임 소유 잔여 항목 감사 중…"),
    translation("Boolean", "布尔值", "布林值", "ブール値", "불리언"),
    translation("Baseline capture", "捕获升级基线", "擷取升級基準", "アップグレード基準の取得", "업그레이드 기준 캡처"),
    translation("Builder", "构建器", "建置器", "ビルダー", "빌더"),
    translation("Compatibility checks", "兼容性检查", "相容性檢查", "互換性チェック", "호환성 검사"),
    translation("Configure native operation", "配置原生操作", "設定原生操作", "ネイティブ操作を設定", "네이티브 작업 구성"),
    translation("Consent", "授权确认", "授權確認", "同意の確認", "동의 확인"),
    translation("Core", "核心", "核心", "コア", "코어"),
    translation("Destructive", "破坏性", "破壞性", "破壊的", "파괴적"),
    translation("Disk usage", "磁盘占用", "磁碟用量", "ディスク使用量", "디스크 사용량"),
    translation("DNS", "DNS", "DNS", "DNS", "DNS"),
    translation("Duration", "时长", "持續時間", "期間", "기간"),
    translation("Enumeration", "枚举值", "列舉值", "列挙値", "열거형"),
    translation("Final idle check", "最终空闲检查", "最終閒置檢查", "最終アイドル確認", "최종 유휴 검사"),
    translation("Health", "健康状态", "健康狀態", "健全性", "상태"),
    translation("Host recommendation", "主机推荐值", "主機建議值", "ホスト推奨値", "호스트 권장값"),
    translation("Image metadata", "镜像元数据", "映像檔中繼資料", "イメージメタデータ", "이미지 메타데이터"),
    translation("Install completion", "完成安装", "完成安裝", "インストール完了", "설치 완료"),
    translation("Install preparation", "准备安装", "準備安裝", "インストール準備", "설치 준비"),
    translation("Installed runtime verification", "已安装运行时验证", "已安裝執行階段驗證", "インストール済みランタイムの検証", "설치된 런타임 검증"),
    translation("Installing approved runtime — %@", "正在安装已批准的运行时——%@", "正在安裝已核准的執行階段——%@", "承認済みランタイムをインストール中 — %@", "승인된 런타임 설치 중 — %@"),
    translation("Kernel", "内核", "核心", "カーネル", "커널"),
    translation("Kernel verification", "内核验证", "核心驗證", "カーネル検証", "커널 검증"),
    translation("Key-value pair", "键值对", "鍵值組", "キーと値のペア", "키-값 쌍"),
    translation("Metadata fetch", "获取元数据", "取得中繼資料", "メタデータ取得", "메타데이터 가져오기"),
    translation("Log In", "登录", "登入", "ログイン", "로그인"),
    translation("Mount", "挂载", "掛載", "マウント", "마운트"),
    translation("Mutating", "更改状态", "變更狀態", "変更あり", "상태 변경"),
    translation("No", "否", "否", "いいえ", "아니요"),
    translation("No registry credentials", "没有镜像仓库凭据", "沒有映像檔登錄庫憑證", "レジストリ認証情報がありません", "레지스트리 자격 증명이 없습니다"),
    translation("Not set", "未设置", "未設定", "未設定", "설정 안 함"),
    translation("Package download", "下载软件包", "下載套件", "パッケージのダウンロード", "패키지 다운로드"),
    translation("Package installation", "安装软件包", "安裝套件", "パッケージのインストール", "패키지 설치"),
    translation("Package preparation", "准备软件包", "準備套件", "パッケージの準備", "패키지 준비"),
    translation("Package verification", "验证软件包", "驗證套件", "パッケージ検証", "패키지 검증"),
    translation("Payload verification", "载荷验证", "承載內容驗證", "ペイロード検証", "페이로드 검증"),
    translation("Platform", "平台", "平台", "プラットフォーム", "플랫폼"),
    translation("Platform preflight", "平台预检", "平台預先檢查", "プラットフォーム事前確認", "플랫폼 사전 검사"),
    translation("Port mapping", "端口映射", "連接埠對應", "ポートマッピング", "포트 매핑"),
    translation("Privileged", "需要特权", "需要特殊權限", "特権が必要", "권한 필요"),
    translation("Previous package verification", "验证先前软件包", "驗證先前套件", "以前のパッケージを検証", "이전 패키지 검증"),
    translation("Read only", "只读", "唯讀", "読み取り専用", "읽기 전용"),
    translation("Receipt verification", "安装收据验证", "安裝收據驗證", "レシート検証", "설치 영수증 검증"),
    translation("Rollback package retention", "保留回滚软件包", "保留回復套件", "ロールバックパッケージの保持", "롤백 패키지 보관"),
    translation("Rollback point creation", "创建回滚点", "建立回復點", "ロールバックポイントの作成", "롤백 지점 생성"),
    translation("Runtime shutdown", "停止运行时", "停止執行階段", "ランタイム停止", "런타임 종료"),
    translation("Runtime startup", "启动运行时", "啟動執行階段", "ランタイム起動", "런타임 시작"),
    translation("Scenario rule", "场景规则", "情境規則", "シナリオルール", "시나리오 규칙"),
    translation("Selects this scenario and opens configuration", "选择此场景并打开配置", "選取此情境並開啟設定", "このシナリオを選択して設定を開きます", "이 시나리오를 선택하고 구성을 엽니다"),
    translation("Signal", "信号", "訊號", "シグナル", "신호"),
    translation("String", "文本", "文字", "文字列", "문자열"),
    translation("Upstream default", "上游默认值", "上游預設值", "アップストリーム既定値", "업스트림 기본값"),
    translation("URL", "URL", "URL", "URL", "URL"),
    translation("User override", "用户设置值", "使用者設定值", "ユーザー設定値", "사용자 설정값"),
    translation("Log in to a registry to store a reviewed credential, then refresh this list.", "登录镜像仓库以存储经审核的凭据，然后刷新此列表。", "登入映像檔登錄庫以儲存經審核的憑證，然後重新整理此列表。", "レジストリにログインして確認済みの認証情報を保存し、この一覧を更新してください。", "레지스트리에 로그인하여 검토된 자격 증명을 저장한 다음 이 목록을 새로 고치십시오."),
    translation("Yes", "是", "是", "はい", "예"),
    translation("build", "构建", "建置", "ビルド", "빌드"),
    translation("container", "容器", "容器", "コンテナ", "컨테이너"),
    translation("image", "镜像", "映像檔", "イメージ", "이미지"),
    translation("item", "项目", "項目", "項目", "항목"),
    translation("machine", "虚拟机", "虛擬機器", "マシン", "머신"),
    translation("network", "网络", "網路", "ネットワーク", "네트워크"),
    translation("registry", "镜像仓库", "映像檔登錄庫", "レジストリ", "레지스트리"),
    translation("system item", "系统项目", "系統項目", "システム項目", "시스템 항목"),
    translation("volume", "存储卷", "儲存卷宗", "ボリューム", "볼륨"),
    translation("Application support", "应用支持数据", "應用程式支援資料", "Application Support", "응용 프로그램 지원 데이터"),
    translation("Checked Rosetta run", "已检查的 Rosetta 运行", "已檢查的 Rosetta 執行", "Rosetta確認済み実行", "Rosetta 확인 실행"),
    translation("Capabilities", "功能", "功能", "機能", "기능"),
    translation("Close", "关闭", "關閉", "閉じる", "닫기"),
    translation("Close failed — session state unchanged", "关闭失败——会话状态未更改", "關閉失敗——工作階段狀態未變更", "終了できませんでした — セッション状態は変更されていません", "닫지 못했습니다 — 세션 상태는 변경되지 않았습니다"),
    translation("Code in a container", "在容器中编写代码", "在容器中撰寫程式碼", "コンテナ内で開発", "컨테이너에서 코딩"),
    translation("Compatibility", "兼容性", "相容性", "互換性", "호환성"),
    translation("Configure", "配置", "設定", "設定", "구성"),
    translation("Configure %@", "配置 %@", "設定 %@", "%@を設定", "%@ 구성"),
    translation("Configuration", "配置", "設定", "設定", "구성"),
    translation("Connected", "已连接", "已連線", "接続済み", "연결됨"),
    translation("Create a persistent Linux machine with sharing and nesting disabled.", "创建持久化 Linux 虚拟机，默认关闭共享和嵌套虚拟化。", "建立持久化 Linux 虛擬機器，預設關閉共享和巢狀虛擬化。", "共有とネストされた仮想化を無効にした永続Linuxマシンを作成します。", "공유와 중첩 가상화를 끈 영구 Linux 머신을 만듭니다."),
    translation("Defaults & Templates", "默认值与模板", "預設值與範本", "既定値とテンプレート", "기본값 및 템플릿"),
    translation("Development workspace", "开发工作区", "開發工作區", "開発ワークスペース", "개발 작업 공간"),
    translation("Detached — workload keeps running", "已分离——工作负载继续运行", "已中斷連線——工作負載會繼續執行", "デタッチ済み — ワークロードは実行を継続します", "분리됨 — 워크로드는 계속 실행됩니다"),
    translation("DNS resolver", "DNS 解析器", "DNS 解析器", "DNSリゾルバ", "DNS 리졸버"),
    translation("Download cache", "下载缓存", "下載快取", "ダウンロードキャッシュ", "다운로드 캐시"),
    translation("Downloaded package", "已下载的软件包", "已下載的套件", "ダウンロード済みパッケージ", "다운로드한 패키지"),
    translation("Fast foreground run", "快速前台运行", "快速前景執行", "高速フォアグラウンド実行", "빠른 포그라운드 실행"),
    translation("Home sharing", "个人文件夹共享", "個人專屬資料夾共享", "ホーム共有", "홈 공유"),
    translation("Home sharing disabled during creation", "创建时关闭个人文件夹共享", "建立時關閉個人專屬資料夾共享", "作成時はホーム共有を無効化", "생성 중 홈 공유 비활성화"),
    translation("Home sharing uses a one-time consent and is never enabled implicitly.", "个人文件夹共享使用一次性同意，绝不会被隐式启用。", "個人專屬資料夾共享使用一次性同意，絕不會被隱式啟用。", "ホーム共有には1回限りの同意を使用し、暗黙に有効になることはありません。", "홈 공유에는 일회성 동의를 사용하며 암시적으로 활성화되지 않습니다."),
    translation("Intel workload", "Intel 工作负载", "Intel 工作負載", "Intelワークロード", "Intel 워크로드"),
    translation("Interactive shell", "交互式 Shell", "互動式 Shell", "対話型シェル", "대화형 셸"),
    translation("Installed payload", "已安装载荷", "已安裝承載內容", "インストール済みペイロード", "설치된 페이로드"),
    translation("Installer receipt", "安装器收据", "安裝器收據", "インストーラレシート", "설치 프로그램 영수증"),
    translation("Keep database files in a named volume and stop gracefully.", "将数据库文件保存在命名存储卷中，并优雅停止。", "將資料庫檔案保存在具名儲存卷宗中，並正常停止。", "データベースファイルを名前付きボリュームに保持し、正常に停止します。", "데이터베이스 파일을 이름 있는 볼륨에 보관하고 정상적으로 중지합니다."),
    translation("Linux machine", "Linux 虚拟机", "Linux 虛擬機器", "Linuxマシン", "Linux 머신"),
    translation("Launch service", "启动服务", "啟動服務", "起動サービス", "시작 서비스"),
    translation("Local database", "本地数据库", "本機資料庫", "ローカルデータベース", "로컬 데이터베이스"),
    translation("Local web endpoint", "本地 Web 端点", "本機 Web 端點", "ローカルWebエンドポイント", "로컬 웹 엔드포인트"),
    translation("Maximum isolation", "最大程度隔离", "最高程度隔離", "最大限の分離", "최대 격리"),
    translation("Memory", "内存", "記憶體", "メモリ", "메모리"),
    translation("Mount one selected project folder into an isolated workspace.", "将一个选定的项目文件夹挂载到隔离工作区。", "將一個選取的專案資料夾掛載到隔離工作區。", "選択したプロジェクトフォルダを分離されたワークスペースにマウントします。", "선택한 프로젝트 폴더 하나를 격리된 작업 공간에 마운트합니다."),
    translation("Nested virtualization", "嵌套虚拟化", "巢狀虛擬化", "ネストされた仮想化", "중첩 가상화"),
    translation("Nested virtualization disabled during creation", "创建时关闭嵌套虚拟化", "建立時關閉巢狀虛擬化", "作成時はネストされた仮想化を無効化", "생성 중 중첩 가상화 비활성화"),
    translation("New Machine", "新建虚拟机", "新增虛擬機器", "新規マシン", "새 머신"),
    translation("Open the image's supported shell and remove the container on exit.", "打开镜像支持的 Shell，并在退出时移除容器。", "開啟映像檔支援的 Shell，並在結束時移除容器。", "イメージが対応するシェルを開き、終了時にコンテナを削除します。", "이미지가 지원하는 셸을 열고 종료할 때 컨테이너를 제거합니다."),
    translation("Off", "关闭", "關閉", "オフ", "끔"),
    translation("On", "开启", "開啟", "オン", "켬"),
    translation("Packet filter", "数据包过滤器", "封包篩選器", "パケットフィルタ", "패킷 필터"),
    translation("Persistent VM workspace", "持久化虚拟机工作区", "持久化虛擬機器工作區", "永続VMワークスペース", "영구 VM 작업 공간"),
    translation("Persistent local data", "持久化本地数据", "持久化本機資料", "永続ローカルデータ", "영구 로컬 데이터"),
    translation("Preferences", "偏好设置", "偏好設定", "環境設定", "환경설정"),
    translation("Reader task active", "读取任务正在运行", "讀取工作正在執行", "読み取りタスク実行中", "읽기 작업 활성"),
    translation("Reader task stopped", "读取任务已停止", "讀取工作已停止", "読み取りタスク停止", "읽기 작업 중지됨"),
    translation("Registry credential", "镜像仓库凭据", "映像檔登錄庫憑證", "レジストリ認証情報", "레지스트리 자격 증명"),
    translation("Resource table", "资源表格", "資源表格", "リソーステーブル", "리소스 표"),
    translation("Resources", "资源", "資源", "リソース", "리소스"),
    translation("Refresh after the runtime is available.", "运行时可用后请刷新。", "執行階段可用後請重新整理。", "ランタイムが使用可能になってから更新してください。", "런타임을 사용할 수 있게 된 후 새로 고치십시오."),
    translation("Restricted workload", "受限工作负载", "受限工作負載", "制限付きワークロード", "제한된 워크로드"),
    translation("Rollback point", "回滚点", "回復點", "ロールバックポイント", "롤백 지점"),
    translation("Runtime process", "运行时进程", "執行階段程序", "ランタイムプロセス", "런타임 프로세스"),
    translation("Runtime-owned directory", "运行时所属目录", "執行階段所屬目錄", "ランタイム管理ディレクトリ", "런타임 소유 디렉터리"),
    translation("Save", "保存", "儲存", "保存", "저장"),
    translation("Run a background service bound only to localhost by default.", "运行默认仅绑定到 localhost 的后台服务。", "執行預設僅綁定到 localhost 的背景服務。", "既定でlocalhostのみにバインドするバックグラウンドサービスを実行します。", "기본적으로 localhost에만 바인딩되는 백그라운드 서비스를 실행합니다."),
    translation("Run an amd64 Linux image only after Rosetta compatibility checks pass.", "仅在通过 Rosetta 兼容性检查后运行 amd64 Linux 镜像。", "僅在通過 Rosetta 相容性檢查後執行 amd64 Linux 映像檔。", "Rosetta互換性確認に合格した後でのみamd64 Linuxイメージを実行します。", "Rosetta 호환성 검사를 통과한 뒤에만 amd64 Linux 이미지를 실행합니다."),
    translation("Run once", "运行一次", "執行一次", "1回実行", "한 번 실행"),
    translation("Runtime Updates", "运行时更新", "執行階段更新", "ランタイム更新", "런타임 업데이트"),
    translation("Search builds", "搜索构建", "搜尋建置", "ビルドを検索", "빌드 검색"),
    translation("Search containers", "搜索容器", "搜尋容器", "コンテナを検索", "컨테이너 검색"),
    translation("Search images", "搜索镜像", "搜尋映像檔", "イメージを検索", "이미지 검색"),
    translation("Search machines", "搜索虚拟机", "搜尋虛擬機器", "マシンを検索", "머신 검색"),
    translation("Search networks", "搜索网络", "搜尋網路", "ネットワークを検索", "네트워크 검색"),
    translation("Search registries", "搜索镜像仓库", "搜尋映像檔登錄庫", "レジストリを検索", "레지스트리 검색"),
    translation("Search resources", "搜索资源", "搜尋資源", "リソースを検索", "리소스 검색"),
    translation("Search system resources", "搜索系统资源", "搜尋系統資源", "システムリソースを検索", "시스템 리소스 검색"),
    translation("Search volumes", "搜索存储卷", "搜尋儲存卷宗", "ボリュームを検索", "볼륨 검색"),
    translation("Settings content", "设置内容", "設定內容", "設定内容", "설정 내용"),
    translation("Share home folder read-only", "以只读方式共享个人文件夹", "以唯讀方式共享個人專屬資料夾", "ホームフォルダを読み取り専用で共有", "홈 폴더를 읽기 전용으로 공유"),
    translation("Standard error", "标准错误", "標準錯誤", "標準エラー", "표준 오류"),
    translation("Standard output", "标准输出", "標準輸出", "標準出力", "표준 출력"),
    translation("Start", "启动", "啟動", "起動", "시작"),
    translation("CPU cores", "CPU 核心", "CPU 核心", "CPUコア", "CPU 코어"),
    translation("Start one container in the foreground with conservative resources.", "使用保守的资源配置在前台启动一个容器。", "使用保守的資源設定在前景啟動一個容器。", "控えめなリソース設定で1つのコンテナをフォアグラウンド起動します。", "보수적인 리소스 설정으로 컨테이너 하나를 포그라운드에서 시작합니다."),
    translation("Stop", "停止", "停止", "停止", "중지"),
    translation("Temporary shell session", "临时 Shell 会话", "暫時 Shell 工作階段", "一時シェルセッション", "임시 셸 세션"),
    translation("Terminated with SIG%@", "已通过 SIG%@ 终止", "已透過 SIG%@ 終止", "SIG%@で終了", "SIG%@로 종료됨"),
    translation("Test fixture", "测试夹具", "測試資料", "テストフィクスチャ", "테스트 픽스처"),
    translation("Use a read-only filesystem with capabilities and networking removed.", "使用只读文件系统，并移除权限能力和网络。", "使用唯讀檔案系統，並移除權限能力和網路。", "読み取り専用ファイルシステムを使用し、ケイパビリティとネットワークを削除します。", "읽기 전용 파일 시스템을 사용하고 권한 기능과 네트워크를 제거합니다."),
    translation("Use Configure after creation to enable either capability with explicit consent.", "创建后使用“配置”，在明确同意后启用任一功能。", "建立後使用「設定」，在明確同意後啟用任一功能。", "作成後に「設定」を使用し、明示的な同意のもとで各機能を有効にしてください。", "생성 후 구성을 사용하여 명시적으로 동의한 뒤 각 기능을 활성화하십시오."),
    translation("Web service", "Web 服务", "Web 服務", "Webサービス", "웹 서비스"),
    translation("Application update %@ is available", "MacContainer 应用更新 %@ 可用", "MacContainer 應用程式更新 %@ 可用", "MacContainerアプリのアップデート%@を利用できます", "MacContainer 앱 업데이트 %@을(를) 사용할 수 있습니다"),
    translation("Application update check failed", "应用更新检查失败", "應用程式更新檢查失敗", "アプリのアップデート確認に失敗しました", "앱 업데이트 확인 실패"),
    translation("Application update service is not ready", "应用更新服务尚未就绪", "應用程式更新服務尚未就緒", "アプリのアップデートサービスは準備中です", "앱 업데이트 서비스를 사용할 준비가 되지 않았습니다"),
    translation("Application updates", "应用更新", "應用程式更新", "アプリのアップデート", "앱 업데이트"),
    translation("Application updates are signed and handled separately from Apple container runtime updates, which always require compatibility approval.", "应用更新经过签名并与 Apple container 运行时更新分开处理；运行时更新始终需要通过兼容性批准。", "應用程式更新經過簽章並與 Apple container 執行階段更新分開處理；執行階段更新一律需要通過相容性核准。", "アプリのアップデートは署名され、Apple containerランタイムの更新とは別に処理されます。ランタイムの更新には常に互換性の承認が必要です。", "앱 업데이트는 서명되며 Apple container 런타임 업데이트와 별도로 처리됩니다. 런타임 업데이트에는 항상 호환성 승인이 필요합니다."),
    translation("Automatically check for signed application updates", "自动检查已签名的应用更新", "自動檢查已簽章的應用程式更新", "署名済みアプリのアップデートを自動確認", "서명된 앱 업데이트 자동 확인"),
    translation("Check for Application Updates", "检查应用更新", "檢查應用程式更新", "アプリのアップデートを確認", "앱 업데이트 확인"),
    translation("Checking for application updates…", "正在检查应用更新…", "正在檢查應用程式更新…", "アプリのアップデートを確認中…", "앱 업데이트 확인 중…"),
    translation("Continue Update and Relaunch", "继续更新并重新启动", "繼續更新並重新啟動", "アップデートを続行して再起動", "업데이트 계속 및 다시 실행"),
    translation("MacContainer is up to date", "MacContainer 已是最新版本", "MacContainer 已是最新版本", "MacContainerは最新です", "MacContainer가 최신 상태입니다"),
    translation("Ready to install and relaunch", "可以安装并重新启动", "可以安裝並重新啟動", "インストールして再起動できます", "설치 후 다시 실행할 준비가 되었습니다"),
    translation("Save or discard the current draft before relaunching", "重新启动前请保存或放弃当前草稿", "重新啟動前請儲存或捨棄目前的草稿", "再起動する前に現在の下書きを保存または破棄してください", "다시 실행하기 전에 현재 초안을 저장하거나 삭제하십시오"),
    translation("Status", "状态", "狀態", "状態", "상태"),
    translation("Wait for active operations and terminals to finish before relaunching", "请等待活动操作和终端结束后再重新启动", "請等待進行中的操作和終端機結束後再重新啟動", "実行中の操作とターミナルが終了してから再起動してください", "진행 중인 작업과 터미널이 끝난 후 다시 실행하십시오"),
    translation("Activity", "活动", "活動", "アクティビティ", "활동"),
    translation("Affected resources", "受影响的资源", "受影響的資源", "影響を受けるリソース", "영향을 받는 리소스"),
    translation("Built in", "内置", "內建", "組み込み", "기본 제공"),
    translation("Control", "控制", "控制", "制御", "제어"),
    translation("Custom", "自定义", "自訂", "カスタム", "사용자 지정"),
    translation("Diagnostics", "诊断", "診斷", "診断", "진단"),
    translation("Effective values", "生效值", "生效值", "適用される値", "적용 값"),
    translation("Experience", "体验", "體驗", "操作環境", "사용 환경"),
    translation("Generated values", "生成值", "產生的值", "生成された値", "생성된 값"),
    translation("Identity", "身份", "身分", "ID情報", "ID 정보"),
    translation("Import blocked", "导入已阻止", "已阻擋輸入", "読み込みをブロックしました", "가져오기 차단됨"),
    translation("Import preview", "导入预览", "輸入預覽", "読み込みプレビュー", "가져오기 미리보기"),
    translation("Install Apple container", "安装 Apple container", "安裝 Apple container", "Apple containerをインストール", "Apple container 설치"),
    translation("Manage", "管理", "管理", "管理", "관리"),
    translation("Navigate", "导航", "導覽", "移動", "탐색"),
    translation("No Activities", "暂无活动", "沒有活動", "アクティビティなし", "활동 없음"),
    translation("Nothing Selected", "未选择任何项目", "未選取任何項目", "何も選択されていません", "선택한 항목 없음"),
    translation("Outcome", "结果", "結果", "結果", "결과"),
    translation("Policy", "策略", "政策", "ポリシー", "정책"),
    translation("Recovery", "恢复", "復原", "復旧", "복구"),
    translation("Result", "结果", "結果", "結果", "결과"),
    translation("Running through the native runtime bridge…", "正在通过原生运行时桥接执行…", "正在透過原生執行階段橋接執行…", "ネイティブランタイムブリッジで実行中…", "네이티브 런타임 브리지를 통해 실행 중…"),
    translation("Starting through the native runtime bridge…", "正在通过原生运行时桥接启动…", "正在透過原生執行階段橋接啟動…", "ネイティブランタイムブリッジで起動中…", "네이티브 런타임 브리지를 통해 시작 중…"),
    translation("Remove Apple container", "移除 Apple container", "移除 Apple container", "Apple containerを削除", "Apple container 제거"),
    translation("Required choices", "必选项", "必要選項", "必須の選択", "필수 선택 사항"),
    translation("Required probe domains", "必需的探测域", "必要的探測領域", "必須プローブ領域", "필수 검사 도메인"),
    translation("Safe defaults", "安全默认值", "安全預設值", "安全な既定値", "안전한 기본값"),
    translation("Safety", "安全", "安全性", "安全性", "안전"),
    translation("State", "状态", "狀態", "状態", "상태"),
    translation("Template review unavailable", "模板检查不可用", "無法檢查範本", "テンプレートを確認できません", "템플릿 검토를 사용할 수 없음"),
    translation("Templates", "模板", "範本", "テンプレート", "템플릿"),
    translation("1. Choose scenario", "1. 选择场景", "1. 選擇情境", "1. シナリオを選択", "1. 시나리오 선택"),
    translation("2. Configure", "2. 配置", "2. 設定", "2. 設定", "2. 구성"),
    translation("8080", "8080", "8080", "8080", "8080"),
    translation("A clear cause, a redacted diagnostic, and safe next actions — without exposing credentials.", "提供明确原因、已脱敏诊断和安全的后续操作，不暴露凭据。", "提供明確原因、已遮蔽診斷和安全的後續操作，不會洩漏憑證。", "認証情報を公開せず、明確な原因、秘匿化された診断、安全な次の操作を示します。", "자격 증명을 노출하지 않고 명확한 원인, 삭제 처리된 진단, 안전한 다음 조치를 제공합니다."),
    translation("Absolute path", "绝对路径", "絕對路徑", "絶対パス", "절대 경로"),
    translation("Accessibility audit fixture browser", "辅助功能审计夹具浏览器", "輔助使用稽核測試資料瀏覽器", "アクセシビリティ監査フィクスチャブラウザ", "손쉬운 사용 감사 픽스처 브라우저"),
    translation("Accessibility fixture navigation", "辅助功能夹具导航", "輔助使用測試資料導覽", "アクセシビリティフィクスチャのナビゲーション", "손쉬운 사용 픽스처 탐색"),
    translation("Action", "操作", "動作", "操作", "작업"),
    translation("Activity Center records progress and item-level outcomes.", "活动中心会记录进度和每个项目的结果。", "活動中心會記錄進度和每個項目的結果。", "アクティビティセンターには進行状況と項目別の結果が記録されます。", "활동 센터에 진행 상황과 항목별 결과가 기록됩니다."),
    translation("Activity details", "活动详情", "活動詳細資訊", "アクティビティの詳細", "활동 세부 정보"),
    translation("Administrator approval appears only after download, signature verification, and review.", "仅在完成下载、签名验证和检查后才会请求管理员批准。", "只有在完成下載、簽章驗證和檢查後才會要求管理員核准。", "ダウンロード、署名検証、確認が完了した後にのみ管理者の承認を求めます。", "다운로드, 서명 검증, 검토가 끝난 후에만 관리자 승인을 요청합니다."),
    translation("Administrator approval is requested only when an install or upgrade actually begins.", "仅在安装或升级真正开始时才会请求管理员批准。", "只有在安裝或升級實際開始時才會要求管理員核准。", "インストールまたはアップグレードを実際に開始するときだけ管理者の承認を求めます。", "설치 또는 업그레이드가 실제로 시작될 때만 관리자 승인을 요청합니다."),
    translation("Administrator approval is requested only when installation begins.", "仅在安装开始时才会请求管理员批准。", "只有在安裝開始時才會要求管理員核准。", "インストール開始時にのみ管理者の承認を求めます。", "설치가 시작될 때만 관리자 승인을 요청합니다."),
    translation("Administrator approval required", "需要管理员批准", "需要管理員核准", "管理者の承認が必要です", "관리자 승인이 필요합니다"),
    translation("Allow MacContainer in System Settings > General > Login Items, then check again.", "请在系统设置 > 通用 > 登录项中允许 MacContainer，然后重新检查。", "請在系統設定 > 一般 > 登入項目中允許 MacContainer，然後重新檢查。", "システム設定 > 一般 > ログイン項目でMacContainerを許可してから、再確認してください。", "시스템 설정 > 일반 > 로그인 항목에서 MacContainer를 허용한 후 다시 확인하십시오."),
    translation("Open Login Items Settings", "打开登录项设置", "開啟登入項目設定", "ログイン項目設定を開く", "로그인 항목 설정 열기"),
    translation("Check approval", "检查批准状态", "檢查核准狀態", "承認を確認", "승인 확인"),
    translation("Installation stopped safely", "安装已安全停止", "安裝已安全停止", "インストールは安全に停止しました", "설치가 안전하게 중지되었습니다"),
    translation("Inventory refresh runs immediately before removal", "移除前会立即刷新清单", "移除前會立即重新整理清單", "削除直前にインベントリを更新します", "제거 직전에 목록을 새로 고칩니다"),
    translation("Uninstall complete", "卸载完成", "解除安裝完成", "アンインストール完了", "제거 완료"),
    translation("No Apple container residue detected.", "未检测到 Apple container 残留。", "未偵測到 Apple container 殘留。", "Apple containerの残留項目は検出されませんでした。", "Apple container 잔여 항목이 감지되지 않았습니다."),
    translation("No success was recorded. Restore administrator access and retry the fresh audit.", "未记录成功结果。请恢复管理员权限并重新运行最新审计。", "未記錄成功結果。請恢復管理員權限並重新執行最新稽核。", "成功は記録されていません。管理者アクセスを回復し、最新の監査を再試行してください。", "성공 상태가 기록되지 않았습니다. 관리자 접근 권한을 복원하고 최신 감사를 다시 시도하십시오."),
    translation("Advanced", "高级", "進階", "詳細", "고급"),
    translation("Advanced controls remain one click away and preserve every value you entered.", "高级控制始终只需一次点击，并会保留你输入的所有值。", "進階控制隨時只需按一下，並會保留你輸入的所有值。", "詳細設定はいつでも1クリックで開け、入力した値はすべて保持されます。", "고급 제어는 언제든 한 번의 클릭으로 열 수 있으며 입력한 모든 값을 유지합니다."),
    translation("Apache License 2.0", "Apache 许可证 2.0", "Apache 授權條款 2.0", "Apache License 2.0", "Apache License 2.0"),
    translation("Apple container 1.1.0", "Apple container 1.1.0", "Apple container 1.1.0", "Apple container 1.1.0", "Apple container 1.1.0"),
    translation("Apple container · compatible", "Apple container · 兼容", "Apple container · 相容", "Apple container · 互換性確認済み", "Apple container · 호환됨"),
    translation("Audit", "审计", "稽核", "監査", "감사"),
    translation("Automatic installation is off until you opt in.", "在你主动启用前，自动安装保持关闭。", "在你主動啟用前，自動安裝會保持關閉。", "明示的に有効にするまで自動インストールは行われません。", "직접 사용 설정하기 전까지 자동 설치는 꺼져 있습니다."),
    translation("Automatically check for signed runtime updates", "自动检查已签名的运行时更新", "自動檢查已簽章的執行階段更新", "署名済みランタイム更新を自動確認", "서명된 런타임 업데이트 자동 확인"),
    translation("Automatically install only compatibility-approved updates", "仅自动安装通过兼容性批准的更新", "只自動安裝通過相容性核准的更新", "互換性が承認された更新だけを自動インストール", "호환성이 승인된 업데이트만 자동 설치"),
    translation("Automatically install updates that pass compatibility checks", "自动安装通过兼容性检查的更新", "自動安裝通過相容性檢查的更新", "互換性確認に合格した更新を自動インストール", "호환성 검사를 통과한 업데이트 자동 설치"),
    translation("Approved update action", "已批准更新的操作", "已核准更新的動作", "承認済み更新の操作", "승인된 업데이트 작업"),
    translation("Check only", "仅检查", "僅檢查", "確認のみ", "확인만"),
    translation("Download and notify", "下载并通知", "下載並通知", "ダウンロードして通知", "다운로드 후 알림"),
    translation("Automatic when idle", "空闲时自动安装", "閒置時自動安裝", "アイドル時に自動", "유휴 상태에서 자동 설치"),
    translation("Reports reviewed updates and waits for an explicit install request.", "报告已审查的更新，并等待你明确请求安装。", "回報已審查的更新，並等待你明確要求安裝。", "レビュー済みの更新を通知し、明示的なインストール要求を待ちます。", "검토된 업데이트를 알리고 명시적인 설치 요청을 기다립니다."),
    translation("Downloads and verifies an approved package, then waits for your review.", "下载并验证已批准的软件包，然后等待你检查。", "下載並驗證已核准的套件，然後等待你檢查。", "承認済みパッケージをダウンロードして検証し、確認を待ちます。", "승인된 패키지를 다운로드하고 검증한 뒤 검토를 기다립니다."),
    translation("Installs only compatibility-approved updates after explicit consent when all work is idle.", "仅在你明确同意且所有任务空闲时安装通过兼容性批准的更新。", "只有在你明確同意且所有工作閒置時，才會安裝通過相容性核准的更新。", "明示的な同意があり、すべての処理がアイドルのときだけ、互換性承認済みの更新をインストールします。", "명시적으로 동의하고 모든 작업이 유휴 상태일 때만 호환성이 승인된 업데이트를 설치합니다."),
    translation("Background checks require approval in System Settings", "后台检查需要在系统设置中批准", "背景檢查需要在系統設定中核准", "バックグラウンド確認にはシステム設定での承認が必要です", "백그라운드 확인은 시스템 설정에서 승인이 필요합니다"),
    translation("Background update checks are enabled", "后台更新检查已启用", "背景更新檢查已啟用", "バックグラウンドの更新確認は有効です", "백그라운드 업데이트 확인이 사용 설정되었습니다"),
    translation("Background update checks are not registered", "后台更新检查尚未注册", "背景更新檢查尚未註冊", "バックグラウンドの更新確認が登録されていません", "백그라운드 업데이트 확인이 등록되지 않았습니다"),
    translation("Background update registration could not be verified", "无法验证后台更新注册状态", "無法驗證背景更新註冊狀態", "バックグラウンド更新の登録を確認できませんでした", "백그라운드 업데이트 등록을 확인할 수 없습니다"),
    translation("Open System Settings", "打开系统设置", "開啟系統設定", "システム設定を開く", "시스템 설정 열기"),
    translation("Update preference could not be saved; the previous safe setting was restored.", "无法保存更新偏好设置；已恢复先前的安全设置。", "無法儲存更新偏好設定；已恢復先前的安全設定。", "更新設定を保存できなかったため、以前の安全な設定に戻しました。", "업데이트 환경설정을 저장할 수 없어 이전의 안전한 설정으로 복원했습니다."),
    translation("Runtime update check was cancelled", "运行时更新检查已取消", "執行階段更新檢查已取消", "ランタイム更新の確認をキャンセルしました", "런타임 업데이트 확인이 취소되었습니다"),
    translation("Runtime update check could not be completed", "无法完成运行时更新检查", "無法完成執行階段更新檢查", "ランタイム更新の確認を完了できませんでした", "런타임 업데이트 확인을 완료할 수 없습니다"),
    translation("No reviewed runtime update candidate is available", "没有可用的已审查运行时更新", "沒有可用的已審查執行階段更新", "レビュー済みのランタイム更新候補はありません", "검토된 런타임 업데이트 후보가 없습니다"),
    translation("Runtime update service is offline — check your connection and retry", "运行时更新服务离线——请检查网络连接后重试", "執行階段更新服務離線——請檢查網路連線後重試", "ランタイム更新サービスはオフラインです。接続を確認して再試行してください", "런타임 업데이트 서비스가 오프라인입니다. 연결을 확인한 후 다시 시도하십시오"),
    translation("Runtime update service is temporarily rate limited — retry later", "运行时更新服务暂时受到速率限制——请稍后重试", "執行階段更新服務暫時受到速率限制——請稍後重試", "ランタイム更新サービスは一時的にレート制限されています。後で再試行してください", "런타임 업데이트 서비스가 일시적으로 요청 제한 상태입니다. 나중에 다시 시도하십시오"),
    translation("Available scenario templates", "可用场景模板", "可用的情境範本", "利用可能なシナリオテンプレート", "사용 가능한 시나리오 템플릿"),
    translation("Back", "返回", "返回", "戻る", "뒤로"),
    translation("Both high-impact capabilities remain off unless you explicitly enable them.", "除非你明确启用，否则这两项高影响功能都保持关闭。", "除非你明確啟用，否則這兩項高影響功能都會保持關閉。", "明示的に有効にしない限り、影響の大きい2つの機能は無効のままです。", "명시적으로 사용 설정하지 않으면 영향이 큰 두 기능은 모두 꺼진 상태로 유지됩니다."),
    translation("Bytes", "字节", "位元組", "バイト", "바이트"),
    translation("CPU and memory are recommended from this Mac, image metadata, and the selected scenario.", "CPU 和内存建议根据此 Mac、镜像元数据和所选场景生成。", "CPU 和記憶體建議會依此 Mac、映像檔中繼資料和所選情境產生。", "CPUとメモリは、このMac、イメージのメタデータ、選択したシナリオに基づいて推奨されます。", "CPU와 메모리는 이 Mac, 이미지 메타데이터, 선택한 시나리오를 바탕으로 권장됩니다."),
    translation("Changed from Apple default", "已不同于 Apple 默认值", "已不同於 Apple 預設值", "Appleの既定値から変更", "Apple 기본값에서 변경됨"),
    translation("Choose a scenario template", "选择场景模板", "選擇情境範本", "シナリオテンプレートを選択", "시나리오 템플릿 선택"),
    translation("Choose an operation", "选择操作", "選擇操作", "操作を選択", "작업 선택"),
    translation("Choose an operation. Search the complete Apple container contract to configure a native action.", "请选择操作。搜索完整的 Apple container 合同以配置原生操作。", "請選擇操作。搜尋完整的 Apple container 合約以設定原生操作。", "操作を選択してください。Apple containerの完全な契約を検索してネイティブ操作を設定できます。", "작업을 선택하십시오. 전체 Apple container 계약을 검색하여 네이티브 작업을 구성할 수 있습니다."),
    translation("Choose an outcome. MacContainer fills in safe, host-aware defaults.", "选择目标，MacContainer 会填入安全且适配主机的默认值。", "選擇目標，MacContainer 會填入安全且符合主機狀況的預設值。", "目的を選ぶと、MacContainerがホスト環境に適した安全な既定値を入力します。", "목표를 선택하면 MacContainer가 호스트 환경에 맞는 안전한 기본값을 입력합니다."),
    translation("Clear operation search", "清除操作搜索", "清除操作搜尋", "操作検索を消去", "작업 검색 지우기"),
    translation("Compatibility gate passed", "已通过兼容性门禁", "已通過相容性關卡", "互換性ゲート合格", "호환성 게이트 통과"),
    translation("Complete means complete", "彻底卸载，不留残余", "完整解除安裝，不留殘餘", "完全なアンインストール", "완전한 제거"),
    translation("Complete simulated postflight", "完成模拟后置检查", "完成模擬後置檢查", "模擬ポストフライトを完了", "시뮬레이션 사후 검사 완료"),
    translation("Complete update check", "完成更新检查", "完成更新檢查", "更新確認を完了", "업데이트 확인 완료"),
    translation("Completely uninstall", "彻底卸载", "完整解除安裝", "完全にアンインストール", "완전히 제거"),
    translation("Configure the selected scenario", "配置所选场景", "設定所選情境", "選択したシナリオを設定", "선택한 시나리오 구성"),
    translation("Could not verify resolver cleanup", "无法验证解析器清理结果", "無法驗證解析器清理結果", "リゾルバのクリーンアップを確認できませんでした", "리졸버 정리를 확인할 수 없습니다"),
    translation("Create your first container", "创建第一个容器", "建立第一個容器", "最初のコンテナを作成", "첫 번째 컨테이너 만들기"),
    translation("Current automatic install setting: ", "当前自动安装设置：", "目前的自動安裝設定：", "現在の自動インストール設定: ", "현재 자동 설치 설정: "),
    translation("Data volume", "数据卷", "資料卷宗", "データボリューム", "데이터 볼륨"),
    translation("Delete", "删除", "刪除", "削除", "삭제"),
    translation("Detach", "分离", "中斷連線", "デタッチ", "분리"),
    translation("Direct interactive session", "直接交互会话", "直接互動工作階段", "直接対話セッション", "직접 대화형 세션"),
    translation("Disk impact: up to 420 MB", "磁盘占用：最多 420 MB", "磁碟占用：最多 420 MB", "ディスク使用量: 最大420 MB", "디스크 사용량: 최대 420MB"),
    translation("Done", "完成", "完成", "完了", "완료"),
    translation("Duplicate", "复制", "製作複本", "複製", "복제"),
    translation("Edit all parameters", "编辑所有参数", "編輯所有參數", "すべてのパラメータを編集", "모든 매개변수 편집"),
    translation("Eight built-in scenarios are immutable. Imported templates are migrated and checked for secrets.", "八个内置场景不可修改；导入的模板会经过迁移和敏感信息检查。", "八個內建情境不可修改；匯入的範本會經過移轉和機密資訊檢查。", "8つの組み込みシナリオは変更できません。読み込んだテンプレートは移行され、シークレットが検査されます。", "8개의 기본 제공 시나리오는 변경할 수 없습니다. 가져온 템플릿은 마이그레이션되고 비밀 정보 검사를 거칩니다."),
    translation("Email Matrix Religio support", "向 Matrix Religio 支持发送邮件", "傳送電子郵件給 Matrix Religio 支援團隊", "Matrix Religioサポートにメール", "Matrix Religio 지원팀에 이메일 보내기"),
    translation("Enable nested virtualization", "启用嵌套虚拟化", "啟用巢狀虛擬化", "ネストされた仮想化を有効にする", "중첩 가상화 사용"),
    translation("Enabled", "已启用", "已啟用", "有効", "사용"),
    translation("Errors that help you recover", "帮助你恢复的错误信息", "協助你復原的錯誤資訊", "復旧に役立つエラー", "복구를 돕는 오류"),
    translation("Every generated value, its source, and its difference from Apple defaults is shown below.", "下方会显示每个生成值、其来源以及与 Apple 默认值的差异。", "下方會顯示每個產生的值、其來源以及與 Apple 預設值的差異。", "生成されたすべての値、その出所、Appleの既定値との差異を以下に表示します。", "생성된 모든 값, 출처, Apple 기본값과의 차이를 아래에 표시합니다."),
    translation("Every owned artifact is inventoried again immediately before removal.", "移除前会立即重新清点每个归属本应用的项目。", "移除前會立即重新清點每個屬於本應用程式的項目。", "削除直前に、管理対象のすべての項目を再度棚卸しします。", "제거 직전에 앱이 소유한 모든 항목의 목록을 다시 확인합니다."),
    translation("Export", "导出", "輸出", "書き出す", "내보내기"),
    translation("Fail closed for unknown runtime versions", "未知运行时版本默认拒绝", "未知執行階段版本預設拒絕", "未知のランタイムバージョンを安全側で拒否", "알 수 없는 런타임 버전은 안전하게 차단"),
    translation("Fresh inventory: 15 owned artifact categories checked", "最新清单：已检查 15 类归属项目", "最新清單：已檢查 15 類所屬項目", "最新の棚卸し: 管理対象15カテゴリを確認済み", "최신 목록: 소유 항목 15개 범주 확인됨"),
    translation("Generated values remain fully editable in review.", "生成的值在检查阶段仍可全部编辑。", "產生的值在檢查階段仍可全部編輯。", "生成された値は確認画面ですべて編集できます。", "생성된 값은 검토 단계에서 모두 편집할 수 있습니다."),
    translation("Graceful stop: 30 seconds", "优雅停止：30 秒", "正常停止：30 秒", "正常停止: 30秒", "정상 종료: 30초"),
    translation("Host port", "主机端口", "主機連接埠", "ホストポート", "호스트 포트"),
    translation("ID", "ID", "ID", "ID", "ID"),
    translation("Image", "镜像", "映像檔", "イメージ", "이미지"),
    translation("Image reference", "镜像引用", "映像檔參照", "イメージ参照", "이미지 참조"),
    translation("Import", "导入", "輸入", "読み込む", "가져오기"),
    translation("Inspect", "检查", "檢查", "詳細を表示", "검사"),
    translation("Installing — compatibility postflight pending", "正在安装——等待兼容性后置检查", "正在安裝——等待相容性後置檢查", "インストール中 — 互換性ポストフライト待機中", "설치 중 — 호환성 사후 검사 대기 중"),
    translation("Installs, pulls, builds, and updates will appear here.", "安装、拉取、构建和更新活动会显示在这里。", "安裝、提取、建置和更新活動會顯示在這裡。", "インストール、取得、ビルド、更新がここに表示されます。", "설치, 가져오기, 빌드, 업데이트가 여기에 표시됩니다."),
    translation("Integer", "整数", "整數", "整数", "정수"),
    translation("Interactive container terminal", "交互式容器终端", "互動式容器終端機", "対話型コンテナターミナル", "대화형 컨테이너 터미널"),
    translation("Keeps images, volumes, configuration, and registry credentials.", "保留镜像、存储卷、配置和镜像仓库凭据。", "保留映像檔、儲存卷宗、設定和映像檔登錄庫憑證。", "イメージ、ボリューム、設定、レジストリ認証情報を保持します。", "이미지, 볼륨, 구성, 레지스트리 자격 증명을 유지합니다."),
    translation("Kind", "类型", "種類", "種類", "종류"),
    translation("MacContainer", "MacContainer", "MacContainer", "MacContainer", "MacContainer"),
    translation("Manage templates", "管理模板", "管理範本", "テンプレートを管理", "템플릿 관리"),
    translation("Name", "名称", "名稱", "名前", "이름"),
    translation("Native operation", "原生操作", "原生操作", "ネイティブ操作", "네이티브 작업"),
    translation("Network and DNS disabled", "网络和 DNS 已禁用", "網路和 DNS 已停用", "ネットワークとDNSは無効", "네트워크 및 DNS 비활성화됨"),
    translation("New…", "新建…", "新增…", "新規…", "새로 만들기…"),
    translation("No custom templates", "没有自定义模板", "沒有自訂範本", "カスタムテンプレートはありません", "사용자 지정 템플릿 없음"),
    translation("No daemon guessing. No hidden destructive action.", "不猜测守护进程状态，不隐藏破坏性操作。", "不猜測背景服務狀態，也不隱藏破壞性操作。", "デーモン状態を推測せず、破壊的な操作を隠しません。", "데몬 상태를 추측하지 않고 파괴적 작업을 숨기지 않습니다."),
    translation("No recent activity", "暂无最近活动", "沒有最近的活動", "最近のアクティビティはありません", "최근 활동 없음"),
    translation("No secrets detected. Save only after reviewing every value.", "未检测到敏感信息。请检查每个值后再保存。", "未偵測到機密資訊。請檢查每個值後再儲存。", "シークレットは検出されませんでした。すべての値を確認してから保存してください。", "비밀 정보가 감지되지 않았습니다. 모든 값을 검토한 후 저장하십시오."),
    translation("Open Activity Center", "打开活动中心", "開啟活動中心", "アクティビティセンターを開く", "활동 센터 열기"),
    translation("Open Template Library", "打开模板库", "開啟範本庫", "テンプレートライブラリを開く", "템플릿 보관함 열기"),
    translation("Operation", "操作", "操作", "操作", "작업"),
    translation("Operation catalog", "操作目录", "操作目錄", "操作カタログ", "작업 카탈로그"),
    translation("Owned artifact inventory", "归属项目清单", "所屬項目清單", "管理対象項目の一覧", "소유 항목 목록"),
    translation("Passwords, tokens, credentials, authorization data, and private temporary paths are redacted.", "密码、令牌、凭据、授权数据和私有临时路径均会脱敏。", "密碼、權杖、憑證、授權資料和私人暫存路徑都會遮蔽。", "パスワード、トークン、認証情報、認可データ、非公開の一時パスは秘匿化されます。", "암호, 토큰, 자격 증명, 권한 부여 데이터, 비공개 임시 경로는 삭제 처리됩니다."),
    translation("Path", "路径", "路徑", "パス", "경로"),
    translation("Re-create it from a template or backup if you need it again.", "如需再次使用，请从模板或备份重新创建。", "如需再次使用，請從範本或備份重新建立。", "再度必要になった場合は、テンプレートまたはバックアップから再作成してください。", "다시 필요하면 템플릿 또는 백업에서 다시 만드십시오."),
    translation("Re-run residue audit", "重新运行残留审计", "重新執行殘留項目稽核", "残留項目の監査を再実行", "잔여 항목 감사 다시 실행"),
    translation("Read-only root filesystem", "只读根文件系统", "唯讀根檔案系統", "読み取り専用ルートファイルシステム", "읽기 전용 루트 파일 시스템"),
    translation("Recommended", "推荐", "建議", "推奨", "권장"),
    translation("Recovery: retry the residue audit after restoring administrator access.", "恢复：恢复管理员权限后重试残留审计。", "復原：恢復管理員權限後重試殘留項目稽核。", "復旧: 管理者アクセスを回復してから残留項目の監査を再試行してください。", "복구: 관리자 접근 권한을 복원한 후 잔여 항목 감사를 다시 시도하십시오."),
    translation("Reduced motion: terminal output updates without decorative animation.", "减少动态效果：终端输出更新时不显示装饰动画。", "減少動態效果：終端機輸出更新時不顯示裝飾動畫。", "視差効果を減らす: 装飾的なアニメーションなしでターミナル出力を更新します。", "동작 줄이기: 장식 애니메이션 없이 터미널 출력을 업데이트합니다."),
    translation("Refresh", "刷新", "重新整理", "更新", "새로 고침"),
    translation("Remote clipboard, links, notifications, and title changes are blocked.", "已阻止远程剪贴板、链接、通知和标题更改。", "已阻擋遠端剪貼簿、連結、通知和標題變更。", "リモートのクリップボード、リンク、通知、タイトル変更はブロックされます。", "원격 클립보드, 링크, 알림, 제목 변경이 차단됩니다."),
    translation("Remove runtime, preserve container data", "移除运行时并保留容器数据", "移除執行階段並保留容器資料", "コンテナデータを保持してランタイムを削除", "컨테이너 데이터를 유지하고 런타임 제거"),
    translation("Retain redacted compatibility and rollback diagnostics", "保留已脱敏的兼容性与回滚诊断", "保留已遮蔽的相容性與回復診斷", "秘匿化した互換性とロールバック診断を保持", "삭제 처리된 호환성 및 롤백 진단 유지"),
    translation("Review", "检查", "檢查", "確認", "검토"),
    translation("Review all values", "检查所有值", "檢查所有值", "すべての値を確認", "모든 값 검토"),
    translation("Risk", "风险", "風險", "リスク", "위험"),
    translation("Rollback point: 1.0.0 · verified · retained", "回滚点：1.0.0 · 已验证 · 已保留", "回復點：1.0.0 · 已驗證 · 已保留", "ロールバックポイント: 1.0.0 · 検証済み · 保持", "롤백 지점: 1.0.0 · 검증됨 · 유지됨"),
    translation("Rosetta is required and will be checked before run.", "需要 Rosetta，运行前会进行检查。", "需要 Rosetta，執行前會進行檢查。", "Rosettaが必要です。実行前に確認されます。", "Rosetta가 필요하며 실행 전에 확인합니다."),
    translation("Run", "运行", "執行", "実行", "실행"),
    translation("Run Apple containers with native controls, safe defaults, and no Terminal setup.", "使用原生控制和安全默认值运行 Apple 容器，无需配置终端。", "使用原生控制和安全預設值執行 Apple 容器，不必設定終端機。", "ネイティブ操作と安全な既定値でAppleコンテナを実行。ターミナル設定は不要です。", "네이티브 제어와 안전한 기본값으로 Apple 컨테이너를 실행하며 터미널 설정이 필요 없습니다."),
    translation("Runtime", "运行时", "執行階段", "ランタイム", "런타임"),
    translation("Runtime checks download only signed catalog metadata and packages you approve.", "运行时检查只会下载已签名的目录元数据和你批准的软件包。", "執行階段檢查只會下載已簽章的目錄中繼資料和你核准的套件。", "ランタイム確認では、署名済みカタログメタデータと承認したパッケージだけをダウンロードします。", "런타임 검사는 서명된 카탈로그 메타데이터와 사용자가 승인한 패키지만 다운로드합니다."),
    translation("Runtime health and the safest next action, at a glance.", "一目了然地查看运行时健康状态和最安全的后续操作。", "一目了然地查看執行階段健康狀態和最安全的後續操作。", "ランタイムの状態と最も安全な次の操作を一目で確認できます。", "런타임 상태와 가장 안전한 다음 조치를 한눈에 확인할 수 있습니다."),
    translation("Runtime ready", "运行时已就绪", "執行階段已就緒", "ランタイム使用可能", "런타임 준비됨"),
    translation("Runtime removed; user data preserved", "运行时已移除；用户数据已保留", "執行階段已移除；使用者資料已保留", "ランタイムを削除し、ユーザーデータを保持しました", "런타임이 제거되었으며 사용자 데이터는 유지되었습니다"),
    translation("Runtime summary", "运行时摘要", "執行階段摘要", "ランタイムの概要", "런타임 요약"),
    translation("SHA-256 digest verified", "SHA-256 摘要已验证", "SHA-256 摘要已驗證", "SHA-256ダイジェスト検証済み", "SHA-256 다이제스트 검증됨"),
    translation("Safe by default", "默认安全", "預設安全", "安全な既定値", "기본적으로 안전"),
    translation("Scenario template builder", "场景模板生成器", "情境範本建立器", "シナリオテンプレートビルダー", "시나리오 템플릿 빌더"),
    translation("Search 61 operations", "搜索 61 项操作", "搜尋 61 項操作", "61件の操作を検索", "61개 작업 검색"),
    translation("Search operations", "搜索操作", "搜尋操作", "操作を検索", "작업 검색"),
    translation("Select next application language", "选择下一种应用语言", "選擇下一種應用程式語言", "次のアプリ言語を選択", "다음 앱 언어 선택"),
    translation("Search the complete Apple container contract to configure a native action.", "搜索完整的 Apple container 合同以配置原生操作。", "搜尋完整的 Apple container 合約以設定原生操作。", "Apple containerの完全な契約を検索してネイティブ操作を設定します。", "전체 Apple container 계약을 검색하여 네이티브 작업을 구성합니다."),
    translation("Seconds", "秒", "秒", "秒", "초"),
    translation("Settings categories", "设置类别", "設定類別", "設定カテゴリ", "설정 범주"),
    translation("Share my home folder", "共享我的个人文件夹", "共享我的個人專屬資料夾", "ホームフォルダを共有", "내 홈 폴더 공유"),
    translation("Signed by Apple · SHA-256 verified", "Apple 签名 · SHA-256 已验证", "Apple 簽章 · SHA-256 已驗證", "Apple署名 · SHA-256検証済み", "Apple 서명 · SHA-256 검증됨"),
    translation("Signer: Apple Inc. - Containerization (UPBK2H6LZM)", "签名方：Apple Inc. - Containerization (UPBK2H6LZM)", "簽章者：Apple Inc. - Containerization (UPBK2H6LZM)", "署名者: Apple Inc. - Containerization (UPBK2H6LZM)", "서명자: Apple Inc. - Containerization (UPBK2H6LZM)"),
    translation("Simulate failed postflight", "模拟后置检查失败", "模擬後置檢查失敗", "ポストフライト失敗をシミュレート", "사후 검사 실패 시뮬레이션"),
    translation("Simulate rollback failure", "模拟回滚失败", "模擬回復失敗", "ロールバック失敗をシミュレート", "롤백 실패 시뮬레이션"),
    translation("Source: developer.apple.com", "来源：developer.apple.com", "來源：developer.apple.com", "提供元: developer.apple.com", "출처: developer.apple.com"),
    translation("Start with Simple Mode", "从简单模式开始", "從簡易模式開始", "シンプルモードで開始", "단순 모드로 시작"),
    translation("Template", "模板", "範本", "テンプレート", "템플릿"),
    translation("Template Library", "模板库", "範本庫", "テンプレートライブラリ", "템플릿 보관함"),
    translation("Template workflow steps", "模板工作流步骤", "範本工作流程步驟", "テンプレートワークフローの手順", "템플릿 작업 흐름 단계"),
    translation("Terminate", "终止", "終止", "終了", "종료"),
    translation("This permanently removes runtime data, credentials, caches, and rollback points.", "此操作将永久移除运行时数据、凭据、缓存和回滚点。", "此操作會永久移除執行階段資料、憑證、快取和回復點。", "ランタイムデータ、認証情報、キャッシュ、ロールバックポイントを完全に削除します。", "런타임 데이터, 자격 증명, 캐시, 롤백 지점을 영구적으로 제거합니다."),
    translation("Type REMOVE APPLE CONTAINER", "输入 REMOVE APPLE CONTAINER", "輸入 REMOVE APPLE CONTAINER", "REMOVE APPLE CONTAINER と入力", "REMOVE APPLE CONTAINER 입력"),
    translation("Uninstall incomplete", "卸载未完成", "解除安裝未完成", "アンインストール未完了", "제거 미완료"),
    translation("Unknown, incomplete, or stale compatibility evidence blocks automatic installation.", "未知、不完整或过期的兼容性证据会阻止自动安装。", "未知、不完整或過期的相容性證據會阻止自動安裝。", "未知、不完全、または古い互換性証拠がある場合、自動インストールをブロックします。", "알 수 없거나 불완전하거나 오래된 호환성 증거가 있으면 자동 설치를 차단합니다."),
    translation("Use Simple Mode for new workloads", "新工作负载使用简单模式", "新工作負載使用簡易模式", "新しいワークロードでシンプルモードを使用", "새 워크로드에 단순 모드 사용"),
    translation("Uses local-only, least-privilege defaults", "使用仅限本地、最小权限的默认值", "使用僅限本機、最低權限的預設值", "ローカル限定、最小権限の既定値を使用", "로컬 전용 최소 권한 기본값 사용"),
    translation("Uses the typed runtime bridge; no shell command is generated.", "使用类型安全的运行时桥接；不会生成 shell 命令。", "使用型別安全的執行階段橋接；不會產生 shell 指令。", "型付きランタイムブリッジを使用し、シェルコマンドは生成しません。", "형식화된 런타임 브리지를 사용하며 셸 명령을 생성하지 않습니다."),
    translation("Value", "值", "值", "値", "값"),
    translation("Version %@", "版本 %@", "版本 %@", "バージョン %@", "버전 %@"),
    translation("Volume name", "存储卷名称", "儲存卷宗名稱", "ボリューム名", "볼륨 이름"),
    translation("Welcome to MacContainer", "欢迎使用 MacContainer", "歡迎使用 MacContainer", "MacContainerへようこそ", "MacContainer에 오신 것을 환영합니다"),
    translation("What do you want to do?", "你想做什么？", "你想做什麼？", "何をしますか?", "무엇을 하시겠습니까?"),
    translation("Workspace folder", "工作区文件夹", "工作區資料夾", "ワークスペースフォルダ", "작업 공간 폴더"),
    translation("https://", "https://", "https://", "https://", "https://"),
    translation("linux/arm64", "linux/arm64", "linux/arm64", "linux/arm64", "linux/arm64"),
    translation("macOS 26 · Apple silicon · Runtime ready", "macOS 26 · Apple 芯片 · 运行时已就绪", "macOS 26 · Apple 晶片 · 執行階段已就緒", "macOS 26 · Appleシリコン · ランタイム使用可能", "macOS 26 · Apple Silicon · 런타임 준비됨"),
    translation("Apple container networks cannot be edited in place. Create a replacement and move workloads after review.", "Apple container 网络无法原地编辑。请创建替代网络，并在检查后迁移工作负载。", "Apple container 網路無法就地編輯。請建立替代網路，並在檢查後移轉工作負載。", "Apple container のネットワークは直接編集できません。代替ネットワークを作成し、確認後にワークロードを移動してください。", "Apple container 네트워크는 직접 편집할 수 없습니다. 대체 네트워크를 만들고 검토 후 워크로드를 이동하십시오."),
    translation("Configuration and relationships", "配置与关联关系", "設定與關聯關係", "設定と関連付け", "구성 및 연결 관계"),
    translation("Create a container", "创建容器", "建立容器", "コンテナを作成", "컨테이너 만들기"),
    translation("Create a workload", "创建工作负载", "建立工作負載", "ワークロードを作成", "워크로드 만들기"),
    translation("Create a workload…", "创建工作负载…", "建立工作負載…", "ワークロードを作成…", "워크로드 만들기…"),
    translation("Open Virtual Machines", "打开虚拟机", "開啟虛擬機器", "仮想マシンを開く", "가상 머신 열기"),
    translation("Open Containers", "打开容器", "開啟容器", "コンテナを開く", "컨테이너 열기"),
    translation("Your virtual machine is running. Open Virtual Machines for terminal and lifecycle controls.", "虚拟机正在运行。打开虚拟机页面即可使用终端和生命周期控制。", "虛擬機器正在執行。開啟虛擬機器頁面即可使用終端機與生命週期控制。", "仮想マシンは実行中です。仮想マシンを開いてターミナルとライフサイクルを管理できます。", "가상 머신이 실행 중입니다. 가상 머신을 열어 터미널과 수명 주기를 관리할 수 있습니다."),
    translation("Your virtual machine is stopped. Open Virtual Machines to start it or access its terminal.", "虚拟机已停止。打开虚拟机页面即可启动或访问终端。", "虛擬機器已停止。開啟虛擬機器頁面即可啟動或存取終端機。", "仮想マシンは停止中です。仮想マシンを開いて起動またはターミナルに接続できます。", "가상 머신이 중지되었습니다. 가상 머신을 열어 시작하거나 터미널에 접근할 수 있습니다."),
    translation("Containers and virtual machines are separate resources. Open Containers to manage this workload.", "容器和虚拟机是不同的资源。打开容器页面管理此工作负载。", "容器與虛擬機器是不同資源。開啟容器頁面管理此工作負載。", "コンテナと仮想マシンは別のリソースです。コンテナを開いてこのワークロードを管理します。", "컨테이너와 가상 머신은 별도 리소스입니다. 컨테이너를 열어 이 워크로드를 관리합니다."),
    translation("Create a guided container or virtual machine. The verified Alpine image is prepared automatically.", "通过向导创建容器或虚拟机。经过验证的 Alpine 镜像会自动准备。", "透過精靈建立容器或虛擬機器。經過驗證的 Alpine 映像會自動準備。", "ガイドに従ってコンテナまたは仮想マシンを作成します。検証済み Alpine イメージは自動準備されます。", "안내에 따라 컨테이너 또는 가상 머신을 만듭니다. 검증된 Alpine 이미지는 자동으로 준비됩니다."),
    translation("Create Replacement", "创建替代网络", "建立替代網路", "置き換えを作成", "대체 네트워크 만들기"),
    translation("Create Replacement…", "创建替代网络…", "建立替代網路…", "置き換えを作成…", "대체 네트워크 만들기…"),
    translation("Custom images need /sbin/init. The verified built-in image is safest.", "自定义镜像需要 /sbin/init。经过验证的内置镜像最安全。", "自訂映像需要 /sbin/init。經過驗證的內建映像最安全。", "カスタムイメージには /sbin/init が必要です。検証済みの内蔵イメージが最も安全です。", "사용자 지정 이미지에는 /sbin/init가 필요합니다. 검증된 내장 이미지가 가장 안전합니다."),
    translation("First use automatically prepares Alpine 3.22 with complete OpenRC init.", "首次使用时会自动准备包含完整 OpenRC 初始化的 Alpine 3.22。", "首次使用時會自動準備包含完整 OpenRC 初始化的 Alpine 3.22。", "初回使用時に完全な OpenRC init を含む Alpine 3.22 を自動準備します。", "처음 사용할 때 완전한 OpenRC init가 포함된 Alpine 3.22를 자동으로 준비합니다."),
    translation("Machines retain files. Named volumes and custom networks attach to containers.", "虚拟机会保留自己的文件系统。命名卷和自定义网络连接到容器。", "虛擬機器會保留自己的檔案系統。命名卷宗與自訂網路連接到容器。", "マシンは独自のファイルシステムを保持します。名前付きボリュームとカスタムネットワークはコンテナに接続します。", "머신은 자체 파일 시스템을 유지합니다. 명명된 볼륨과 사용자 지정 네트워크는 컨테이너에 연결됩니다."),
    translation("Networks cannot be edited in place. Create a replacement, then move workloads.", "网络无法原地编辑。请创建替代网络，然后迁移工作负载。", "網路無法原地編輯。請建立替代網路，然後遷移工作負載。", "ネットワークはその場で編集できません。置き換えを作成してからワークロードを移動します。", "네트워크는 제자리에서 편집할 수 없습니다. 대체 네트워크를 만든 후 워크로드를 이동하십시오."),
    translation("Container", "容器", "容器", "コンテナ", "컨테이너"),
    translation("Create a Linux virtual machine", "创建 Linux 虚拟机", "建立 Linux 虛擬機器", "Linux仮想マシンを作成", "Linux 가상 머신 만들기"),
    translation("Default", "默认", "預設", "デフォルト", "기본값"),
    translation("Details", "详情", "詳細資訊", "詳細", "세부 정보"),
    translation("Duplicate as New…", "复制为新网络…", "複製為新網路…", "新規として複製…", "새 항목으로 복제…"),
    translation("Interactive terminal", "交互式终端", "互動式終端機", "対話型ターミナル", "대화형 터미널"),
    translation("Network", "网络", "網路", "ネットワーク", "네트워크"),
    translation("New Build", "新建构建", "新增建置", "新規ビルド", "새 빌드"),
    translation("New Container", "新建容器", "新增容器", "新規コンテナ", "새 컨테이너"),
    translation("New Network", "新建网络", "新增網路", "新規ネットワーク", "새 네트워크"),
    translation("New Volume", "新建存储卷", "新增儲存卷宗", "新規ボリューム", "새 볼륨"),
    translation("None", "无", "無", "なし", "없음"),
    translation("OK", "好", "好", "OK", "확인"),
    translation("Open Terminal", "打开终端", "開啟終端機", "ターミナルを開く", "터미널 열기"),
    translation("Persistent volume", "持久化存储卷", "持久化儲存卷宗", "永続ボリューム", "영구 볼륨"),
    translation("Pull Image", "拉取镜像", "提取映像檔", "イメージを取得", "이미지 가져오기"),
    translation("Resource type", "资源类型", "資源類型", "リソースの種類", "리소스 유형"),
    translation("Running containers", "运行中的容器", "執行中的容器", "実行中のコンテナ", "실행 중인 컨테이너"),
    translation("Running virtual machines", "运行中的虚拟机", "執行中的虛擬機器", "実行中の仮想マシン", "실행 중인 가상 머신"),
    translation("Container terminal", "容器终端", "容器終端機", "コンテナターミナル", "컨테이너 터미널"),
    translation("Cancelled", "已取消", "已取消", "キャンセル済み", "취소됨"),
    translation("Completed", "已完成", "已完成", "完了", "완료됨"),
    translation("Downloading", "正在下载", "正在下載", "ダウンロード中", "다운로드 중"),
    translation("Failed", "失败", "失敗", "失敗", "실패"),
    translation("Preparing", "正在准备", "正在準備", "準備中", "준비 중"),
    translation("Running", "正在运行", "正在執行", "実行中", "실행 중"),
    translation("Virtual machine terminal", "虚拟机终端", "虛擬機器終端機", "仮想マシンターミナル", "가상 머신 터미널"),
    translation("Virtual machine", "虚拟机", "虛擬機器", "仮想マシン", "가상 머신"),
    translation("The selected resource could not be started or its interactive shell could not be opened.", "无法启动所选资源，或无法打开其交互式 Shell。", "無法啟動所選資源，或無法開啟其互動式 Shell。", "選択したリソースを起動できないか、対話型シェルを開けませんでした。", "선택한 리소스를 시작할 수 없거나 대화형 셸을 열 수 없습니다."),
    translation("Unable to open terminal", "无法打开终端", "無法開啟終端機", "ターミナルを開けません", "터미널을 열 수 없음"),
    translation("What do you want to create?", "你想创建什么？", "你想建立什麼？", "何を作成しますか？", "무엇을 만드시겠습니까?"),
    translation("Choose a container workload or a persistent virtual machine.", "选择容器工作负载或持久化虚拟机。", "選擇容器工作負載或持久化虛擬機器。", "コンテナワークロードまたは永続仮想マシンを選択します。", "컨테이너 워크로드 또는 영구 가상 머신을 선택하십시오."),
    translation("Containers run application workloads inside the Linux runtime.", "容器在 Linux 运行时中运行应用工作负载。", "容器在 Linux 執行階段中執行應用程式工作負載。", "コンテナはLinuxランタイム内でアプリケーションワークロードを実行します。", "컨테이너는 Linux 런타임에서 애플리케이션 워크로드를 실행합니다."),
    translation("A virtual machine is a persistent Linux host with its own CPU, memory, and disk.", "虚拟机是一台具有独立 CPU、内存和磁盘的持久化 Linux 主机。", "虛擬機器是一台具有獨立 CPU、記憶體和磁碟的持久化 Linux 主機。", "仮想マシンは独自のCPU、メモリ、ディスクを持つ永続Linuxホストです。", "가상 머신은 자체 CPU, 메모리 및 디스크를 가진 영구 Linux 호스트입니다."),
    translation("Your virtual machine is ready. Containers are application workloads that run inside the Linux runtime.", "虚拟机已就绪。容器是在 Linux 运行时中运行的应用工作负载。", "虛擬機器已就緒。容器是在 Linux 執行階段中執行的應用程式工作負載。", "仮想マシンの準備ができています。コンテナはLinuxランタイム内で実行されるアプリケーションワークロードです。", "가상 머신이 준비되었습니다. 컨테이너는 Linux 런타임에서 실행되는 애플리케이션 워크로드입니다."),
    translation("Create an application container. MacContainer will prepare the required Linux runtime safely.", "创建应用容器。MacContainer 会安全地准备所需的 Linux 运行时。", "建立應用程式容器。MacContainer 會安全地準備所需的 Linux 執行階段。", "アプリケーションコンテナを作成します。MacContainerが必要なLinuxランタイムを安全に準備します。", "애플리케이션 컨테이너를 만드십시오. MacContainer가 필요한 Linux 런타임을 안전하게 준비합니다."),
    translation("Create a named volume, then attach it to a container in the workload wizard.", "创建命名存储卷，然后在工作负载向导中将其挂载到容器。", "建立具名儲存卷宗，然後在工作負載精靈中將其掛載到容器。", "名前付きボリュームを作成し、ワークロードウィザードでコンテナに接続します。", "이름 있는 볼륨을 만든 다음 워크로드 마법사에서 컨테이너에 연결하십시오."),
    translation("Create a network, then select it while configuring a container workload.", "创建网络，然后在配置容器工作负载时选择它。", "建立網路，然後在設定容器工作負載時選擇它。", "ネットワークを作成し、コンテナワークロードの設定時に選択します。", "네트워크를 만든 다음 컨테이너 워크로드를 구성할 때 선택하십시오."),
    translation("seconds", "秒", "秒", "秒", "초")
])
// swiftlint:enable line_length

private func localizedObject(_ value: LocalizedValue) -> [String: Any] {
    ["localizations": Dictionary(uniqueKeysWithValues: locales.map { locale in
        (locale, ["stringUnit": ["state": "translated", "value": value.values[locale]!]])
    })]
}

private func humanize(_ identifier: String) -> String {
    let expanded = identifier.reduce(into: "") { output, character in
        if character.isUppercase, output.isEmpty == false {
            output.append(" ")
        }
        output.append(character)
    }
    return expanded.replacingOccurrences(of: "ID", with: "ID").capitalized
}

// Parameter help is intentionally a complete five-language decision table.
// swiftlint:disable line_length
// swiftlint:disable:next cyclomatic_complexity
private func parameterValue(
    kind: String,
    identifier: String,
    parameter: [String: Any],
    locale: String
) -> String {
    let label = humanize(identifier)
    let accepted = (parameter["acceptedValues"] as? [String])?.joined(separator: ", ") ?? "any reviewed value"
    let grammar = parameter["grammar"] as? String ?? "the reviewed value type"
    let security = parameter["securityImpact"] as? String ?? "read-only"
    let required = parameter["required"] as? Bool == true
    let defaultDescription = parameter["upstreamDefault"] is NSNull ? "none" : "see the embedded Apple contract"
    switch (kind, locale) {
    case ("label", "en"): return label
    case ("label", "zh-Hans"): return "\(label) 参数"
    case ("label", "zh-Hant"): return "\(label) 參數"
    case ("label", "ja"): return "\(label) パラメータ"
    case ("label", "ko"): return "\(label) 매개변수"
    case ("concise", "en"): return "Configure \(label) using the reviewed Apple container contract."
    case ("concise", "zh-Hans"): return "按照已审查的 Apple container 合同配置 \(label)。"
    case ("concise", "zh-Hant"): return "依照已審查的 Apple container 合約設定 \(label)。"
    case ("concise", "ja"): return "レビュー済みの Apple container 契約に従って \(label) を設定します。"
    case ("concise", "ko"): return "검토된 Apple container 계약에 따라 \(label)을(를) 설정합니다."
    case ("validation", "en"): return "Enter a value matching \(grammar); accepted values: \(accepted)."
    case ("validation", "zh-Hans"): return "请输入符合 \(grammar) 的值；可接受值：\(accepted)。"
    case ("validation", "zh-Hant"): return "請輸入符合 \(grammar) 的值；可接受值：\(accepted)。"
    case ("validation", "ja"): return "\(grammar) に一致する値を入力してください。使用可能な値: \(accepted)。"
    case ("validation", "ko"): return "\(grammar)에 맞는 값을 입력하십시오. 허용 값: \(accepted)."
    case ("recovery", "en"): return "Review \(label), correct the value, and retry; no failed value is applied automatically."
    case ("recovery", "zh-Hans"): return "检查并修正 \(label) 后重试；失败的值不会自动应用。"
    case ("recovery", "zh-Hant"): return "檢查並修正 \(label) 後重試；失敗的值不會自動套用。"
    case ("recovery", "ja"): return "\(label) を確認して値を修正し、再試行してください。失敗した値は自動適用されません。"
    case ("recovery", "ko"): return "\(label)을(를) 검토하고 값을 수정한 뒤 다시 시도하십시오. 실패한 값은 자동 적용되지 않습니다."
    case ("detail", "en"):
        return "Purpose: configures \(label). Upstream default: \(defaultDescription). Accepted values or format: \(accepted); validation grammar: \(grammar). Repeat and order behavior: follows the embedded cardinality and preserves user order. Dependencies and conflicts: enforced from the reviewed contract before dispatch. OS, hardware, and runtime limits: macOS 26, Apple silicon, Apple container 1.1.0. Security or data impact: \(security); required: \(required). Example: choose a reviewed value in this field. Recovery: correct the highlighted value and retry; MacContainer never applies an invalid value."
    case ("detail", "zh-Hans"):
        return "用途：配置 \(label)。上游默认值：\(defaultDescription)。可接受值或格式：\(accepted)；校验规则：\(grammar)。重复与顺序：遵循内嵌基数规则并保留用户顺序。依赖与冲突：执行前按已审查合同强制检查。系统限制：macOS 26、Apple 芯片、Apple container 1.1.0。安全或数据影响：\(security)；必填：\(required)。示例：在此字段选择已审查的值。恢复：修正高亮值后重试；MacContainer 绝不会应用无效值。"
    case ("detail", "zh-Hant"):
        return "用途：設定 \(label)。上游預設值：\(defaultDescription)。可接受值或格式：\(accepted)；驗證規則：\(grammar)。重複與順序：遵循內嵌基數規則並保留使用者順序。相依性與衝突：執行前依已審查合約強制檢查。系統限制：macOS 26、Apple 晶片、Apple container 1.1.0。安全性或資料影響：\(security)；必填：\(required)。範例：在此欄位選擇已審查的值。復原：修正醒目提示的值後重試；MacContainer 絕不會套用無效值。"
    case ("detail", "ja"):
        return "目的: \(label) を設定します。上流の既定値: \(defaultDescription)。使用可能な値または形式: \(accepted)、検証規則: \(grammar)。反復と順序: 埋め込みの基数規則に従い、ユーザーの順序を保持します。依存関係と競合: 実行前にレビュー済み契約から強制します。システム制限: macOS 26、Apple シリコン、Apple container 1.1.0。セキュリティまたはデータへの影響: \(security)、必須: \(required)。例: このフィールドでレビュー済みの値を選択します。復旧: 強調表示された値を修正して再試行してください。MacContainer は無効な値を適用しません。"
    case ("detail", "ko"):
        return "목적: \(label)을(를) 설정합니다. 업스트림 기본값: \(defaultDescription). 허용 값 또는 형식: \(accepted), 검증 규칙: \(grammar). 반복 및 순서: 포함된 카디널리티 규칙을 따르고 사용자 순서를 유지합니다. 종속성과 충돌: 실행 전에 검토된 계약에 따라 강제됩니다. 시스템 제한: macOS 26, Apple Silicon, Apple container 1.1.0. 보안 또는 데이터 영향: \(security), 필수: \(required). 예: 이 필드에서 검토된 값을 선택합니다. 복구: 강조된 값을 수정하고 다시 시도하십시오. MacContainer는 잘못된 값을 적용하지 않습니다."
    default: fatalError("unsupported localization")
    }
}

// swiftlint:enable line_length

private let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fatalError("usage: generate-localizations.swift contract.json output-directory")
}

let contract = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
guard let root = contract as? [String: Any], let operations = root["operations"] as? [[String: Any]] else {
    fatalError("invalid contract")
}

private let allCore = core.merging(additionalCore) { _, additional in additional }
var strings = Dictionary(uniqueKeysWithValues: allCore.map { ($0.key, localizedObject($0.value)) })
for operation in operations {
    guard let parameters = operation["parameters"] as? [[String: Any]] else { continue }
    for parameter in parameters {
        guard let identifier = parameter["id"] as? String else { continue }
        for (field, kind) in [
            ("labelKey", "label"),
            ("conciseHelpKey", "concise"),
            ("detailedHelpKey", "detail"),
            ("validationErrorKey", "validation"),
            ("recoveryKey", "recovery")
        ] {
            guard let key = parameter[field] as? String else { continue }
            let value = LocalizedValue(
                en: parameterValue(kind: kind, identifier: identifier, parameter: parameter, locale: "en"),
                zhHans: parameterValue(kind: kind, identifier: identifier, parameter: parameter, locale: "zh-Hans"),
                zhHant: parameterValue(kind: kind, identifier: identifier, parameter: parameter, locale: "zh-Hant"),
                ja: parameterValue(kind: kind, identifier: identifier, parameter: parameter, locale: "ja"),
                ko: parameterValue(kind: kind, identifier: identifier, parameter: parameter, locale: "ko")
            )
            strings[key] = localizedObject(value)
        }
    }
}

let catalog: [String: Any] = ["sourceLanguage": "en", "strings": strings, "version": "1.0"]
let outputDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let data = try JSONSerialization.data(
    withJSONObject: catalog,
    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
)
try data.write(to: outputDirectory.appending(path: "Localizable.xcstrings"), options: .atomic)

let infoStrings: [String: Any] = [
    "CFBundleDisplayName": localizedObject(.init(
        en: "MacContainer",
        zhHans: "MacContainer",
        zhHant: "MacContainer",
        ja: "MacContainer",
        ko: "MacContainer"
    )),
    "NSHumanReadableCopyright": localizedObject(.init(
        en: "Copyright © 2026 Matrix Religio. All rights reserved.",
        zhHans: "版权所有 © 2026 Matrix Religio。保留所有权利。",
        zhHant: "著作權所有 © 2026 Matrix Religio。保留所有權利。",
        ja: "Copyright © 2026 Matrix Religio. All rights reserved.",
        ko: "Copyright © 2026 Matrix Religio. All rights reserved."
    ))
]
let infoCatalog: [String: Any] = ["sourceLanguage": "en", "strings": infoStrings, "version": "1.0"]
let infoData = try JSONSerialization.data(
    withJSONObject: infoCatalog,
    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
)
try infoData.write(to: outputDirectory.appending(path: "InfoPlist.xcstrings"), options: .atomic)
print("Generated localization catalogs: \(strings.count) UI/help keys in five languages")
