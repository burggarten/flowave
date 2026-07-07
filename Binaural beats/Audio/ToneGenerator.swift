//
//  ToneGenerator.swift
//  Binaural beats
//
//  オーディオレンダースレッド上で動作する純音＋ノイズの合成器。
//  リアルタイムスレッドで呼ばれるため、メモリ確保・ロック・ARCトラフィックを避ける。
//  そのため MainActor 隔離から外し（nonisolated）、値の読み書きのみで完結させる。
//

import Foundation
import AVFoundation

nonisolated final class ToneGenerator {
    /// サンプルレート（BinauralAudioEngine 側で設定）
    var sampleRate: Double = 44_100

    // MARK: - メインスレッドから更新されるパラメータ
    // 64bit 整列済みの読み書きはアトミックに扱えるため、レンダースレッドとの共有はこのまま行う。

    /// 左チャンネル周波数（Hz）
    var leftFrequency: Double = 200
    /// 右チャンネル周波数（Hz）
    var rightFrequency: Double = 210
    /// マスター音量（0...1）
    var volume: Double = 0.7
    /// ノイズ音量（0...1）
    var noiseLevel: Double = 0.0
    /// ノイズ種別コード（NoiseType.code）
    var noiseCode: Int = 0

    /// フェードの目標値（0 = 無音, 1 = 再生）。クリックノイズ防止用。
    var targetGain: Double = 0.0

    // MARK: - レンダースレッド内部状態
    private var phaseLeft: Double = 0
    private var phaseRight: Double = 0
    private var currentGain: Double = 0

    /// 約30msでフェードするステップ量
    private var gainStep: Double { 1.0 / (0.030 * sampleRate) }

    // ノイズ生成用の状態
    private var rngState: UInt32 = 0x9E3779B9
    private var pinkB0: Float = 0, pinkB1: Float = 0, pinkB2: Float = 0
    private var pinkB3: Float = 0, pinkB4: Float = 0, pinkB5: Float = 0, pinkB6: Float = 0
    private var brownLast: Float = 0

    private let toneAmplitude: Float = 0.30
    private let noiseAmplitude: Float = 0.28

    // MARK: - 合成

    /// AVAudioSourceNode のレンダーブロックから呼ばれる。
    func render(frameCount: Int, audioBufferList: UnsafeMutablePointer<AudioBufferList>) {
        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard abl.count > 0 else { return }

        let leftPtr = abl[0].mData?.assumingMemoryBound(to: Float.self)
        let rightPtr = abl.count > 1
            ? abl[1].mData?.assumingMemoryBound(to: Float.self)
            : leftPtr
        guard let left = leftPtr, let right = rightPtr else { return }

        let twoPi = 2.0 * Double.pi
        let dPhaseL = twoPi * leftFrequency / sampleRate
        let dPhaseR = twoPi * rightFrequency / sampleRate
        let vol = Float(volume)
        let nLevel = Float(noiseLevel)
        let code = noiseCode
        let step = gainStep
        let target = targetGain

        for frame in 0..<frameCount {
            // クリック防止のためのゲイン漸近
            if currentGain < target {
                currentGain = min(target, currentGain + step)
            } else if currentGain > target {
                currentGain = max(target, currentGain - step)
            }
            let gain = Float(currentGain) * vol

            let tL = Float(sin(phaseLeft)) * toneAmplitude
            let tR = Float(sin(phaseRight)) * toneAmplitude

            var noise: Float = 0
            if code != 0 && nLevel > 0 {
                noise = noiseSample(code: code) * noiseAmplitude * nLevel
            }

            left[frame] = (tL + noise) * gain
            right[frame] = (tR + noise) * gain

            phaseLeft += dPhaseL
            if phaseLeft >= twoPi { phaseLeft -= twoPi }
            phaseRight += dPhaseR
            if phaseRight >= twoPi { phaseRight -= twoPi }
        }
    }

    // MARK: - ノイズ

    /// xorshift32 による -1...1 の擬似乱数（リアルタイム安全）
    private func white() -> Float {
        var x = rngState
        x ^= x << 13
        x ^= x >> 17
        x ^= x << 5
        rngState = x
        return Float(Int32(bitPattern: x)) / Float(Int32.max)
    }

    private func noiseSample(code: Int) -> Float {
        let w = white()
        switch code {
        case 1: // ホワイト
            return w
        case 2: // ピンク（Paul Kellet の近似フィルタ）
            pinkB0 = 0.99886 * pinkB0 + w * 0.0555179
            pinkB1 = 0.99332 * pinkB1 + w * 0.0750759
            pinkB2 = 0.96900 * pinkB2 + w * 0.1538520
            pinkB3 = 0.86650 * pinkB3 + w * 0.3104856
            pinkB4 = 0.55000 * pinkB4 + w * 0.5329522
            pinkB5 = -0.7616 * pinkB5 - w * 0.0168980
            let pink = pinkB0 + pinkB1 + pinkB2 + pinkB3 + pinkB4 + pinkB5 + pinkB6 + w * 0.5362
            pinkB6 = w * 0.115926
            return pink * 0.11
        case 3: // ブラウン（積分＝リーキー）
            brownLast = (brownLast + 0.02 * w) / 1.02
            return brownLast * 3.5
        default:
            return 0
        }
    }
}
