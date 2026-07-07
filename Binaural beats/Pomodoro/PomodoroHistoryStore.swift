//
//  PomodoroHistoryStore.swift
//  Binaural beats
//
//  完了した集中セッションの履歴を保持するストア。保存先（iCloud / ローカル）は
//  CloudKeyValueStore が AppSettings のトグルに応じて切り替える。
//  他デバイスや保存先切替の通知を受けて再読み込みし、UUID をキーに和集合マージするため
//  セッションの取りこぼしを避けられる。
//

import Foundation
import Observation

@MainActor
@Observable
final class PomodoroHistoryStore {

    /// 日付昇順に並んだ全セッション。
    private(set) var sessions: [PomodoroSession] = []

    private let cloud: CloudKeyValueStore
    private let key = "pomodoro.history.sessions"

    init(cloud: CloudKeyValueStore) {
        self.cloud = cloud
        load()
        // 他デバイスからの変更・保存先切替に応じて再読み込みする。
        cloud.addListener { [weak self] in self?.load() }
    }

    // MARK: - 記録

    /// 完了した集中フェーズを1件記録する。
    /// id を明示すると、同じ完了フェーズを複数端末が記録しても重複しない（決定的ID）。
    func record(id: UUID = UUID(), focusMinutes: Int, mode: PomodoroSession.Mode, date: Date = Date()) {
        guard !sessions.contains(where: { $0.id == id }) else { return }
        let session = PomodoroSession(id: id, date: date, focusMinutes: focusMinutes, mode: mode)
        sessions.append(session)
        sessions.sort { $0.date < $1.date }
        persist()
    }

    /// すべての履歴を削除する。
    func clearAll() {
        sessions.removeAll()
        persist()
    }

    /// UIテスト（スクリーンショット）用のサンプル履歴を投入する（保存はしない）。
    func seedSampleDataForUITests() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let plan: [(offset: Int, minutes: [Int])] = [
            (0, [25, 25, 50]), (1, [25, 25]), (2, [50, 25, 25]), (3, [25]),
            (4, [25, 25, 25, 25]), (5, [50]), (6, [25, 25]), (8, [25, 50]),
            (9, [25, 25, 25]), (11, [50, 25]), (13, [25, 25]),
        ]
        var result: [PomodoroSession] = []
        for (offset, minutes) in plan {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            for (i, m) in minutes.enumerated() {
                let date = day.addingTimeInterval(TimeInterval(9 * 3600 + i * 1800))
                result.append(PomodoroSession(date: date, focusMinutes: m, mode: .cycle))
            }
        }
        sessions = result.sorted { $0.date < $1.date }
    }

    // MARK: - 永続化 / 同期

    /// 保存先から読み込み、現在の値とマージする。
    private func load() {
        guard let data = cloud.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PomodoroSession].self, from: data) else {
            return
        }

        // この端末にしか無いセッションを検出しておく。
        let incomingIDs = Set(decoded.map(\.id))
        let hasLocalOnly = sessions.contains { !incomingIDs.contains($0.id) }

        merge(decoded)

        // ローカル固有のセッションがあれば、保存先へ書き戻して収束を早める。
        if hasLocalOnly {
            persist()
        }
    }

    /// UUID をキーに和集合マージする（既存の値を優先して保持）。
    private func merge(_ incoming: [PomodoroSession]) {
        var byID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { current, _ in current })
        for session in incoming {
            byID[session.id] = session
        }
        sessions = byID.values.sorted { $0.date < $1.date }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        cloud.set(data, forKey: key)
    }
}
