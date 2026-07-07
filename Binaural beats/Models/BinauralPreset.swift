//
//  BinauralPreset.swift
//  Binaural beats
//
//  バイノーラルビートのプリセット定義。
//  音声ファイルは持たず、基準周波数（キャリア）とビート周波数（左右差）で
//  それぞれの「曲」を定義し、再生時にリアルタイム合成する。
//

import SwiftUI

/// 脳波の帯域カテゴリ。ビート周波数がこの帯域に対応する。
enum BrainwaveBand: String, CaseIterable, Identifiable {
    case delta
    case theta
    case alpha
    case beta
    case gamma

    var id: String { rawValue }

    /// 表示名
    var title: String {
        switch self {
        case .delta: return String(localized: "デルタ波")
        case .theta: return String(localized: "シータ波")
        case .alpha: return String(localized: "アルファ波")
        case .beta:  return String(localized: "ベータ波")
        case .gamma: return String(localized: "ガンマ波")
        }
    }

    /// 周波数の目安（Hz）
    var range: String {
        switch self {
        case .delta: return "0.5–4 Hz"
        case .theta: return "4–8 Hz"
        case .alpha: return "8–12 Hz"
        case .beta:  return "13–30 Hz"
        case .gamma: return "30–45 Hz"
        }
    }

    /// 用途の説明
    var purpose: String {
        switch self {
        case .delta: return String(localized: "深い休息・回復・睡眠導入")
        case .theta: return String(localized: "瞑想・リラックス・創造性")
        case .alpha: return String(localized: "落ち着いた集中・読書・軽い作業")
        case .beta:  return String(localized: "アクティブな集中・仕事・学習")
        case .gamma: return String(localized: "高度な集中・ひらめき・処理速度")
        }
    }

    /// カテゴリ色
    var color: Color {
        switch self {
        case .delta: return .indigo
        case .theta: return .purple
        case .alpha: return .teal
        case .beta:  return .orange
        case .gamma: return .pink
        }
    }

    var systemImage: String {
        switch self {
        case .delta: return "moon.stars.fill"
        case .theta: return "leaf.fill"
        case .alpha: return "book.fill"
        case .beta:  return "bolt.fill"
        case .gamma: return "brain.head.profile"
        }
    }
}

/// 1つのバイノーラルビート「曲」。
struct BinauralPreset: Identifiable, Hashable {
    let id: Int
    /// 曲名（日本語）
    let name: String
    /// 補足（英語名・ひとことの用途）
    let detail: String
    let band: BrainwaveBand
    /// キャリア（基準）周波数。左耳に流す音。
    let carrier: Double
    /// ビート周波数。左右の差として知覚される周波数。
    let beat: Double

    /// 左チャンネルの周波数
    var leftFrequency: Double { carrier }
    /// 右チャンネルの周波数（キャリア + ビート）
    var rightFrequency: Double { carrier + beat }

    /// ビート周波数の表示文字列（例: "10.0 Hz"）
    var beatText: String { String(format: "%.1f Hz", beat) }

    /// ローカライズした曲名（`name` を翻訳テーブルのキーとして引く）
    var localizedName: String { NSLocalizedString(name, comment: "Binaural preset name") }
    /// ローカライズした補足説明
    var localizedDetail: String { NSLocalizedString(detail, comment: "Binaural preset detail") }
}

