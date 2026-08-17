import XCTest

@MainActor
final class MauryaUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOfflineLaunchAndProductionGatesFailClosed() {
        let app = launchApp()

        XCTAssertTrue(app.descendants(matching: .any)["scan-screen"].waitForExistence(timeout: 5))
        let start = app.buttons["scan-start"]
        let stop = app.buttons["scan-stop"]
        XCTAssertTrue(start.exists)
        XCTAssertTrue(stop.exists)
        XCTAssertLessThan(start.frame.maxX, stop.frame.minX)
        XCTAssertLessThan(abs(start.frame.midY - stop.frame.midY), 2)
        XCTAssertFalse(app.buttons["Import share"].exists)
        XCTAssertFalse(app.buttons["Open review guide"].exists)
        app.buttons["features-menu"].tap()
        XCTAssertFalse(app.buttons["Resources & Palettes"].exists)
        XCTAssertFalse(app.buttons["Effect Editor"].exists)
        XCTAssertFalse(app.buttons["effect-share-entry"].exists)
        app.tap()
        capture("scan-light")

        app.terminate()
        let ota = launchApp(additionalArguments: ["-maurya-ui-route-ota"])
        XCTAssertTrue(ota.collectionViews["ota-workflow"].waitForExistence(timeout: 5))
        XCTAssertTrue(ota.staticTexts["Unavailable: no approved OTA HTTPS endpoint is configured."].exists)
        XCTAssertFalse(ota.buttons["Start secure update"].isEnabled)
        capture("ota-fail-closed")
    }

    func testTypedNavigationReachesOfflineLegalDisclosure() {
        let app = launchApp(additionalArguments: ["-maurya-ui-route-legal"])

        XCTAssertTrue(app.collectionViews["legal-privacy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Privacy"].exists)
        app.collectionViews["legal-privacy"].swipeUp()
        XCTAssertTrue(app.staticTexts["Firmware Update Risk"].exists)
    }

    func testLargestTextAndRTLLaunchDoesNotCrash() {
        let app = launchApp(
            language: "ar", locale: "ar_SA",
            additionalArguments: [
                "-maurya-ui-accessibility-xxxl",
                "-maurya-ui-reduce-motion",
                "-maurya-ui-rtl",
            ])

        XCTAssertTrue(app.descendants(matching: .any)["scan-screen"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.staticTexts["ui-test-fixture-banner"].value as? String,
            "dark;accessibility=true;differentiate=false;reduceMotion=true;rtl=true"
        )
        XCTAssertEqual(app.state, .runningForeground)
        capture("scan-rtl-axxxl")
    }

    func testPopulatedResourcesAndEffectLibraryJourneys() {
        let resources = launchApp(additionalArguments: ["-maurya-ui-route-resources"])
        XCTAssertTrue(resources.navigationBars["Resources & Palettes"].waitForExistence(timeout: 5))
        XCTAssertTrue(resources.staticTexts["Built-in catalog"].exists)
        XCTAssertTrue(resources.buttons["Add palette"].exists)
        let firstResource = resources.staticTexts["Poppin'Party"].firstMatch
        let secondResource = resources.staticTexts["Afterglow"].firstMatch
        XCTAssertTrue(firstResource.exists)
        XCTAssertTrue(secondResource.exists)
        XCTAssertLessThan(abs(secondResource.frame.midY - firstResource.frame.midY), 180)
        capture("resources-populated-light")

        let search = resources.searchFields["Search"]
        XCTAssertTrue(search.exists)
        search.tap()
        search.typeText("美竹兰")
        XCTAssertTrue(resources.staticTexts["美竹兰"].waitForExistence(timeout: 5))
        capture("character-avatar-search-light")

        resources.terminate()
        let effects = launchApp(additionalArguments: ["-maurya-ui-route-effects"])
        XCTAssertTrue(effects.navigationBars["Effect Library"].waitForExistence(timeout: 5))
        XCTAssertTrue(effects.staticTexts["UI Fixture Effect"].exists)
        XCTAssertTrue(effects.buttons["effect-share-entry"].exists)
        capture("effects-populated-light")
        effects.buttons["effect-share-entry"].tap()
        XCTAssertTrue(effects.navigationBars["Temporary Share"].waitForExistence(timeout: 5))
        XCTAssertTrue(effects.segmentedControls.firstMatch.exists)
    }

    func testEditorRecoveryAndControlsAreReachable() {
        let app = launchApp(additionalArguments: ["-maurya-ui-route-editor"])

        XCTAssertTrue(app.staticTexts["UI fixture: restored autosaved editor source"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["effect-editor"].exists)
        XCTAssertTrue(app.staticTexts["Ready"].waitForExistence(timeout: 10))
        let source = app.textViews.firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(String(describing: source.value).contains("Recovered Fixture"))
        source.tap()
        source.typeText(" ")
        XCTAssertTrue(app.buttons["Save"].exists)
        capture("editor-recovery-light")
    }

    func testIPadProLandscapeKeepsSidebarAndMajorRoutesUsable() throws {
        // Launching the app can reset the interface to portrait while XCTest still
        // reports the device as landscape. Force a real orientation transition.
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = launchApp(additionalArguments: ["-maurya-ui-route-resources"])
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        guard max(window.frame.width, window.frame.height) > 1_100 else {
            throw XCTSkip("This deterministic wide-layout journey runs only on an iPad-class simulator.")
        }
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let window = object as? XCUIElement else { return false }
                return window.frame.width > window.frame.height
            },
            object: window
        )
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 10), .completed)
        XCTAssertGreaterThan(window.frame.width, window.frame.height)

        let sidebar = app.collectionViews["sidebar-navigation"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["sidebar-resources"].exists)
        XCTAssertFalse(app.buttons["sidebar-editor"].exists)
        XCTAssertTrue(app.navigationBars["Resources & Palettes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Poppin'Party"].firstMatch.exists)
        XCTAssertLessThan(sidebar.frame.maxX, app.staticTexts["Poppin'Party"].firstMatch.frame.midX)
        capture("ipad-landscape-resources-split")

        app.buttons["sidebar-effects"].tap()
        XCTAssertTrue(app.navigationBars["Effect Library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["effect-share-entry"].exists)
        XCTAssertTrue(app.staticTexts["UI Fixture Effect"].firstMatch.exists)
        let fixtureEffect = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'UI Fixture Effect'")
        ).firstMatch
        XCTAssertTrue(fixtureEffect.exists)

        fixtureEffect.tap()
        XCTAssertTrue(app.descendants(matching: .any)["effect-editor"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["sidebar-effects"].isSelected)
        XCTAssertTrue(app.staticTexts["Ready"].waitForExistence(timeout: 30))
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 20))
        editor.tap()
        editor.typeText(" ")
        let save = app.buttons["Save"]
        expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: save)
        waitForExpectations(timeout: 5)
        if app.keyboards.firstMatch.exists {
            XCTAssertLessThan(editor.frame.minY, app.keyboards.firstMatch.frame.minY)
        }
        capture("ipad-landscape-editor-keyboard-split")

        app.buttons["sidebar-analysis"].tap()
        XCTAssertTrue(app.navigationBars["Live Analysis"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["sidebar-playback"].exists)
        XCTAssertTrue(app.buttons["sidebar-share"].exists)
        XCTAssertFalse(app.buttons["sidebar-review"].exists)
        XCTAssertFalse(app.buttons["sidebar-legal"].exists)

        app.buttons["sidebar-share"].tap()
        XCTAssertTrue(app.navigationBars["Temporary Share"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sidebar-share"].isSelected)

        app.buttons["sidebar-ota"].tap()
        XCTAssertTrue(app.navigationBars["Firmware Update"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Start secure update"].isEnabled)
        capture("ipad-landscape-ota-fail-closed-split")
    }

    func testIPadSidebarIncludesShareAndKeepsItOffTheHomeScreen() throws {
        let app = launchApp(additionalArguments: ["-maurya-ui-route-resources"])
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        guard max(window.frame.width, window.frame.height) > 1_100 else {
            throw XCTSkip("This sidebar journey runs only on an iPad-class simulator.")
        }

        XCTAssertTrue(app.collectionViews["sidebar-navigation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sidebar-share"].exists)
        app.buttons["sidebar-share"].tap()
        XCTAssertTrue(app.navigationBars["Temporary Share"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sidebar-share"].isSelected)

        app.buttons["sidebar-devices"].tap()
        XCTAssertTrue(app.navigationBars["Devices"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["share.import"].exists)
    }

    func testSimplifiedChineseLaunchUsesLocalizedNavigation() {
        let app = launchApp(language: "zh-Hans", locale: "zh_CN")

        XCTAssertTrue(app.navigationBars["设备"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["language-menu"].exists)
    }

    func testSharePreviewConfirmFailureAndCancellationJourneys() {
        let preview = launchApp(additionalArguments: [
            "-maurya-ui-route-share",
            "-maurya-ui-share-preview",
        ])
        XCTAssertTrue(preview.staticTexts["Deterministic UI test preview"].waitForExistence(timeout: 5))
        XCTAssertTrue(preview.staticTexts["Hash, schema, moderation, and local compilation checks passed"].exists)
        capture("share-preview-light")
        preview.buttons["Create local copy"].tap()
        XCTAssertTrue(preview.staticTexts["UI fixture preview cannot import data."].waitForExistence(timeout: 5))
        capture("share-confirm-failure")
        preview.buttons["Cancel"].tap()
        XCTAssertTrue(
            preview.staticTexts["Enter a code or an exact Maurya share link. Nothing is imported automatically."].waitForExistence(
                timeout: 5))

        preview.terminate()
        let cancelling = launchApp(additionalArguments: ["-maurya-ui-route-share"])
        let token = cancelling.textFields["10-character code or link"]
        XCTAssertTrue(token.waitForExistence(timeout: 5))
        token.tap()
        token.typeText("ABCDEFGHIJ")
        cancelling.buttons["Validate and preview"].tap()
        XCTAssertTrue(cancelling.staticTexts["Verifying securely"].waitForExistence(timeout: 5))
        XCTAssertTrue(cancelling.buttons["Cancel"].exists)
        cancelling.buttons["Cancel"].tap()
        XCTAssertTrue(
            cancelling.staticTexts["Enter a code or an exact Maurya share link. Nothing is imported automatically."].waitForExistence(
                timeout: 5))
    }

    func testScannerUnavailableRemainsRecoverableAcrossLandscapeAndLifecycle() {
        let originalOrientation = XCUIDevice.shared.orientation
        addTeardownBlock { XCUIDevice.shared.orientation = originalOrientation }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launchApp(additionalArguments: [
            "-maurya-ui-route-share",
            "-maurya-ui-scanner-unavailable",
        ])

        let scanButton = app.buttons["Scan QR code"]
        XCTAssertTrue(scanButton.waitForExistence(timeout: 5))
        scanButton.tap()

        let unavailable = app.descendants(matching: .any)["share-scanner-unavailable"]
        XCTAssertTrue(unavailable.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height)
        XCTAssertTrue(app.buttons["Retry"].isHittable)

        app.buttons["Retry"].tap()
        XCTAssertTrue(unavailable.waitForExistence(timeout: 5))

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(unavailable.waitForExistence(timeout: 5))

        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.textFields["10-character code or link"].waitForExistence(timeout: 5))
    }

    func testPhysicalBluetoothDiscoveryWhenExplicitlyEnabled() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_UDID"] == nil else {
            throw XCTSkip("Physical BLE discovery cannot run in Simulator.")
        }

        addUIInterruptionMonitor(withDescription: "Bluetooth permission") { alert in
            for title in ["Allow", "允许", "好"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }

        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.tap()

        XCTAssertTrue(app.descendants(matching: .any)["scan-screen"].waitForExistence(timeout: 8))
        let discoveredDevice = app.buttons.matching(identifier: "scan-device").firstMatch
        XCTAssertTrue(
            discoveredDevice.waitForExistence(timeout: 20),
            "No Maurya peripheral advertising FFE0 or a maurya- name was discovered."
        )
        XCTAssertTrue(discoveredDevice.isHittable)
        capture("physical-ble-discovery-read-only")
    }

    func testPhysicalBluetoothConnectsAndReadsSnapshotWithoutWriting() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_UDID"] == nil else {
            throw XCTSkip("Physical BLE connection cannot run in Simulator.")
        }

        addUIInterruptionMonitor(withDescription: "Bluetooth permission") { alert in
            for title in ["Allow", "允许", "好"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }

        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.tap()

        XCTAssertTrue(app.descendants(matching: .any)["scan-screen"].waitForExistence(timeout: 8))
        let discoveredDevice = app.buttons.matching(identifier: "scan-device").firstMatch
        XCTAssertTrue(
            discoveredDevice.waitForExistence(timeout: 20),
            "No Maurya peripheral was discovered for the read-only connection check."
        )
        discoveredDevice.tap()

        XCTAssertTrue(app.navigationBars["Device"].waitForExistence(timeout: 8))
        let firmware = app.descendants(matching: .any)["device-telemetry-card"]
        XCTAssertTrue(
            firmware.waitForExistence(timeout: 25),
            "The BLE link did not reach ready state with a readable device snapshot."
        )
        capture("physical-ble-connected-read-only-snapshot")

        let disconnect = app.buttons["device-disconnect"]
        XCTAssertTrue(disconnect.isHittable)
        disconnect.tap()
    }

    func testPhysicalCharacterCatalogShowsPackagedAvatarsWithoutWriting() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_UDID"] == nil else {
            throw XCTSkip("Physical avatar validation is recorded on the connected iPad.")
        }

        addUIInterruptionMonitor(withDescription: "Bluetooth permission") { alert in
            for title in ["Allow", "允许", "好"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }

        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.tap()

        XCTAssertTrue(app.descendants(matching: .any)["scan-screen"].waitForExistence(timeout: 8))
        let discoveredDevice = app.buttons.matching(identifier: "scan-device").firstMatch
        XCTAssertTrue(discoveredDevice.waitForExistence(timeout: 20))
        discoveredDevice.tap()
        XCTAssertTrue(app.descendants(matching: .any)["device-telemetry-card"].waitForExistence(timeout: 25))

        let characters = app.descendants(matching: .any)["device-section-characters"]
        XCTAssertTrue(characters.waitForExistence(timeout: 5))
        characters.tap()
        XCTAssertTrue(app.descendants(matching: .any)["support-color-browser"].waitForExistence(timeout: 12))

        let afterglow = app.descendants(matching: .any)["palette-group-bangdream_afterglow"]
        XCTAssertTrue(afterglow.waitForExistence(timeout: 8))
        afterglow.tap()
        let ran = app.descendants(matching: .any)["palette-character-bangdream_char_006"]
        let browser = app.collectionViews["support-color-browser"]
        for _ in 0..<4 where ran.exists == false {
            browser.swipeUp()
        }
        XCTAssertTrue(ran.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["美竹兰"].exists)
        capture("physical-character-avatars-afterglow")

        app.buttons["device-disconnect"].tap()
    }

    func testPhysicalReversibleWriteValidationRestoresOriginalState() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_UDID"] == nil else {
            throw XCTSkip("Physical register writes cannot run in Simulator.")
        }

        addUIInterruptionMonitor(withDescription: "Bluetooth permission") { alert in
            for title in ["Allow", "允许", "好"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }

        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-maurya-physical-write-validation",
        ]
        app.launch()
        app.tap()

        XCTAssertTrue(app.descendants(matching: .any)["scan-screen"].waitForExistence(timeout: 8))
        let discoveredDevice = app.buttons.matching(identifier: "scan-device").firstMatch
        XCTAssertTrue(discoveredDevice.waitForExistence(timeout: 20))
        discoveredDevice.tap()
        XCTAssertTrue(app.descendants(matching: .any)["device-telemetry-card"].waitForExistence(timeout: 25))

        let run = app.buttons["device-write-validation-run"]
        XCTAssertTrue(run.waitForExistence(timeout: 8))
        XCTAssertTrue(run.isHittable)
        run.tap()

        let success = app.descendants(matching: .any)["device-operation-success"]
        let error = app.descendants(matching: .any)["device-operation-error"]
        expectation(
            for: NSPredicate { _, _ in success.exists || error.exists },
            evaluatedWith: app
        )
        waitForExpectations(timeout: 45)
        XCTAssertFalse(error.exists, "Write validation failed: \(error.label)")
        XCTAssertTrue(success.exists)
        capture("physical-reversible-register-write-passed-and-restored")

        app.buttons["device-disconnect"].tap()
    }

    func testPhysicalConsoleStartsWithIndividualGroupsCollapsed() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_UDID"] == nil else {
            throw XCTSkip("The live console hierarchy is validated on the connected iPad.")
        }

        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["scan-screen"].waitForExistence(timeout: 8))
        let discoveredDevice = app.buttons.matching(identifier: "scan-device").firstMatch
        XCTAssertTrue(discoveredDevice.waitForExistence(timeout: 20))
        discoveredDevice.tap()
        XCTAssertTrue(app.descendants(matching: .any)["device-telemetry-card"].waitForExistence(timeout: 25))

        let console = app.scrollViews["device-console"]
        XCTAssertTrue(console.exists)
        let toggle = app.buttons["advanced-groups-toggle"]
        for _ in 0..<8 where toggle.exists == false {
            console.swipeUp()
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        XCTAssertEqual(toggle.value as? String, "collapsed")
        XCTAssertFalse(app.descendants(matching: .any)["group-card-1"].exists)
        capture("physical-console-individual-groups-collapsed")

        toggle.tap()
        let firstGroup = app.descendants(matching: .any)["group-card-1"]
        XCTAssertTrue(firstGroup.waitForExistence(timeout: 8))
        XCTAssertEqual(toggle.value as? String, "expanded")
        capture("physical-console-individual-groups-expanded")

        app.buttons["device-disconnect"].tap()
    }

    func testDarkAppearanceVisualBaseline() {
        let app = launchApp(additionalArguments: [
            "-maurya-ui-dark",
            "-maurya-ui-route-resources",
        ])

        XCTAssertTrue(app.navigationBars["Resources & Palettes"].waitForExistence(timeout: 5))
        let banner = app.staticTexts["ui-test-fixture-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "value BEGINSWITH 'dark;'"), evaluatedWith: banner)
        waitForExpectations(timeout: 3)
        capture("resources-populated-dark")
    }

    func testResourceFallbackAtLargestTextAndDifferentiateWithoutColor() {
        let app = launchApp(additionalArguments: [
            "-maurya-ui-route-resources",
            "-maurya-ui-accessibility-xxxl",
            "-maurya-ui-differentiate-without-color",
        ])

        XCTAssertTrue(app.navigationBars["Resources & Palettes"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.staticTexts["ui-test-fixture-banner"].value as? String,
            "dark;accessibility=true;differentiate=true;reduceMotion=false;rtl=false"
        )
        XCTAssertTrue(app.staticTexts["Poppin'Party"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["#FF69B4"].exists)
        capture("resources-axxxl-differentiate-without-color")
    }

    private func launchApp(
        language: String = "en",
        locale: String = "en_US",
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            [
                "-maurya-ui-testing",
                "-AppleLanguages", "(\(language))",
                "-AppleLocale", locale,
            ] + additionalArguments
        app.launch()
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
