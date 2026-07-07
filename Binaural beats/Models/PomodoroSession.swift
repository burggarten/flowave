//
//  PomodoroSession.swift
//  Binaural beats
//
//  完了した集中セッション1件を表す履歴レコード。
//  iCloud（NSUbiquitousKeyValueStore）に同期するため Codable にしている。
//

import Foundation
import CryptoKit

/// 完了した集中フェーズ1件の記録。
struct PomodoroSession: Identifiable, Codable, Hashable {
    /// セッションのモード種別。
    enum Mode: String, Codable {
        case simple
        case cycle
    }

    /// デバイス間で一意になるよう UUID を用いる（同期時のマージキー）。
    let id: UUID
    /// 集中フェーズが完了した日時。
    let date: Date
    /// この集中フェーズの長さ（分）。
    let focusMinutes: Int
    /// 記録時のモード。
    let mode: Mode

    init(id: UUID = UUID(), date: Date, focusMinutes: Int, mode: Mode) {
        self.id = id
        self.date = date
        self.focusMinutes = focusMinutes
        self.mode = mode
    }

    /// 文字列から決定的な UUID を生成する。
    /// 同じ入力なら常に同じ UUID になるため、複数端末が同一の完了フェーズを記録しても
    /// 履歴ストアの UUID マージで自動的に重複排除される。
    static func deterministicID(_ string: String) -> UUID {
        let digest = SHA256.hash(data: Data(string.utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
