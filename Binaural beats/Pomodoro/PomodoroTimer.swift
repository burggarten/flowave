//
//  PomodoroTimer.swift
//  Binaural beats
//
//  ポモドーロタイマー。2つのモードを切り替え可能：
//   - simple: 1回だけのカウントダウン（集中時間のみ）
//   - cycle : 作業／休憩を設定セット数だけ繰り返す
//
//  タイマーは「開始時刻＋スケジュール記述子（SessionDescriptor）」で表現し、
//  現在のフェーズ・残り時間は絶対時刻から算出する。この記述子を iCloud で共有するため、
//  別の端末に持ち替えても、アプリを再起動しても、同じセッションがそのまま続く。
//  各端末は記述子から通知を自前で予約し、完了した集中フェーズは決定的IDで履歴に記録する
//  （同一フェーズを複数端末が記録しても重複しない）。
//

import Foundation
import Observation

@MainActor
@Observable
final class PomodoroTimer {

    enum Mode: String, CaseIterable, Identifiable {
        case simple
        case cycle
        var id: String { rawValue }
        var title: String {
            switch self {
            case .simple: return String(localized: "シンプル")
            case .cycle:  return String(localized: "サイクル")
            }
        }
    }

    /// 現在のフェーズ
    enum Phase: Equatable {
        case idle          // 未開始
        case focus         // 集中中
        case breakTime     // 休憩中
        case finished      // すべて完了
    }

    // MARK: - 設定（ユーザが自由に変更）
    var mode: Mode = .simple
    /// シンプルモードの集中時間（分）
    var simpleMinutes: Int = 30
    /// サイクルモードの作業時間（分）
    var focusMinutes: Int = 25
    /// サイクルモードの休憩時間（分）
    var breakMinutes: Int = 5
    /// サイクルモードのセット数
    var totalSets: Int = 4
    /// 休憩中に音を止めるか
    var pauseAudioOnBreak: Bool = true

    // MARK: - 状態（UI が監視、記述子から算出）
    private(set) var phase: Phase = .idle
    private(set) var remaining: TimeInterval = 0
    private(set) var currentSet: Int = 1
    private(set) var isPaused = false

    var isActive: Bool { phase == .focus || phase == .breakTime }

    /// フェーズ全体の長さ（進捗リング用）
    private(set) var phaseDuration: TimeInterval = 1

    // MARK: - 同期用の記述子

    /// 実行中セッションを一意に表す記述子。これを iCloud に共有して端末間で同期する。
    private struct SessionDescriptor: Codable, Equatable {
        var sessionID: UUID
        var mode: String            // "simple" / "cycle"
        var startDate: Date         // タイムライン起点（一時停止再開時にずらす）
        var focusSeconds: Int       // 集中フェーズ1回の長さ
        var breakSeconds: Int       // 休憩フェーズ1回の長さ
        var totalSets: Int
        var pauseAudioOnBreak: Bool
        var pausedAt: Date?         // 一時停止中の時刻（nil なら進行中）
        var updatedAt: Date         // 変更検知用
    }

    /// タイムライン上の1ブロック（1フェーズ）。
    private struct Block {
        let phase: Phase
        let start: TimeInterval
        let end: TimeInterval
        let set: Int
    }

    // MARK: - 内部
    private let notifications: NotificationManager
    private let history: PomodoroHistoryStore
    private let cloud: CloudKeyValueStore
    private static let activeKey = "pomodoro.activeSession"

    private var descriptor: SessionDescriptor?
    /// このセッションで既に履歴記録済みの集中セット番号。
    private var recordedFocusSets: Set<Int> = []
    private var tickTask: Task<Void, Never>?

    init(notifications: NotificationManager, history: PomodoroHistoryStore, cloud: CloudKeyValueStore) {
        self.notifications = notifications
        self.history = history
        self.cloud = cloud
        // 他端末・再起動時に進行中セッションを取り込む。
        cloud.addListener { [weak self] in self?.adoptRemote() }
        adoptRemote()
    }

    // MARK: - 表示補助

