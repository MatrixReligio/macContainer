import MCCompatibility
import MCSystemLifecycle
import XCTest

final class UpdateAgentTests: XCTestCase {
    func testLaunchAgentUsesDailyBackgroundScheduleWithBackoff() throws {
        let data = try Data(contentsOf: sourceRoot
            .appending(path: "App/UpdateAgent/container.matrixreligio.com.update-agent.plist"))
        let value = try PropertyListSerialization.propertyList(from: data, format: nil)
        let plist = try XCTUnwrap(value as? [String: Any])

        XCTAssertEqual(plist["Label"] as? String, "container.matrixreligio.com.update-agent")
        XCTAssertEqual(plist["StartInterval"] as? Int, 86400)
        XCTAssertEqual(plist["ThrottleInterval"] as? Int, 900)
        XCTAssertEqual(plist["ProcessType"] as? String, "Background")
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, false)
        XCTAssertEqual(plist["LowPriorityIO"] as? Bool, true)
    }

    func testAgentHasNoPrivilegedEntitlement() throws {
        let data = try Data(contentsOf: sourceRoot.appending(path: "App/UpdateAgent/UpdateAgent.entitlements"))
        let value = try PropertyListSerialization.propertyList(from: data, format: nil)
        let entitlements = try XCTUnwrap(value as? [String: Any])

        XCTAssertNil(entitlements["com.apple.security.application-groups"])
        XCTAssertNil(entitlements["com.apple.security.temporary-exception.files.absolute-path.read-write"])
        XCTAssertNil(entitlements["com.apple.security.cs.disable-library-validation"])
    }

    func testUpdateAgentBuildSmokeDoesNotTouchRuntime() throws {
        let products = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        let executable = products
            .appending(path: "MacContainer.app/Contents/MacOS/container.matrixreligio.com.update-agent")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path))

        let process = Process()
        process.executableURL = executable
        process.arguments = ["--build-smoke-test"]
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, EXIT_SUCCESS)
    }

    func testNotificationLanguageResolutionMatchesAppPolicy() {
        XCTAssertEqual(UpdateAgentLocalization.resolveLanguage(
            selectedLanguageRawValue: "ko",
            preferredLanguages: ["en-US"]
        ), "ko")
        XCTAssertEqual(UpdateAgentLocalization.resolveLanguage(
            selectedLanguageRawValue: "system",
            preferredLanguages: ["zh_CN"]
        ), "zh-Hans")
        XCTAssertEqual(UpdateAgentLocalization.resolveLanguage(
            selectedLanguageRawValue: nil,
            preferredLanguages: ["zh-HK"]
        ), "zh-Hant")
        XCTAssertEqual(UpdateAgentLocalization.resolveLanguage(
            selectedLanguageRawValue: "invalid",
            preferredLanguages: ["ja-JP"]
        ), "ja")
        XCTAssertEqual(UpdateAgentLocalization.resolveLanguage(
            selectedLanguageRawValue: nil,
            preferredLanguages: ["fr-FR"]
        ), "en")
    }

    func testNotificationsUseCompleteCompiledTranslations() throws {
        let products = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        let appBundle = try XCTUnwrap(Bundle(url: products.appending(path: "MacContainer.app")))

        for fixture in notificationFixtures {
            let localization = UpdateAgentLocalization(
                appBundle: appBundle,
                selectedLanguageRawValue: fixture.language,
                preferredLanguages: []
            )
            XCTAssertEqual(localization.title(), fixture.title, fixture.language)
            XCTAssertEqual(localization.body(for: .available(version: "1.2.3")), fixture.available, fixture.language)
            XCTAssertEqual(localization.body(for: .pending(.workActive)), fixture.pending, fixture.language)
            XCTAssertEqual(localization.body(for: .held(.unknownRuntime)), fixture.held, fixture.language)
            XCTAssertEqual(
                localization.body(for: .rolledBack(previousVersion: "1.1.0", failedProbeID: nil)),
                fixture.rolledBack,
                fixture.language
            )
            XCTAssertEqual(
                localization.body(for: .recoveryRequired(code: "fixture")),
                fixture.recoveryRequired,
                fixture.language
            )
            XCTAssertEqual(localization.body(for: .upToDate), fixture.defaultBody, fixture.language)
        }
    }

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct NotificationFixture {
    let language: String
    let title: String
    let available: String
    let pending: String
    let held: String
    let rolledBack: String
    let recoveryRequired: String
    let defaultBody: String
}