extension BinauralPreset {
    /// 30曲のプリセット一覧。帯域ごとにバランスよく配置。
    static let all: [BinauralPreset] = [
        // MARK: - デルタ波（深い休息・睡眠）
        .init(id: 1,  name: "静寂の海",     detail: "Deep Sea Calm",      band: .delta, carrier: 100, beat: 2.0),
        .init(id: 2,  name: "夜の帳",       detail: "Night Veil",         band: .delta, carrier: 90,  beat: 1.0),
        .init(id: 3,  name: "深層回復",     detail: "Deep Recovery",      band: .delta, carrier: 110, beat: 3.0),
        .init(id: 4,  name: "眠りの入口",   detail: "Threshold of Sleep", band: .delta, carrier: 95,  beat: 0.8),
        .init(id: 5,  name: "大地の鼓動",   detail: "Earth Pulse",        band: .delta, carrier: 105, beat: 3.5),

        // MARK: - シータ波（瞑想・創造）
        .init(id: 6,  name: "瞑想の森",     detail: "Meditation Forest",  band: .theta, carrier: 120, beat: 5.0),
        .init(id: 7,  name: "夢想",         detail: "Reverie",            band: .theta, carrier: 130, beat: 6.0),
        .init(id: 8,  name: "内省",         detail: "Introspection",      band: .theta, carrier: 115, beat: 4.5),
        .init(id: 9,  name: "創造の泉",     detail: "Creative Spring",    band: .theta, carrier: 140, beat: 7.0),
        .init(id: 10, name: "静心",         detail: "Still Mind",         band: .theta, carrier: 125, beat: 4.0),
        .init(id: 11, name: "発想の扉",     detail: "Idea Gate",          band: .theta, carrier: 150, beat: 6.5),

        // MARK: - アルファ波（落ち着いた集中）
        .init(id: 12, name: "澄んだ集中",   detail: "Clear Focus",        band: .alpha, carrier: 200, beat: 10.0),
        .init(id: 13, name: "朝の光",       detail: "Morning Light",      band: .alpha, carrier: 210, beat: 9.0),
        .init(id: 14, name: "穏やかな流れ", detail: "Gentle Flow",        band: .alpha, carrier: 190, beat: 8.5),
        .init(id: 15, name: "リラックス集中", detail: "Relaxed Focus",    band: .alpha, carrier: 220, beat: 10.5),
        .init(id: 16, name: "読書の時間",   detail: "Reading Time",       band: .alpha, carrier: 180, beat: 8.0),
        .init(id: 17, name: "心の余白",     detail: "Mental Space",       band: .alpha, carrier: 205, beat: 11.0),
        .init(id: 18, name: "ゾーンの入口", detail: "Into the Zone",      band: .alpha, carrier: 215, beat: 12.0),

        // MARK: - ベータ波（アクティブな集中・仕事）
        .init(id: 19, name: "集中モード",   detail: "Focus Mode",         band: .beta,  carrier: 240, beat: 15.0),
        .init(id: 20, name: "仕事の推進力", detail: "Work Drive",         band: .beta,  carrier: 250, beat: 18.0),
        .init(id: 21, name: "学習ブースト", detail: "Study Boost",        band: .beta,  carrier: 260, beat: 16.0),
        .init(id: 22, name: "論理思考",     detail: "Logical Thinking",   band: .beta,  carrier: 245, beat: 20.0),
        .init(id: 23, name: "締切スプリント", detail: "Deadline Sprint",  band: .beta,  carrier: 270, beat: 22.0),
        .init(id: 24, name: "覚醒",         detail: "Alertness",          band: .beta,  carrier: 255, beat: 14.0),
        .init(id: 25, name: "高速処理",     detail: "Rapid Processing",   band: .beta,  carrier: 280, beat: 25.0),
        .init(id: 26, name: "タスク集中",   detail: "Task Focus",         band: .beta,  carrier: 235, beat: 17.0),

        // MARK: - ガンマ波（高度な集中・ひらめき）
        .init(id: 27, name: "鋭敏な知性",   detail: "Sharp Intellect",    band: .gamma, carrier: 300, beat: 40.0),
        .init(id: 28, name: "ひらめき",     detail: "Insight",            band: .gamma, carrier: 300, beat: 35.0),
        .init(id: 29, name: "超集中",       detail: "Hyperfocus",         band: .gamma, carrier: 320, beat: 38.0),
        .init(id: 30, name: "頂点思考",     detail: "Peak Cognition",     band: .gamma, carrier: 300, beat: 45.0),
    ]

    /// 帯域ごとにまとめた一覧（表示用）
    static func grouped() -> [(band: BrainwaveBand, presets: [BinauralPreset])] {
        BrainwaveBand.allCases.map { band in
            (band, all.filter { $0.band == band })
        }
    }
}

/// 背景に重ねるノイズの種類。
enum NoiseType: String, CaseIterable, Identifiable {
    case none
    case white
    case pink
    case brown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:  return String(localized: "なし")
        case .white: return String(localized: "ホワイト")
        case .pink:  return String(localized: "ピンク")
        case .brown: return String(localized: "ブラウン")
        }
    }

    var detail: String {
        switch self {
        case .none:  return String(localized: "純粋なバイノーラルビートのみ")
        case .white: return String(localized: "均一なノイズ。マスキング効果が高い")
        case .pink:  return String(localized: "自然な雨のような柔らかいノイズ")
        case .brown: return String(localized: "低音が強い波のようなノイズ")
        }
    }

    /// 合成ロジックで使う整数コード
    var code: Int {
        switch self {
        case .none:  return 0
        case .white: return 1
        case .pink:  return 2
        case .brown: return 3
        }
    }
}