    var remainingText: String {
        let total = max(0, Int(remaining.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var phaseTitle: String {
        switch phase {
        case .idle:      return String(localized: "準備完了")
        case .focus:     return mode == .simple
            ? String(localized: "集中")
            : String(localized: "集中（\(currentSet)/\(totalSets)）")
        case .breakTime: return String(localized: "休憩")
        case .finished:  return String(localized: "完了")
        }
    }

    /// 0...1 の進捗（経過割合）
    var progress: Double {
        guard phaseDuration > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / phaseDuration))
    }

    // MARK: - 操作

    func start() {
        Task { await notifications.requestAuthorization() }
        let now = Date()
        let focusMinutes = mode == .simple ? simpleMinutes : self.focusMinutes
        let descriptor = SessionDescriptor(
            sessionID: UUID(),
            mode: mode.rawValue,
            startDate: now,
            focusSeconds: max(1, focusMinutes) * 60,
            breakSeconds: max(1, breakMinutes) * 60,
            totalSets: mode == .simple ? 1 : totalSets,
            pauseAudioOnBreak: pauseAudioOnBreak,
            pausedAt: nil,
            updatedAt: now
        )
        activate(descriptor, publish: true)
    }

    func togglePause() {
        guard var descriptor, isActive else { return }
        let now = Date()
        if let pausedAt = descriptor.pausedAt {
            // 再開：一時停止していた分だけ起点を後ろへずらす。
            descriptor.startDate = descriptor.startDate.addingTimeInterval(now.timeIntervalSince(pausedAt))
            descriptor.pausedAt = nil
        } else {
            descriptor.pausedAt = now
        }
        descriptor.updatedAt = now
        activate(descriptor, publish: true)
    }

    func reset() {
        resetState(publishClear: true)
    }

    /// 実行中のセッションがあれば現在の保存先へ公開する。
    /// iCloud をセッション中に有効化したとき、進行中セッションを他端末へ届けるために使う。
    func publishActiveIfNeeded() {
        guard let descriptor, let data = try? JSONEncoder().encode(descriptor) else { return }
        cloud.set(data, forKey: Self.activeKey)
    }

    // MARK: - セッションの適用

    /// 記述子を有効化し、通知予約・ティック・（必要なら）iCloud への公開を行う。
    private func activate(_ descriptor: SessionDescriptor, publish: Bool) {
        self.descriptor = descriptor
        recordedFocusSets = []
        applySettings(from: descriptor)

        if publish {
            if let data = try? JSONEncoder().encode(descriptor) {
                cloud.set(data, forKey: Self.activeKey)
            }
        }

        scheduleNotifications(for: descriptor)

        if descriptor.pausedAt == nil {
            startTicking()
        } else {
            stopTicking()
            notifications.cancelAll()
        }
        tick()
    }

    /// 実行中セッションの設定を、表示用のプロパティへ反映する。
    private func applySettings(from descriptor: SessionDescriptor) {
        mode = descriptor.mode == "cycle" ? .cycle : .simple
        if descriptor.mode == "simple" {
            simpleMinutes = descriptor.focusSeconds / 60
        } else {
            focusMinutes = descriptor.focusSeconds / 60
            breakMinutes = descriptor.breakSeconds / 60
            totalSets = descriptor.totalSets
        }
        pauseAudioOnBreak = descriptor.pauseAudioOnBreak
    }

    private func resetState(publishClear: Bool) {
        stopTicking()
        notifications.cancelAll()
        descriptor = nil
        recordedFocusSets = []
        phase = .idle
        isPaused = false
        currentSet = 1
        remaining = 0
        phaseDuration = 1
        if publishClear {
            cloud.set(nil, forKey: Self.activeKey)
        }
    }

    // MARK: - iCloud からの取り込み

    /// iCloud 上の実行中セッションを取り込む（他端末・再起動・保存先切替時）。
    private func adoptRemote() {
        guard let data = cloud.data(forKey: Self.activeKey),
              let remote = try? JSONDecoder().decode(SessionDescriptor.self, from: data) else {
            // リモートでセッションが終了／削除された。こちらが実行中なら合わせて停止する。
            if descriptor != nil {
                resetState(publishClear: false)
            }
            return
        }
        // 変化が無ければ何もしない（再スケジュールの無駄打ちを防ぐ）。
        guard descriptor != remote else { return }
        activate(remote, publish: false)
    }

    // MARK: - タイムライン

    /// 記述子からフェーズのブロック列を組み立てる。
    private func blocks(for descriptor: SessionDescriptor) -> [Block] {
        var result: [Block] = []
        var offset: TimeInterval = 0
        let focus = TimeInterval(descriptor.focusSeconds)
        let brk = TimeInterval(descriptor.breakSeconds)
        let isCycle = descriptor.mode == "cycle"

        for set in 1...max(1, descriptor.totalSets) {
            result.append(Block(phase: .focus, start: offset, end: offset + focus, set: set))
            offset += focus
            let isLast = set == descriptor.totalSets
            if isCycle && !isLast && brk > 0 {
                result.append(Block(phase: .breakTime, start: offset, end: offset + brk, set: set))
                offset += brk
            }
        }
        return result
    }

    // MARK: - ティック

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    /// 現在時刻（一時停止中は停止時刻）から状態を算出する。
    private func tick() {
        guard let descriptor else { return }
        let now = descriptor.pausedAt ?? Date()
        let elapsed = max(0, now.timeIntervalSince(descriptor.startDate))
        let blocks = blocks(for: descriptor)

        // 完了した集中フェーズを履歴に記録（決定的IDで端末間の重複を防ぐ）。
        for block in blocks where block.phase == .focus
        && elapsed >= block.end
        && !recordedFocusSets.contains(block.set) {
            recordedFocusSets.insert(block.set)
            let id = PomodoroSession.deterministicID("\(descriptor.sessionID.uuidString)-focus-\(block.set)")
            history.record(
                id: id,
                focusMinutes: descriptor.focusSeconds / 60,
                mode: descriptor.mode == "simple" ? .simple : .cycle,
                date: descriptor.startDate.addingTimeInterval(block.end)
            )
        }

        isPaused = descriptor.pausedAt != nil

        guard let total = blocks.last?.end else { return }

        if elapsed >= total {
            phase = .finished
            currentSet = descriptor.totalSets
            remaining = 0
            phaseDuration = 1
            stopTicking()
            return
        }

        if let block = blocks.first(where: { elapsed >= $0.start && elapsed < $0.end }) {
            phase = block.phase
            currentSet = block.set
            phaseDuration = block.end - block.start
            remaining = block.end - elapsed
        }
    }

    // MARK: - 通知

    /// 記述子に沿って、各フェーズ境界のローカル通知を予約する。
    private func scheduleNotifications(for descriptor: SessionDescriptor) {
        notifications.cancelAll()
        guard descriptor.pausedAt == nil else { return }

        let blocks = blocks(for: descriptor)
        for (index, block) in blocks.enumerated() {
            let after = descriptor.startDate.addingTimeInterval(block.end).timeIntervalSinceNow
            guard after > 0 else { continue }

            let isLastBlock = index == blocks.count - 1
            let title: String
            let body: String

            switch block.phase {
            case .focus:
                if isLastBlock {
                    if descriptor.mode == "simple" {
                        title = String(localized: "集中完了")
                        body = String(localized: "お疲れさまでした。集中セッションが終了しました。")
                    } else {
                        title = String(localized: "すべて完了")
                        body = String(localized: "全\(descriptor.totalSets)セットが完了しました。お疲れさまでした。")
                    }
                } else {
                    title = String(localized: "休憩の時間です")
                    body = String(localized: "\(descriptor.breakSeconds / 60)分間の休憩を取りましょう。")
                }
            case .breakTime:
                title = String(localized: "集中の時間です")
                body = String(localized: "休憩終了。次のセット（\(block.set + 1)/\(descriptor.totalSets)）を始めましょう。")
            default:
                continue
            }

            notifications.schedule(
                id: "pomodoro.\(descriptor.sessionID.uuidString).\(index)",
                after: after,
                title: title,
                body: body
            )
        }
    }
}
