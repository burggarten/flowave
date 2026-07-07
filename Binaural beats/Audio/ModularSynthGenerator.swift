//
//  ModularSynthGenerator.swift
//  Binaural beats
//
//  モジュラーシンセ風のBGMをリアルタイム合成する。
//  構成：ステップシーケンサ → 2オシレーター(デチューン) → AD/Sエンベロープ →
//        LFOで揺れるレゾナント・ローパスフィルター(SVF) ＋ 持続パッド → ステレオディレイ。
//  リアルタイムスレッドで動くため MainActor から外し、確保・ロックを行わない。
//

import Foundation
import AVFoundation

nonisolated final class ModularSynthGenerator {
    var sampleRate: Double = 44_100 {
        didSet { rebuildDerived() }
    }
    var volume: Double = 0.7
    var targetGain: Double = 0.0

    // MARK: - シーケンス（固定長バッファに書き込み、レンダースレッドは読むだけ）
    // 各ステップは4和音。chordFreqBase[stepIndex*4 + voice] に基音周波数を格納（休符は先頭0）。
    private let maxSteps = 64
    private let voicesPerStep = 4
    private var chordFreqBase: [Double]
    private var stepCount = 1
    private var stepDurationSamples = 22_050.0

    // MARK: - トラックパラメータ
    private var waveform = 0
    private var cutoffBase = 1_200.0
    private var resonance = 0.3
    private var lfoRate = 0.15
    private var lfoDepth = 0.4
    private var delayMix = 0.3
    private var padLevel = 0.3
    private var padFreqs: [Double]
    private var padCount = 0

    // MARK: - フェード
    private var currentGain = 0.0
    private var gainStep = 1.0 / (0.040 * 44_100)

    // MARK: - シーケンサ状態
    private var stepIndex = 0
    private var stepSampleCounter = 0.0

    // MARK: - 90秒の和声サイクル
    // モチーフが1周するたびにトランスポーズ（転調）が進み、系列を一巡すると
    // 約90秒でルートに戻る。これにより短いループの反復感をなくす。
    private let harmonyCap = 128
    private var harmonySeq: [Double]      // 各モチーフ周回のトランスポーズ倍率
    private var harmonyCount = 1
    private var harmonyIndex = 0
    private var transpose = 1.0
    private let cycleSeconds = 180.0

    // MARK: - オシレーター（4和音）／エンベロープ
    private var voiceFreq: [Double]
    private var voicePhase: [Double]
    private var env = 0.0
    private var envStage = 0   // 0:idle 1:attack 2:decay/sustain 3:release
    private var attackSamples = 220.0
    private var decaySamples = 8_000.0
    private var sustainLevel = 0.55
    private var releaseSamples = 12_000.0

    // MARK: - LFO / フィルター(SVF)
    private var lfoPhase = 0.0
    private var padLfoPhase = 0.0
    private var svfIc1 = 0.0
    private var svfIc2 = 0.0
    // 制御レート更新用の係数キャッシュ
    private var coefA1 = 0.0, coefA2 = 0.0, coefA3 = 0.0
    private var controlCounter = 0
    private let controlInterval = 16

    // MARK: - パッド
    private var padPhases: [Double]

    // MARK: - ステレオディレイ
    private let delaySize = 48_000
    private var delayL: [Float]
    private var delayR: [Float]
    private var delayWrite = 0
    private var delayTimeL = 13_230
    private var delayTimeR = 19_845
    private var delayFeedback = 0.32

    private let outputAmp: Float = 0.85

    init() {
        chordFreqBase = [Double](repeating: 0, count: maxSteps * 4)
        voiceFreq = [Double](repeating: 0, count: 4)
        voicePhase = [Double](repeating: 0, count: 4)
        padFreqs = [Double](repeating: 0, count: 4)
        padPhases = [Double](repeating: 0, count: 4)
        harmonySeq = [Double](repeating: 1.0, count: 128)
        delayL = [Float](repeating: 0, count: delaySize)
        delayR = [Float](repeating: 0, count: delaySize)
        rebuildDerived()
    }

    private func rebuildDerived() {
        gainStep = 1.0 / (0.040 * sampleRate)
    }

    // MARK: - トラックのロード（メインスレッドから、無音時に呼ぶ）

    func load(_ track: ModularTrack) {
        let chords = track.stepChordFrequencies()
        stepCount = min(maxSteps, max(1, chords.count))
        for s in 0..<stepCount {
            let ch = chords[s]
            for v in 0..<voicesPerStep {
                chordFreqBase[s * 4 + v] = v < ch.count ? ch[v] : 0
            }
        }

        let pads = track.padFrequencies()
        padCount = min(4, pads.count)
        for i in 0..<padCount { padFreqs[i] = pads[i] }

        stepDurationSamples = sampleRate * 60.0 / (track.bpm * Double(track.division))

        waveform = track.waveform.rawValue
        cutoffBase = track.cutoff
        resonance = min(0.95, max(0.0, track.resonance))
        lfoRate = track.lfoRate
        lfoDepth = track.lfoDepth
        delayMix = track.delayMix
        padLevel = track.padLevel

        // ディレイ時間をテンポに合わせる（付点8分程度と4分程度）
        let beat = sampleRate * 60.0 / track.bpm
        delayTimeL = min(delaySize - 1, max(1, Int(beat * 0.75)))
        delayTimeR = min(delaySize - 1, max(1, Int(beat * 0.5)))

        buildHarmony(track: track)
        resetSequencer()
    }

    /// 約90秒で一巡する転調系列を生成する。
    /// モチーフ1周の長さから90秒に収まる周回数を求め、その数だけ
    /// スケールに馴染む音程を疑似ランダムに並べる（ルート＝0から開始）。
    private func buildHarmony(track: ModularTrack) {
        let motifSamples = stepDurationSamples * Double(stepCount)
        let loops = max(2, min(harmonyCap, Int((cycleSeconds * sampleRate / motifSamples).rounded())))
        harmonyCount = loops

        // 転調に使う音程（半音）。完全・長短3度中心で、原調から離れすぎない。
        let palette = [0, 0, 5, -5, 7, 3, -3, 2, -2, 5, 0, -5]
        var seed = UInt32(truncatingIfNeeded: track.rootNote &* 2_654_435_761
                          &+ track.id &* 40_503 &+ Int(track.bpm) &* 97 &+ 1)
        if seed == 0 { seed = 0x1234_5678 }

        harmonySeq[0] = 1.0 // 先頭は必ずルート
        for i in 1..<loops {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            let semis = palette[Int(seed % UInt32(palette.count))]
            harmonySeq[i] = pow(2.0, Double(semis) / 12.0)
        }
    }

    private func resetSequencer() {
        stepIndex = 0
        stepSampleCounter = 0
        env = 0
        envStage = 0
        for v in 0..<voicesPerStep { voiceFreq[v] = 0; voicePhase[v] = 0 }
        harmonyIndex = 0
        transpose = harmonySeq[0]
    }

    // MARK: - 合成

    func render(frameCount: Int, audioBufferList: UnsafeMutablePointer<AudioBufferList>) {
        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard abl.count > 0 else { return }
        let leftPtr = abl[0].mData?.assumingMemoryBound(to: Float.self)
        let rightPtr = abl.count > 1 ? abl[1].mData?.assumingMemoryBound(to: Float.self) : leftPtr
        guard let left = leftPtr, let right = rightPtr else { return }

        let twoPi = 2.0 * Double.pi
        let vol = Float(volume)

        for frame in 0..<frameCount {
            // ゲイン漸近（クリック防止）
            if currentGain < targetGain {
                currentGain = min(targetGain, currentGain + gainStep)
            } else if currentGain > targetGain {
                currentGain = max(targetGain, currentGain - gainStep)
            }

            // --- シーケンサ ---
            if stepSampleCounter <= 0 {
                let base = chordFreqBase[stepIndex * 4]
                if base > 0 {
                    for v in 0..<voicesPerStep {
                        voiceFreq[v] = chordFreqBase[stepIndex * 4 + v] * transpose
                    }
                    envStage = 1   // アタック開始（リトリガー）
                } else {
                    envStage = 3   // 休符 → リリース（前の和音の余韻を残す）
                }
                stepIndex += 1
                if stepIndex >= max(1, stepCount) {
                    stepIndex = 0
                    // モチーフが1周 → 転調を進める（一巡で約90秒）
                    harmonyIndex = (harmonyIndex + 1) % max(1, harmonyCount)
                    transpose = harmonySeq[harmonyIndex]
                }
                stepSampleCounter += stepDurationSamples
            }
            stepSampleCounter -= 1

            // --- エンベロープ ---
            switch envStage {
            case 1:
                env += 1.0 / attackSamples
                if env >= 1.0 { env = 1.0; envStage = 2 }
            case 2:
                if env > sustainLevel {
                    env -= (1.0 - sustainLevel) / decaySamples
                    if env < sustainLevel { env = sustainLevel }
                }
            case 3:
                if env > 0 {
                    env -= sustainLevel / releaseSamples
                    if env < 0 { env = 0 }
                }
            default:
                break
            }

            // --- 和音オシレーター（4声） ---
            var lead: Float = 0
            if voiceFreq[0] > 0 {
                var sum: Float = 0
                for v in 0..<voicesPerStep {
                    let f = voiceFreq[v]
                    if f <= 0 { continue }
                    let inc = twoPi * f / sampleRate
                    voicePhase[v] += inc
                    if voicePhase[v] >= twoPi { voicePhase[v] -= twoPi }
                    sum += waveSample(waveform, voicePhase[v])
                }
                lead = sum * 0.25 * Float(env)
            }

            // --- LFO ＆ フィルター係数（制御レートで更新） ---
            lfoPhase += twoPi * lfoRate / sampleRate
            if lfoPhase >= twoPi { lfoPhase -= twoPi }
            if controlCounter == 0 {
                let lfo = sin(lfoPhase)
                var cutoff = cutoffBase * (1.0 + lfoDepth * lfo)
                cutoff = min(sampleRate * 0.45, max(60.0, cutoff))
                updateFilterCoefficients(cutoff: cutoff)
            }
            controlCounter = (controlCounter + 1) % controlInterval

            // --- SVF ローパス ---
            let filtered = Float(svfLowpass(Double(lead)))

            // --- パッド（持続音・ゆっくり揺れる） ---
            padLfoPhase += twoPi * 0.05 / sampleRate
            if padLfoPhase >= twoPi { padLfoPhase -= twoPi }
            var pad: Float = 0
            if padLevel > 0 {
                for i in 0..<padCount {
                    let inc = twoPi * padFreqs[i] * transpose / sampleRate
                    padPhases[i] += inc
                    if padPhases[i] >= twoPi { padPhases[i] -= twoPi }
                    let w: Float = i == 0 ? 1.0 : (i == 1 ? 0.6 : 0.4)
                    pad += Float(sin(padPhases[i])) * w
                }
                let tremolo = Float(0.85 + 0.15 * sin(padLfoPhase))
                pad *= Float(padLevel) * 0.18 * tremolo
            }

            let mono = filtered + pad

            // --- ステレオディレイ ---
            let readIdxL = (delayWrite - delayTimeL + delaySize) % delaySize
            let readIdxR = (delayWrite - delayTimeR + delaySize) % delaySize
            let echoL = delayL[readIdxL]
            let echoR = delayR[readIdxR]
            let outL = mono + echoL * Float(delayMix)
            let outR = mono + echoR * Float(delayMix)
            delayL[delayWrite] = mono + echoL * Float(delayFeedback)
            delayR[delayWrite] = mono + echoR * Float(delayFeedback)
            delayWrite = (delayWrite + 1) % delaySize

            let g = Float(currentGain) * vol
            // tanh によるソフトクリップで安全に
            left[frame] = tanhf(outL * outputAmp) * g
            right[frame] = tanhf(outR * outputAmp) * g
        }
    }

    // MARK: - フィルター（Cytomic SVF）

    private func updateFilterCoefficients(cutoff: Double) {
        let g = tan(Double.pi * cutoff / sampleRate)
        let k = 2.0 - 1.9 * resonance   // resonance 0..1 → k 2.0..0.1
        coefA1 = 1.0 / (1.0 + g * (g + k))
        coefA2 = g * coefA1
        coefA3 = g * coefA2
    }

    private func svfLowpass(_ input: Double) -> Double {
        let v3 = input - svfIc2
        let v1 = coefA1 * svfIc1 + coefA2 * v3
        let v2 = svfIc2 + coefA2 * svfIc1 + coefA3 * v3
        svfIc1 = 2.0 * v1 - svfIc1
        svfIc2 = 2.0 * v2 - svfIc2
        return v2
    }

    // MARK: - 波形

    private func waveSample(_ code: Int, _ phase: Double) -> Float {
        switch code {
        case 0: // sine
            return Float(sin(phase))
        case 1: // saw
            return Float(phase / Double.pi - 1.0)
        case 2: // square
            return phase < Double.pi ? 1.0 : -1.0
        case 3: // triangle
            let t = phase / (2.0 * Double.pi) // 0..1
            return Float(4.0 * abs(t - 0.5) - 1.0)
        case 4: // pulse (25%)
            return phase < (Double.pi * 0.5) ? 1.0 : -1.0
        default:
            return Float(sin(phase))
        }
    }
}
