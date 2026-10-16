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
        XCTAssertTrue(app.staticTexts["History marker 15"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.staticTexts["History marker 15"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.staticTexts["History marker 15"].waitForExistence(timeout: 5))
        XCTAssertFalse(failure.exists)
        XCTAssertTrue(marker.isHittable)
        XCTAssertEqual(marker.frame.minY, beforeRetry, accuracy: 5)
        capture("21-history-recovered-preview", app: app)
        for _ in 0..<12 { if load.isHittable { break }; timeline.swipeDown() }
        let older = app.staticTexts["History marker 8"]
        XCTAssertTrue(older.isHittable)
        let beforeFinal = older.frame.minY
        load.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: load)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(load.exists)
        XCTAssertTrue(older.isHittable)
        XCTAssertEqual(older.frame.minY, beforeFinal, accuracy: 5)
        capture("22-history-final-page-preview", app: app)
        app.buttons["Jump to latest message"].tap()
        XCTAssertTrue(app.staticTexts["History marker 23"].isHittable)
        capture("23-history-jump-latest-preview", app: app)
    }

    func testNativeAttachmentPreviewWithPreviewData() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--attachments-demo", "--reset-demo-draft"]; app.launch()
        app.staticTexts["Build a native iOS client"].tap()
        let pdf = app.buttons["Open Notes.pdf"]
        XCTAssertTrue(pdf.waitForExistence(timeout: 5))
        capture("25-attachment-list-preview", app: app)
        pdf.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Native attachment preview")).firstMatch.waitForExistence(timeout: 10))
        capture("26-native-pdf-preview", app: app)
        app.buttons["Done"].tap()
        XCTAssertTrue(pdf.waitForExistence(timeout: 5))
        app.buttons["Open Layout.png"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        capture("27-native-image-preview", app: app)
        app.buttons["Done"].tap()
        app.buttons["Open Connection.txt"].tap()
        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 5))
        capture("28-attachment-retry-preview", app: app)
        app.buttons["Retry"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        capture("29-native-text-preview", app: app)
        app.buttons["Done"].tap()
        XCTAssertTrue(pdf.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Open Future attachment"].isEnabled)
        app.buttons["Open Layout.png"].tap()
        XCTAssertTrue(app.buttons["Share"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Share"].firstMatch.tap()
        capture("30-native-share-preview", app: app)
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
    func testRemovingOneServerPreservesTheOtherWithPreviewData() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--host-removal-preview"]; app.launch()
        let status = app.buttons["connection-status"]
        expectation(for: NSPredicate(format: "value == %@", "Preview data"), evaluatedWith: status)
        waitForExpectations(timeout: 10)
        app.buttons["Connections"].tap()
        let alpha = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Alpha server")).firstMatch
        let beta = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Beta server")).firstMatch
        XCTAssertTrue(alpha.waitForExistence(timeout: 5)); XCTAssertTrue(beta.exists)
        capture("40-two-server-removal-fixture-preview", app: app)
        alpha.swipeLeft(); app.buttons["Remove"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Remove server"].waitForExistence(timeout: 5))
        capture("41-server-draft-removal-confirmation-preview", app: app)
        app.staticTexts["Add a server"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertFalse(app.buttons["Remove server"].exists)
        XCTAssertTrue(alpha.exists); XCTAssertTrue(beta.exists)
        alpha.swipeLeft(); app.buttons["Remove"].firstMatch.tap()
        app.buttons["Remove server"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: alpha)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(beta.exists)
        XCTAssertEqual(beta.value as? String, "Selected")
        capture("42-other-server-preserved-preview", app: app)
    }
    func testUnassignedLegacyDraftsRemainVisibleAfterServerRemovalWithPreviewData() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--host-removal-preview", "--legacy-removal-preview"]; app.launch()
        expectation(for: NSPredicate(format: "value == %@", "Preview data"), evaluatedWith: app.buttons["connection-status"])
        waitForExpectations(timeout: 10)
        app.buttons["Connections"].tap()
        let alpha = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Alpha server")).firstMatch
        XCTAssertTrue(alpha.waitForExistence(timeout: 5)); alpha.swipeLeft(); app.buttons["Remove"].firstMatch.tap()
        app.buttons["Remove server"].tap()
        XCTAssertTrue(app.staticTexts["Older attachment drafts without server information were kept on this device."].waitForExistence(timeout: 5))
        capture("43-unassigned-drafts-preserved-preview", app: app)
    }
    func testFailedDraftCleanupKeepsServerAvailableWithPreviewData() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--host-removal-preview", "--failed-removal-preview"]; app.launch()
        expectation(for: NSPredicate(format: "value == %@", "Preview data"), evaluatedWith: app.buttons["connection-status"])
        waitForExpectations(timeout: 10)
        app.buttons["Connections"].tap()
        let alpha = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Alpha server")).firstMatch
        XCTAssertTrue(alpha.waitForExistence(timeout: 5)); alpha.swipeLeft(); app.buttons["Remove"].firstMatch.tap()
        app.buttons["Remove server"].tap()
        XCTAssertTrue(app.staticTexts["Could not clear this server's attachment drafts. The server is still saved."].waitForExistence(timeout: 5))
        XCTAssertTrue(alpha.exists)
        capture("44-cleanup-failure-keeps-server-preview", app: app)
    }
    func testNativePhotosPickerWithPreviewData() throws {
        let env = ProcessInfo.processInfo.environment
        let count = Int(env["T3_NATIVE_PHOTO_FIXTURE_COUNT"] ?? env["TEST_RUNNER_T3_NATIVE_PHOTO_FIXTURE_COUNT"] ?? "") ?? 0
        guard (2...3).contains(count) else { throw XCTSkip("Seed photo fixtures and set TEST_RUNNER_T3_NATIVE_PHOTO_FIXTURE_COUNT.") }
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--attachment-draft-demo", "--reset-demo-attachments"]; app.launch()
        app.staticTexts["Build a native iOS client"].tap()
        let attach = app.buttons["attach-files"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: attach)
        waitForExpectations(timeout: 5)
        attach.tap(); capture("48-photo-source-menu-preview", app: app)
        app.buttons["Choose photos"].tap()
        let photos = app.images.matching(identifier: "PXGGridLayout-Info")
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 30))
        capture("49-native-photo-picker-preview", app: app)
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.scrollViews["draft-attachments"].exists)
        attach.tap(); app.buttons["Choose photos"].tap()
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 30))
        XCTAssertGreaterThanOrEqual(photos.count, count)
        for index in 0..<count { photos.element(boundBy: index).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        capture("50-selected-photos-preview", app: app)
        app.buttons["Done"].tap()
        let chips = app.scrollViews["draft-attachments"]
        XCTAssertTrue(chips.waitForExistence(timeout: 15))
        let remove = chips.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Remove "))
        expectation(for: NSPredicate(format: "count == %d", count), evaluatedWith: remove)
        waitForExpectations(timeout: 15)
        XCTAssertTrue(chips.staticTexts["T3 Photo Fixture 1.png"].exists)
        XCTAssertTrue(chips.staticTexts["T3 Photo Fixture 2.jpeg"].exists)
        if count == 3 { XCTAssertTrue(chips.staticTexts["T3 Photo Fixture 3.jpeg"].exists, "Photos should supply a compatible JPEG for HEIC.") }
        XCTAssertFalse(app.buttons["send-message"].isEnabled, "Preview photos cannot send to a host.")
        capture("51-photo-drafts-preview", app: app)
        chips.swipeLeft(); capture("52-photo-drafts-scrolled-preview", app: app)
        app.terminate(); app.launchArguments = ["--demo", "--attachment-draft-demo"]; app.launch()
        app.staticTexts["Build a native iOS client"].tap()
        expectation(for: NSPredicate(format: "count == %d", count), evaluatedWith: remove)
        waitForExpectations(timeout: 10)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.staticTexts["Review the reconnect behavior"].tap()
        XCTAssertFalse(chips.exists, "Photo drafts belong to their original conversation.")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.staticTexts["Build a native iOS client"].tap()
        expectation(for: NSPredicate(format: "count == %d", count), evaluatedWith: remove)
        waitForExpectations(timeout: 10)
        capture("53-photo-drafts-after-relaunch-preview", app: app)
        for remaining in (1...count).reversed() {
            remove.firstMatch.tap()
            expectation(for: NSPredicate(format: "count == %d", remaining - 1), evaluatedWith: remove)
            waitForExpectations(timeout: 5)
        }
        capture("54-photo-drafts-removed-preview", app: app)
    }
    func testPhotoSizeLimitAndRecoveryWhenFixtureProvided() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["T3_NATIVE_PHOTO_LIMIT_FIXTURE"] == "1" || env["TEST_RUNNER_T3_NATIVE_PHOTO_LIMIT_FIXTURE"] == "1" else {
            throw XCTSkip("Seed the oversized photo fixture as the newest image.")
        }
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--attachment-draft-demo", "--reset-demo-attachments"]; app.launch()
        app.staticTexts["Build a native iOS client"].tap()
        let attach = app.buttons["attach-files"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: attach); waitForExpectations(timeout: 5)
        attach.tap(); app.buttons["Choose photos"].tap()
        let photos = app.images.matching(identifier: "PXGGridLayout-Info")
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 30))
        photos.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["Done"].tap()
        let error = app.staticTexts["Choose a photo no larger than 10 MiB."]
        XCTAssertTrue(error.waitForExistence(timeout: 20))
        XCTAssertFalse(app.scrollViews["draft-attachments"].exists)
        capture("55-photo-size-limit-preview", app: app)
        app.buttons["Dismiss attachment error"].tap()
        attach.tap(); app.buttons["Choose photos"].tap()
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 30))
        photos.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["Done"].tap()
        let chips = app.scrollViews["draft-attachments"]
        XCTAssertTrue(chips.waitForExistence(timeout: 20)); XCTAssertFalse(error.exists)
        capture("56-photo-size-limit-recovered-preview", app: app)
        chips.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Remove ")).firstMatch.tap()
    }
    func testNativeToolDetailsWithPreviewData() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--tools-demo", "--reset-demo-draft"]; app.launch()
        app.staticTexts["Build a native iOS client"].tap()
        func tool(_ title: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch }
        func outerScrollUp() {
            let scroll = app.scrollViews["conversation-timeline"]
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.85)).press(forDuration: 0.05,
                thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.2)))
        }
        XCTAssertTrue(tool("Inspect build result").waitForExistence(timeout: 10))
        capture("64-native-tools-collapsed-preview", app: app)
        tool("Inspect build result").tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "includeWarnings")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "artifact")).firstMatch.waitForExistence(timeout: 10))
        capture("65-native-structured-tool-preview", app: app)
        tool("Inspect build result").tap()
        tool("Run native checks").tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "All native checks passed")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Exit 0"].exists)
        app.buttons.matching(identifier: "Copy").element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["Copied"].firstMatch.waitForExistence(timeout: 5))
        capture("66-native-full-command-output-preview", app: app)
        tool("Run native checks").tap()
        tool("Retry failed command output").tap()
        XCTAssertTrue(app.buttons["Retry output"].waitForExistence(timeout: 10))
        capture("67-native-tool-error-preview", app: app)
        app.buttons["Retry output"].tap()
        XCTAssertTrue(app.staticTexts["Exit 1"].waitForExistence(timeout: 10))
        capture("68-native-tool-error-recovered-preview", app: app)
        tool("Retry failed command output").tap()
        tool("Read a long result").tap()
        let limit = app.staticTexts["Showing a shortened result. Copy includes only the displayed portion."]
        XCTAssertTrue(limit.waitForExistence(timeout: 10))
        for _ in 0..<4 { if limit.isHittable { break }; outerScrollUp() }
        XCTAssertTrue(limit.isHittable)
        capture("69-native-bounded-tool-output-preview", app: app)
        tool("Read a long result").tap()
        tool("Removed output").tap()
        XCTAssertTrue(app.staticTexts["Output is no longer available."].waitForExistence(timeout: 10))
        capture("70-native-missing-tool-output-preview", app: app)
        tool("Removed output").tap()
        tool("Inspect an active command").tap()
        XCTAssertTrue(app.staticTexts["Running fixture output snapshot 1"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Refresh output"].exists)
        capture("71-native-active-tool-output-preview", app: app)
        app.buttons["Refresh output"].tap()
        XCTAssertTrue(app.staticTexts["Running fixture output snapshot 2"].waitForExistence(timeout: 10))
        capture("72-native-refreshed-tool-output-preview", app: app)
    }
    func testUnsentAttachmentsOpenLocalNativePreviewsWithPreviewData() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--attachment-draft-demo", "--reset-demo-draft", "--reset-demo-attachments"]
        app.launch(); app.staticTexts["Build a native iOS client"].tap()
        let attach = app.buttons["attach-files"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: attach)
        waitForExpectations(timeout: 5)
        attach.tap(); app.buttons["Sample text"].tap()
        let text = app.buttons["Preview draft Composer notes.txt"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        attach.tap(); app.buttons["Sample image"].tap()
        let image = app.buttons["Preview draft Composer image.png"]
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        capture("59-unsent-attachment-buttons-preview", app: app)
        text.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Native T3 attachment draft")).firstMatch.waitForExistence(timeout: 10))
        capture("60-unsent-native-text-preview", app: app)
        app.buttons["Done"].tap()
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        image.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        capture("61-unsent-native-image-preview", app: app)
        app.buttons["Done"].tap()
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["--demo", "--attachment-draft-demo"]; app.launch()
        app.staticTexts["Build a native iOS client"].tap()
        XCTAssertTrue(text.waitForExistence(timeout: 5)); XCTAssertTrue(image.exists)
        capture("62-draft-preserved-after-previews-preview", app: app)
        text.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Share"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Share"].firstMatch.tap()
        capture("63-unsent-native-share-preview", app: app)
    }
    func testAttachmentDraftRestoresAndUsesNativeFilesPickerWithPreviewData() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--attachment-draft-demo", "--reset-demo-draft", "--reset-demo-attachments"]
        app.launch(); app.staticTexts["Build a native iOS client"].tap()
        let attach = app.buttons["attach-files"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: attach)
        waitForExpectations(timeout: 5)
        capture("33-composer-attachment-control-preview", app: app)
        attach.tap(); app.buttons["Empty sample"].tap()
        XCTAssertTrue(app.staticTexts["'Composer empty.txt' is empty."].waitForExistence(timeout: 5))
        capture("34-attachment-import-error-preview", app: app)
        app.buttons["Dismiss attachment error"].tap()
        attach.tap(); app.buttons["Sample text"].tap()
        XCTAssertTrue(app.buttons["Remove Composer notes.txt"].waitForExistence(timeout: 5))
        attach.tap(); app.buttons["Sample image"].tap()
        XCTAssertTrue(app.buttons["Remove Composer image.png"].waitForExistence(timeout: 5))
        capture("35-composer-file-image-draft-preview", app: app)
        app.terminate()
        app.launchArguments = ["--demo", "--attachment-draft-demo"]
        app.launch(); app.staticTexts["Build a native iOS client"].tap()
        XCTAssertTrue(app.buttons["Remove Composer notes.txt"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Remove Composer image.png"].exists)
        XCTAssertFalse(app.buttons["send-message"].isEnabled, "Preview data cannot send to a host.")
        capture("36-attachment-draft-after-relaunch-preview", app: app)
        attach.tap(); app.buttons["Choose files"].tap()
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 30))
        capture("37-native-file-picker-preview", app: app)
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Remove Composer image.png"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["--demo", "--attachment-draft-demo", "--attachment-upload-preview"]
        app.launch(); app.staticTexts["Build a native iOS client"].tap()
        XCTAssertTrue(app.buttons["Cancel upload"].waitForExistence(timeout: 5))
        capture("39-upload-progress-fixture-preview", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.staticTexts["Review the reconnect behavior"].tap()
        XCTAssertTrue(app.buttons["attach-files"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Cancel upload"].exists, "Upload progress belongs to its original conversation.")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.staticTexts["Build a native iOS client"].tap()
        XCTAssertTrue(app.buttons["Cancel upload"].waitForExistence(timeout: 5))
        app.buttons["Cancel upload"].tap()
        XCTAssertFalse(app.buttons["Cancel upload"].exists)
        XCTAssertTrue(app.buttons["Remove Composer notes.txt"].exists)
        app.buttons["Remove Composer image.png"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["Remove Composer image.png"])
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.buttons["Remove Composer notes.txt"].exists)
        app.buttons["Remove Composer notes.txt"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["Remove Composer notes.txt"])
        waitForExpectations(timeout: 5)
        capture("38-attachment-draft-removed-preview", app: app)
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
        app.buttons["attach-files"].tap()
        XCTAssertTrue(app.buttons["Choose photos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose files"].exists)
        XCTAssertFalse(app.buttons["Sample image"].exists)
        capture("57-live-attachment-sources", app: app)
        app.buttons["Choose photos"].tap()
        XCTAssertTrue(app.images.matching(identifier: "PXGGridLayout-Info").firstMatch.waitForExistence(timeout: 30))
        capture("58-live-host-photo-picker-fixture-library", app: app)
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
