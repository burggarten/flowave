//
//  ModularTrack.swift
//  Binaural beats
//
//  モジュラーシンセ風に生成するBGMトラックの定義。
//  各トラックは「スケール・ルート音・テンポ・シーケンス・波形・フィルター・LFO・ディレイ」
//  などのパラメータで表現し、再生時にリアルタイム合成する（音声ファイル不要）。
//

import SwiftUI

/// 音階（ルートからの半音オフセット）
enum MusicalScale: String, CaseIterable {
    case major
    case minor
    case majorPentatonic
    case minorPentatonic
    case dorian
    case lydian

    var offsets: [Int] {
        switch self {
        case .major:            return [0, 2, 4, 5, 7, 9, 11]
        case .minor:            return [0, 2, 3, 5, 7, 8, 10]
        case .majorPentatonic:  return [0, 2, 4, 7, 9]
        case .minorPentatonic:  return [0, 3, 5, 7, 10]
        case .dorian:           return [0, 2, 3, 5, 7, 9, 10]
        case .lydian:           return [0, 2, 4, 6, 7, 9, 11]
        }
    }
}

/// オシレーターの波形
enum SynthWaveform: Int {
    case sine = 0
    case saw = 1
    case square = 2
    case triangle = 3
    case pulse = 4
}

/// トラックの雰囲気（グループ分け・配色用）
enum SynthMood: String, CaseIterable, Identifiable {
    case ambient
    case focus
    case uplifting
    case deep
    case dreamy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ambient:   return String(localized: "アンビエント")
        case .focus:     return String(localized: "フォーカス")
        case .uplifting: return String(localized: "アップリフティング")
        case .deep:      return String(localized: "ディープ")
        case .dreamy:    return String(localized: "ドリーミー")
        }
    }

    var purpose: String {
        switch self {
        case .ambient:   return String(localized: "空間的で穏やかな環境音楽")
        case .focus:     return String(localized: "一定のリズムで作業に没入")
        case .uplifting: return String(localized: "明るく前向きな気分に")
        case .deep:      return String(localized: "低音中心の深く落ち着いた響き")
        case .dreamy:    return String(localized: "浮遊感のある幻想的な音像")
        }
    }

    var color: Color {
        switch self {
        case .ambient:   return .mint
        case .focus:     return .blue
        case .uplifting: return .yellow
        case .deep:      return .indigo
        case .dreamy:    return .purple
        }
    }

    var systemImage: String {
        switch self {
        case .ambient:   return "cloud.fill"
        case .focus:     return "scope"
        case .uplifting: return "sun.max.fill"
        case .deep:      return "water.waves"
        case .dreamy:    return "sparkles"
        }
    }
}

/// 1つのモジュラーシンセBGMトラック。
struct ModularTrack: Identifiable, Hashable {
    let id: Int
    let name: String
    let detail: String
    let mood: SynthMood

    /// ルート音（MIDIノート番号。C3 = 48）
    let rootNote: Int
    let scale: MusicalScale
    /// テンポ（BPM）
    let bpm: Double
    /// 1拍あたりのステップ数（2 = 8分, 4 = 16分）
    let division: Int
    /// シーケンス（スケール上の度数。休符は `rest`）
    let steps: [Int]
    let waveform: SynthWaveform
    /// フィルターのベースカットオフ（Hz）
    let cutoff: Double
    /// レゾナンス（0...1）
    let resonance: Double
    /// フィルターを揺らすLFOの速さ（Hz）
    let lfoRate: Double
    /// LFOの深さ（0...1）
    let lfoDepth: Double
    /// ディレイ（やまびこ）の量（0...1）
    let delayMix: Double
    /// パッド（持続音）の音量（0...1）
    let padLevel: Double

    var bpmText: String { "\(Int(bpm)) BPM" }

    /// ローカライズしたトラック名（`name` を翻訳テーブルのキーとして引く）
    var localizedName: String { NSLocalizedString(name, comment: "Modular track name") }
    /// ローカライズした補足説明
    var localizedDetail: String { NSLocalizedString(detail, comment: "Modular track detail") }

    /// 休符を表す度数
    static let rest = Int.min

    // MARK: - 周波数の計算

    private func frequency(forMIDI midi: Int) -> Double {
        440.0 * pow(2.0, Double(midi - 69) / 12.0)
    }

    /// 各ステップの周波数（休符は 0）
    func stepFrequencies() -> [Double] {
        let offs = scale.offsets
        let n = offs.count
        return steps.map { deg in
            guard deg != Self.rest else { return 0 }
            let octave = Int(floor(Double(deg) / Double(n)))
            let idx = ((deg % n) + n) % n
            let midi = rootNote + octave * 12 + offs[idx]
            return frequency(forMIDI: midi)
        }
    }

    /// 各ステップの4和音の周波数（スケール上で3度堆積：度数 d, d+2, d+4, d+6）。休符は空配列。
    func stepChordFrequencies() -> [[Double]] {
        let offs = scale.offsets
        let n = offs.count
        return steps.map { deg -> [Double] in
            guard deg != Self.rest else { return [] }
            return [deg, deg + 2, deg + 4, deg + 6].map { d in
                let octave = Int(floor(Double(d) / Double(n)))
                let idx = ((d % n) + n) % n
                let midi = rootNote + octave * 12 + offs[idx]
                return frequency(forMIDI: midi)
            }
        }
    }

