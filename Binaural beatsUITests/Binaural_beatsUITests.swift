//
//  Binaural_beatsUITests.swift
//  Binaural beatsUITests
//
//  App Store 用スクリーンショットを自動撮影する UI テスト。
//  言語は起動引数で強制し、コントロールは accessibilityIdentifier で操作するため
//  表示言語に依存しない。撮影結果は keepAlways の添付として .xcresult に保存され、
//  `xcrun xcresulttool export attachments` で取り出せる。
//

import XCTest

final class Binaural_beatsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-UITestQuiet",   // 通知許可ダイアログを抑止
            "-UITestSeed",    // 履歴グラフ用のサンプルデータを投入
        ]
        app.launch()

        // 1) Sounds（バイノーラル一覧）
        XCTAssertTrue(app.buttons["ambienceButton"].waitForExistence(timeout: 20))
        pause()
        snap("01-Sounds")

        // 2) Ambience（環境音ミキサー）
        app.buttons["ambienceButton"].tap()
        pause()
        snap("02-Ambience")
        if app.buttons["doneButton"].waitForExistence(timeout: 5) {
            app.buttons["doneButton"].tap()
        }

        // Pomodoro タブへ（iPad の新フローティングタブバーは Cell として見えるため
        // 複数の要素タイプをラベルで試す。言語は英語に固定済み）
        tapTab(named: "Pomodoro", in: app)

        // 3) Pomodoro（実行中のリング）
        if app.buttons["startButton"].waitForExistence(timeout: 10) {
            app.buttons["startButton"].tap()
        }
        pause(1_500_000)
        snap("03-Pomodoro")

        // 4) History（集中時間の推移グラフ）
        if app.buttons["historyButton"].waitForExistence(timeout: 10) {
            app.buttons["historyButton"].tap()
        }
        pause()
        snap("04-History")
        // 戻る
        if app.navigationBars.buttons.element(boundBy: 0).exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        // 5) Settings（iCloud 同期）
        if app.buttons["settingsButton"].waitForExistence(timeout: 10) {
            app.buttons["settingsButton"].tap()
        }
        pause()
        snap("05-Settings")
    }

    // MARK: - Helpers

    /// タブバー実装（従来型 / iPad のフローティング型）に依存せずタブをタップする。
    private func tapTab(named label: String, in app: XCUIApplication) {
        let candidates: [XCUIElement] = [
            app.tabBars.buttons[label].firstMatch,
            app.buttons[label].firstMatch,
            app.cells[label].firstMatch,
            app.staticTexts[label].firstMatch,
        ]
        for element in candidates where element.waitForExistence(timeout: 3) {
            element.tap()
            return
        }
        // 最終手段：ラベル一致する任意要素
        let any = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label)).firstMatch
        if any.waitForExistence(timeout: 3) { any.tap() }
    }

    private func pause(_ microseconds: useconds_t = 900_000) {
        usleep(microseconds)
    }

    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
