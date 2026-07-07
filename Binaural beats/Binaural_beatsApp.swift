//
//  Binaural_beatsApp.swift
//  Binaural beats
//
//  Created by Tomohiro Hayashi on 2026/07/07.
//

import SwiftUI

@main
struct Binaural_beatsApp: App {
    @State private var settings: AppSettings
    @State private var notifications: NotificationManager
    @State private var audio = BinauralAudioEngine()
    @State private var pomodoro: PomodoroTimer
    @State private var history: PomodoroHistoryStore

    init() {
        let settings = AppSettings()
        let cloud = CloudKeyValueStore(useICloud: settings.useICloud)
        let notifications = NotificationManager()
        let history = PomodoroHistoryStore(cloud: cloud)
        let pomodoro = PomodoroTimer(notifications: notifications, history: history, cloud: cloud)

        // UIテスト（スクリーンショット）用にサンプル履歴を投入する。
        if ProcessInfo.processInfo.arguments.contains("-UITestSeed") {
            history.seedSampleDataForUITests()
        }

        // 設定トグルの変更を保存先ストアへ伝える。有効化時は進行中セッションを公開する。
        settings.onChangeUseICloud = { [cloud, pomodoro] enabled in
            cloud.setUseICloud(enabled)
            if enabled { pomodoro.publishActiveIfNeeded() }
        }

        _settings = State(initialValue: settings)
        _notifications = State(initialValue: notifications)
        _history = State(initialValue: history)
        _pomodoro = State(initialValue: pomodoro)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(audio)
                .environment(pomodoro)
                .environment(history)
                .task {
                    await notifications.requestAuthorization()
                }
        }
    }
}
