import XCTest

@MainActor final class NativeFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func messageInput(_ app: XCUIApplication) -> XCUIElement {
        if app.textViews["message-input"].exists { return app.textViews["message-input"] }
        return app.textFields["message-input"]
    }
    func testNativeAppearanceAndConversationWithPreviewData() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--reset-demo-draft"]; app.launch()
        XCTAssertTrue(app.navigationBars["Threads"].waitForExistence(timeout: 10))
        capture("01-conversations-preview", app: app)
        app.buttons["Appearance and text size"].tap()
        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 5))
        capture("02-appearance", app: app)
        app.sliders["Conversation text size"].adjust(toNormalizedSliderPosition: 0.7)
        capture("03-larger-type", app: app)
        app.sliders["Conversation text size"].adjust(toNormalizedSliderPosition: 1.0 / 6.0)
        app.buttons["Done"].tap()
        app.staticTexts["Build a native iOS client"].tap()
        XCTAssertTrue(messageInput(app).waitForExistence(timeout: 5))
        capture("04-native-conversation-preview", app: app)
        messageInput(app).tap()
        messageInput(app).typeText("A saved draft")
        capture("05-composer-keyboard-preview", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.staticTexts["Build a native iOS client"].tap()
        XCTAssertEqual(messageInput(app).value as? String, "A saved draft")
    }

    func testModelOptionsAndProviderDraftWithPreviewData() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--reset-demo-draft"]; app.launch()
        app.staticTexts["Build a native iOS client"].tap()
        XCTAssertTrue(app.buttons["model-settings"].waitForExistence(timeout: 5))
        app.buttons["model-settings"].tap()
        XCTAssertTrue(app.navigationBars["Model"].waitForExistence(timeout: 5))
        capture("09-model-options-preview", app: app)
        app.buttons["model-option-effort"].tap(); app.buttons["Max"].tap()
        app.buttons["model-option-fastMode"].tap(); app.buttons["On"].tap()
        capture("10-explicit-model-options-preview", app: app)
        app.buttons["Use model"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.staticTexts["Build a native iOS client"].tap()
        app.buttons["model-settings"].tap()
        XCTAssertTrue(app.buttons["model-option-effort"].label.contains("Max"))
        app.buttons["conversation-provider"].tap(); app.buttons["Claude"].tap()
        XCTAssertFalse(app.buttons["model-option-effort"].exists)
        capture("11-provider-switch-preview", app: app)
        app.buttons["Use model"].tap()
        XCTAssertEqual(app.buttons["model-settings"].value as? String, "Claude Sonnet 4.6")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.staticTexts["Build a native iOS client"].tap()
        XCTAssertEqual(app.buttons["model-settings"].value as? String, "Claude Sonnet 4.6")
        app.buttons["model-settings"].tap(); app.buttons["Use conversation settings"].tap()
        XCTAssertEqual(app.buttons["model-settings"].value as? String, "GPT-6.1 Sol")
    }

    func testNativeMarkdownWithPreviewData() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--markdown-demo", "--reset-demo-draft"]; app.launch()
        app.staticTexts["Build a native iOS client"].tap()
        XCTAssertTrue(app.buttons["model-settings"].waitForExistence(timeout: 5))
        let timeline = app.scrollViews["conversation-timeline"]
        capture("14-markdown-code-table-preview", app: app)
        if app.buttons["Copy"].firstMatch.isHittable {
            app.buttons["Copy"].firstMatch.tap()
            XCTAssertTrue(app.buttons["Copied"].firstMatch.waitForExistence(timeout: 3))
        }
        timeline.swipeDown(); timeline.swipeDown()
        capture("15-markdown-headings-lists-preview", app: app)
        XCTAssertTrue(app.staticTexts["Keep your place on reconnect"].exists)
        XCTAssertTrue(app.staticTexts["Connection states"].exists)
        XCTAssertTrue(app.scrollViews["markdown-table"].exists)
        app.buttons["Conversation actions"].tap(); app.buttons["Text and appearance"].tap()
        app.buttons["appearance-choice"].tap(); app.buttons["Light"].tap()
        app.sliders["Conversation text size"].adjust(toNormalizedSliderPosition: 0.6)
        app.buttons["Done"].tap(); app.buttons["Jump to latest message"].tap()
        capture("16-markdown-light-larger-type-preview", app: app)
        app.buttons["Conversation actions"].tap(); app.buttons["Text and appearance"].tap()
        app.buttons["appearance-choice"].tap(); app.buttons["System"].tap()
        app.sliders["Conversation text size"].adjust(toNormalizedSliderPosition: 1.0 / 6.0)
        app.buttons["Done"].tap()
    }

    func testEarlierHistoryKeepsReadingPositionWithPreviewData() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--history-demo", "--reset-demo-draft"]; app.launch()
        app.staticTexts["Build a native iOS client"].tap()
        let timeline = app.scrollViews["conversation-timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        let load = app.buttons["Load earlier messages"]
        for _ in 0..<10 { if load.isHittable { break }; timeline.swipeDown() }
        XCTAssertTrue(load.isHittable)
        let marker = app.staticTexts["History marker 16"]
        XCTAssertTrue(marker.isHittable)
        let before = marker.frame.minY
        capture("17-history-before-page-preview", app: app)
        load.tap()
        capture("18-history-after-page-preview", app: app)
        XCTAssertTrue(marker.isHittable, "Loading history must keep the current message visible.")
        XCTAssertEqual(marker.frame.minY, before, accuracy: 5, "Prepending a page must preserve the reading offset.")
    }

    func testLongMessageHistoryAnchorWithPreviewData() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--history-demo", "--history-tall-demo", "--reset-demo-draft"]; app.launch()
        app.staticTexts["Build a native iOS client"].tap()
        let timeline = app.scrollViews["conversation-timeline"]
        let load = app.buttons["Load earlier messages"]
        let marker = app.staticTexts["History marker 16"]
        for _ in 0..<12 {
            if load.isHittable && load.frame.minY >= timeline.frame.minY && marker.isHittable { break }
            timeline.swipeDown()
        }
        XCTAssertTrue(load.isHittable)
        XCTAssertTrue(marker.isHittable)
        let before = marker.frame.minY
        load.tap()
        XCTAssertTrue(marker.isHittable)
        XCTAssertEqual(marker.frame.minY, before, accuracy: 5)
        capture("19-history-long-message-preview", app: app)
    }

    func testHistoryRetryAndFinalPageWithPreviewData() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--history-demo", "--history-error-demo", "--reset-demo-draft"]; app.launch()
        app.staticTexts["Build a native iOS client"].tap()
        let timeline = app.scrollViews["conversation-timeline"]
        let load = app.buttons["Load earlier messages"]
        for _ in 0..<10 { if load.isHittable { break }; timeline.swipeDown() }
        load.tap()
        let failure = app.staticTexts["The server returned HTTP 503."]
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        capture("20-history-retry-preview", app: app)
        let marker = app.staticTexts["History marker 16"]
        let beforeRetry = marker.frame.minY
        app.buttons["Retry earlier messages"].tap()
        XCTAssertFalse(failure.exists)
        XCTAssertTrue(marker.isHittable)
        XCTAssertEqual(marker.frame.minY, beforeRetry, accuracy: 5)
        capture("21-history-recovered-preview", app: app)
        for _ in 0..<12 { if load.isHittable { break }; timeline.swipeDown() }
        let older = app.staticTexts["History marker 8"]
        XCTAssertTrue(older.isHittable)
        let beforeFinal = older.frame.minY
        load.tap()
        XCTAssertFalse(load.exists)
        XCTAssertTrue(older.isHittable)
        XCTAssertEqual(older.frame.minY, beforeFinal, accuracy: 5)
        capture("22-history-final-page-preview", app: app)
        app.buttons["Jump to latest message"].tap()
        XCTAssertTrue(app.staticTexts["History marker 23"].isHittable)
        capture("23-history-jump-latest-preview", app: app)
    }

    func testPairWithRealHostWhenProvided() throws {
        let link = ProcessInfo.processInfo.environment["T3_NATIVE_PAIRING_URL"] ?? ProcessInfo.processInfo.environment["TEST_RUNNER_T3_NATIVE_PAIRING_URL"] ?? ""
        guard !link.isEmpty else { throw XCTSkip("Set TEST_RUNNER_T3_NATIVE_PAIRING_URL for a scoped test host.") }
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["Connections"].waitForExistence(timeout: 10))
        app.buttons["Connections"].tap()
        let input = app.descendants(matching: .any).matching(identifier: "pairing-link").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText(link)
        app.buttons["Connect"].tap()
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 25))
        capture("06-real-host-connected", app: app)
    }
    func testCaptureConnectedPhoneWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["T3_NATIVE_CAPTURE_CONNECTED"] == "1" || ProcessInfo.processInfo.environment["TEST_RUNNER_T3_NATIVE_CAPTURE_CONNECTED"] == "1" else {
            throw XCTSkip("Opt-in read-only capture of the phone's saved environment.")
        }
        let app = XCUIApplication(); app.launch()
        let status = app.buttons["connection-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let connected = NSPredicate(format: "value == %@", "Connected")
        expectation(for: connected, evaluatedWith: status)
        waitForExpectations(timeout: 30)
        capture("01-live-t3-threads", app: app)
        app.buttons["New conversation"].tap()
        XCTAssertTrue(app.navigationBars["New conversation"].waitForExistence(timeout: 5))
        capture("13-live-new-conversation", app: app)
        app.buttons["Cancel"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "thread-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        XCTAssertTrue(messageInput(app).waitForExistence(timeout: 10))
        app.buttons["Jump to latest message"].tap()
        capture("02-live-t3-conversation", app: app)
        app.buttons["model-settings"].tap()
        XCTAssertTrue(app.navigationBars["Model"].waitForExistence(timeout: 5))
        capture("12-live-model-catalog", app: app)
        app.buttons["Cancel"].tap()
        messageInput(app).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        capture("03-live-t3-keyboard", app: app)
    }

    func testUpstreamThemeVariantsWithPreviewData() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        app.buttons["Appearance and text size"].tap()
        app.buttons["theme-choice"].tap()
        app.buttons["T3 Chat"].tap()
        capture("06-t3-chat-appearance", app: app)
        app.buttons["Done"].tap()
        capture("07-t3-chat-dark-threads", app: app)
        app.buttons["Appearance and text size"].tap()
        app.buttons["appearance-choice"].tap()
        app.buttons["Light"].tap()
        app.buttons["Done"].tap()
        capture("08-t3-chat-light-threads", app: app)
        app.buttons["Appearance and text size"].tap()
        app.buttons["theme-choice"].tap(); app.buttons["T3 Code"].tap()
        app.buttons["appearance-choice"].tap(); app.buttons["System"].tap()
        app.buttons["Done"].tap()
    }

}