private let notificationFixtures: [NotificationFixture] = [
    .init(
        language: "en",
        title: "MacContainer runtime update",
        available: "Apple container 1.2.3 is compatibility-approved and ready to review.",
        pending: "An approved runtime update is waiting. Open MacContainer for details.",
        held: "A discovered runtime is held for safety. Open MacContainer for details.",
        rolledBack: "The runtime update was rolled back. Open MacContainer for recovery details.",
        recoveryRequired: "Runtime recovery requires attention in MacContainer.",
        defaultBody: "Open MacContainer to review runtime update status."
    ),
    .init(
        language: "zh-Hans",
        title: "MacContainer 运行时更新",
        available: "Apple container 1.2.3 已通过兼容性验证，可以查看。",
        pending: "已批准的运行时更新正在等待。请打开 MacContainer 查看详情。",
        held: "检测到的运行时已为安全起见暂停。请打开 MacContainer 查看详情。",
        rolledBack: "运行时更新已回滚。请打开 MacContainer 查看恢复详情。",
        recoveryRequired: "运行时恢复需要在 MacContainer 中处理。",
        defaultBody: "请打开 MacContainer 查看运行时更新状态。"
    ),
    .init(
        language: "zh-Hant",
        title: "MacContainer 執行階段更新",
        available: "Apple container 1.2.3 已通過相容性驗證，可供檢視。",
        pending: "已核准的執行階段更新正在等候。請開啟 MacContainer 查看詳細資訊。",
        held: "偵測到的執行階段已基於安全考量暫停。請開啟 MacContainer 查看詳細資訊。",
        rolledBack: "執行階段更新已回復。請開啟 MacContainer 查看復原詳細資訊。",
        recoveryRequired: "執行階段復原需要在 MacContainer 中處理。",
        defaultBody: "請開啟 MacContainer 查看執行階段更新狀態。"
    ),
    .init(
        language: "ja",
        title: "MacContainer ランタイムアップデート",
        available: "Apple container 1.2.3 は互換性が確認され、確認できます。",
        pending: "承認済みのランタイムアップデートが保留中です。詳細は MacContainer で確認してください。",
        held: "検出されたランタイムは安全のため保留されています。詳細は MacContainer で確認してください。",
        rolledBack: "ランタイムアップデートはロールバックされました。復旧の詳細は MacContainer で確認してください。",
        recoveryRequired: "MacContainer でランタイムの復旧対応が必要です。",
        defaultBody: "ランタイムアップデートの状態を MacContainer で確認してください。"
    ),
    .init(
        language: "ko",
        title: "MacContainer 런타임 업데이트",
        available: "Apple container 1.2.3의 호환성 검증이 완료되어 검토할 수 있습니다.",
        pending: "승인된 런타임 업데이트가 대기 중입니다. MacContainer에서 세부 정보를 확인하십시오.",
        held: "발견된 런타임이 안전을 위해 보류되었습니다. MacContainer에서 세부 정보를 확인하십시오.",
        rolledBack: "런타임 업데이트가 롤백되었습니다. MacContainer에서 복구 세부 정보를 확인하십시오.",
        recoveryRequired: "MacContainer에서 런타임 복구 조치가 필요합니다.",
        defaultBody: "MacContainer에서 런타임 업데이트 상태를 확인하십시오."
    )
]
