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
    translation("Version 0.1.0", "版本 0.1.0", "版本 0.1.0", "バージョン 0.1.0", "버전 0.1.0"),
    translation("Volume name", "存储卷名称", "儲存卷宗名稱", "ボリューム名", "볼륨 이름"),
    translation("Welcome to MacContainer", "欢迎使用 MacContainer", "歡迎使用 MacContainer", "MacContainerへようこそ", "MacContainer에 오신 것을 환영합니다"),
    translation("What do you want to do?", "你想做什么？", "你想做什麼？", "何をしますか?", "무엇을 하시겠습니까?"),
    translation("Workspace folder", "工作区文件夹", "工作區資料夾", "ワークスペースフォルダ", "작업 공간 폴더"),
    translation("https://", "https://", "https://", "https://", "https://"),
    translation("linux/arm64", "linux/arm64", "linux/arm64", "linux/arm64", "linux/arm64"),
    translation("macOS 26 · Apple silicon · Runtime ready", "macOS 26 · Apple 芯片 · 运行时已就绪", "macOS 26 · Apple 晶片 · 執行階段已就緒", "macOS 26 · Appleシリコン · ランタイム使用可能", "macOS 26 · Apple Silicon · 런타임 준비됨"),
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
