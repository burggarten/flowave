//
//  AmbienceKind.swift
//  Binaural beats
//
//  環境音の種類（7種）。各音はリアルタイム合成され、独立に ON/OFF・音量調整でき、
//  単独でも組み合わせでも、メイン音源と重ねても再生できる。
//

import Foundation

enum AmbienceKind: String, CaseIterable, Identifiable {
    case ocean
    case rain
    case forest
    case stream
    case fire
    case wind
    case white

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ocean:  return String(localized: "海の音")
        case .rain:   return String(localized: "雨")
        case .forest: return String(localized: "森の音")
        case .stream: return String(localized: "小川のせせらぎ")
        case .fire:   return String(localized: "焚き火")
        case .wind:   return String(localized: "風")
        case .white:  return String(localized: "ホワイトノイズ")
        }
    }

    var subtitle: String {
        switch self {
        case .ocean:  return String(localized: "寄せては返す波のうねり")
        case .rain:   return String(localized: "しとしと降る雨と雨だれ")
        case .forest: return String(localized: "葉ずれ・風・小鳥のさえずり")
        case .stream: return String(localized: "さらさら流れる水とせせらぎ")
        case .fire:   return String(localized: "低い唸りとパチパチという爆ぜ")
        case .wind:   return String(localized: "吹き抜ける風のそよぎ")
        case .white:  return String(localized: "均一なノイズで雑音をマスキング")
        }
    }

    var systemImage: String {
        switch self {
        case .ocean:  return "water.waves"
        case .rain:   return "cloud.rain.fill"
        case .forest: return "tree.fill"
        case .stream: return "drop.fill"
        case .fire:   return "flame.fill"
        case .wind:   return "wind"
        case .white:  return "waveform"
        }
    }

    /// ON にしたときの初期音量
    var defaultLevel: Double {
        switch self {
        case .ocean:  return 0.5
        case .rain:   return 0.5
        case .forest: return 0.5
        case .stream: return 0.5
        case .fire:   return 0.5
        case .wind:   return 0.5
        case .white:  return 0.4
        }
    }
}
