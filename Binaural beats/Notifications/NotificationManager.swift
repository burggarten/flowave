//
//  NotificationManager.swift
//  Binaural beats
//
//  ポモドーロのフェーズ切替を知らせるローカル通知を管理する。
//  バックグラウンド／ロック中でも指定時刻に通知が届く。
//

import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private(set) var isAuthorized = false

    override init() {
        super.init()
        center.delegate = self
    }

    /// 通知の許可をリクエストする。
    func requestAuthorization() async {
        // UIテスト（スクリーンショット撮影）中はシステムの許可ダイアログを出さない。
        if ProcessInfo.processInfo.arguments.contains("-UITestQuiet") { return }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
        } catch {
            isAuthorized = false
        }
    }

    /// 指定秒数後に通知を予約する。
    func schedule(id: String, after seconds: TimeInterval, title: String, body: String) {
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)
    }

    /// 予約済みの通知をすべて取り消す。
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// フォアグラウンドでもバナーと音で通知する。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