    /// パッド（持続音）の周波数：1オクターブ下のルート・5度・ルート
    func padFrequencies() -> [Double] {
        [frequency(forMIDI: rootNote - 12),
         frequency(forMIDI: rootNote - 5),
         frequency(forMIDI: rootNote)]
    }
}

extension ModularTrack {
    /// BGMトラック20曲。
    static let all: [ModularTrack] = {
        let R = ModularTrack.rest
        return [
            // MARK: - アンビエント
            .init(id: 101, name: "薄明",       detail: "Twilight Haze",   mood: .ambient, rootNote: 48, scale: .majorPentatonic, bpm: 46, division: 2, steps: [0, R, 2, R, 4, R, 2, R], waveform: .sine,     cutoff: 900,  resonance: 0.20, lfoRate: 0.08, lfoDepth: 0.5, delayMix: 0.45, padLevel: 0.55),
            .init(id: 102, name: "霧の庭",     detail: "Misty Garden",    mood: .ambient, rootNote: 45, scale: .minorPentatonic, bpm: 44, division: 2, steps: [0, R, 3, R, 4, R, 2, R], waveform: .triangle, cutoff: 800,  resonance: 0.25, lfoRate: 0.06, lfoDepth: 0.6, delayMix: 0.50, padLevel: 0.60),
            .init(id: 103, name: "遠い記憶",   detail: "Distant Memory",  mood: .ambient, rootNote: 50, scale: .dorian,          bpm: 50, division: 2, steps: [0, 2, R, 4, R, 2, 0, R], waveform: .sine,     cutoff: 1000, resonance: 0.20, lfoRate: 0.10, lfoDepth: 0.4, delayMix: 0.40, padLevel: 0.50),
            .init(id: 104, name: "星屑",       detail: "Stardust",        mood: .ambient, rootNote: 55, scale: .majorPentatonic, bpm: 52, division: 2, steps: [0, 2, 4, 2, 0, R, 4, R], waveform: .triangle, cutoff: 1100, resonance: 0.22, lfoRate: 0.12, lfoDepth: 0.5, delayMix: 0.48, padLevel: 0.45),

            // MARK: - フォーカス
            .init(id: 105, name: "定常軌道",   detail: "Steady Orbit",    mood: .focus, rootNote: 48, scale: .minor,           bpm: 56, division: 2, steps: [0, 3, 7, 3, 0, 3, 7, 10], waveform: .saw,      cutoff: 1400, resonance: 0.30, lfoRate: 0.15, lfoDepth: 0.4, delayMix: 0.28, padLevel: 0.30),
            .init(id: 106, name: "思考の流れ", detail: "Flow State",      mood: .focus, rootNote: 50, scale: .dorian,          bpm: 54,  division: 2, steps: [0, 2, 3, 5, 7, 5, 3, 2],  waveform: .saw,      cutoff: 1300, resonance: 0.28, lfoRate: 0.12, lfoDepth: 0.35, delayMix: 0.25, padLevel: 0.28),
            .init(id: 107, name: "回路",       detail: "Circuit",         mood: .focus, rootNote: 43, scale: .minorPentatonic, bpm: 52, division: 4, steps: [0, 3, 5, 7, 5, 3, 7, 5],  waveform: .pulse,    cutoff: 1500, resonance: 0.35, lfoRate: 0.20, lfoDepth: 0.4, delayMix: 0.30, padLevel: 0.25),
            .init(id: 108, name: "集中線",     detail: "Focus Lines",     mood: .focus, rootNote: 45, scale: .minor,           bpm: 56, division: 2, steps: [0, 2, 3, 7, 3, 2, 0, R],  waveform: .square,   cutoff: 1350, resonance: 0.30, lfoRate: 0.18, lfoDepth: 0.35, delayMix: 0.26, padLevel: 0.30),
            .init(id: 109, name: "反復",       detail: "Repetition",      mood: .focus, rootNote: 48, scale: .major,           bpm: 52, division: 2, steps: [0, 4, 7, 4, 0, 4, 7, 4],  waveform: .saw,      cutoff: 1450, resonance: 0.28, lfoRate: 0.14, lfoDepth: 0.4, delayMix: 0.24, padLevel: 0.28),

            // MARK: - アップリフティング
            .init(id: 110, name: "陽光",       detail: "Sunbeam",         mood: .uplifting, rootNote: 52, scale: .major,           bpm: 58, division: 2, steps: [0, 2, 4, 7, 9, 7, 4, 2],   waveform: .saw,    cutoff: 2000, resonance: 0.30, lfoRate: 0.20, lfoDepth: 0.4, delayMix: 0.32, padLevel: 0.30),
            .init(id: 111, name: "上昇気流",   detail: "Updraft",         mood: .uplifting, rootNote: 50, scale: .lydian,          bpm: 60, division: 4, steps: [0, 2, 4, 6, 7, 9, 11, 7],  waveform: .saw,    cutoff: 2200, resonance: 0.32, lfoRate: 0.25, lfoDepth: 0.4, delayMix: 0.34, padLevel: 0.28),
            .init(id: 112, name: "躍動",       detail: "Vivid",           mood: .uplifting, rootNote: 48, scale: .majorPentatonic, bpm: 58, division: 2, steps: [0, 2, 4, 7, 9, 7, 4, 2],   waveform: .pulse,  cutoff: 2100, resonance: 0.30, lfoRate: 0.22, lfoDepth: 0.35, delayMix: 0.30, padLevel: 0.28),
            .init(id: 113, name: "きらめき",   detail: "Glimmer",         mood: .uplifting, rootNote: 55, scale: .major,           bpm: 56, division: 4, steps: [0, 4, 7, 11, 7, 4, 0, R],  waveform: .triangle, cutoff: 2400, resonance: 0.28, lfoRate: 0.24, lfoDepth: 0.45, delayMix: 0.38, padLevel: 0.26),

            // MARK: - ディープ
            .init(id: 114, name: "深層",       detail: "The Deep",        mood: .deep, rootNote: 36, scale: .minor,           bpm: 42, division: 2, steps: [0, R, 3, R, 7, R, 3, R],  waveform: .sine,     cutoff: 700, resonance: 0.25, lfoRate: 0.06, lfoDepth: 0.5, delayMix: 0.40, padLevel: 0.55),
            .init(id: 115, name: "地下水脈",   detail: "Aquifer",         mood: .deep, rootNote: 38, scale: .dorian,          bpm: 44, division: 2, steps: [0, 2, R, 5, R, 2, 0, R],  waveform: .triangle, cutoff: 750, resonance: 0.30, lfoRate: 0.08, lfoDepth: 0.5, delayMix: 0.42, padLevel: 0.55),
            .init(id: 116, name: "夜間飛行",   detail: "Night Flight",    mood: .deep, rootNote: 41, scale: .minorPentatonic, bpm: 46, division: 2, steps: [0, 3, 5, 3, 0, R, 7, R],  waveform: .saw,      cutoff: 850, resonance: 0.35, lfoRate: 0.10, lfoDepth: 0.45, delayMix: 0.38, padLevel: 0.50),
            .init(id: 117, name: "静止",       detail: "Stillness",       mood: .deep, rootNote: 36, scale: .minor,           bpm: 40, division: 2, steps: [0, R, R, R, 7, R, R, R],  waveform: .sine,     cutoff: 650, resonance: 0.20, lfoRate: 0.05, lfoDepth: 0.4, delayMix: 0.45, padLevel: 0.60),

            // MARK: - ドリーミー
            .init(id: 118, name: "夢の断片",   detail: "Dream Fragment",  mood: .dreamy, rootNote: 53, scale: .lydian,          bpm: 50, division: 2, steps: [0, 2, 4, 6, 4, 2, 0, R],  waveform: .triangle, cutoff: 1300, resonance: 0.25, lfoRate: 0.14, lfoDepth: 0.5, delayMix: 0.52, padLevel: 0.45),
            .init(id: 119, name: "浮遊",       detail: "Floating",        mood: .dreamy, rootNote: 50, scale: .majorPentatonic, bpm: 48, division: 2, steps: [0, 4, 2, 7, 4, 9, 7, R],  waveform: .sine,     cutoff: 1200, resonance: 0.22, lfoRate: 0.12, lfoDepth: 0.55, delayMix: 0.55, padLevel: 0.48),
            .init(id: 120, name: "残響",       detail: "Reverberation",   mood: .dreamy, rootNote: 48, scale: .dorian,          bpm: 52, division: 2, steps: [0, 3, 5, 7, 5, 3, R, R],  waveform: .triangle, cutoff: 1250, resonance: 0.28, lfoRate: 0.16, lfoDepth: 0.5, delayMix: 0.60, padLevel: 0.44),
        ]
    }()

    /// 雰囲気ごとにまとめた一覧（表示用）
    static func grouped() -> [(mood: SynthMood, tracks: [ModularTrack])] {
        SynthMood.allCases.map { mood in
            (mood, all.filter { $0.mood == mood })
        }
    }
}

/// いま再生中の項目（バイノーラル or モジュラー）を統一的に扱う。
enum NowPlayingItem: Equatable {
    case binaural(BinauralPreset)
    case modular(ModularTrack)

    var title: String {
        switch self {
        case .binaural(let p): return p.localizedName
        case .modular(let t):  return t.localizedName
        }
    }

    var subtitle: String {
        switch self {
        case .binaural(let p): return String(localized: "\(p.band.title) ・ ビート \(p.beatText)")
        case .modular(let t):  return String(localized: "\(t.mood.title) ・ \(t.bpmText)")
        }
    }

    var color: Color {
        switch self {
        case .binaural(let p): return p.band.color
        case .modular(let t):  return t.mood.color
        }
    }

    var isBinaural: Bool {
        if case .binaural = self { return true }
        return false
    }
}
