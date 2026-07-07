//
//  AmbienceGenerator.swift
//  Binaural beats
//
//  7種の環境音（アンビエンス）をリアルタイム合成する。
//   - 海   … 低域ブラウンノイズ＋うねり＋しぶき
//   - 雨   … ピンクノイズを帯域通過した密な地雨＋高域のきらめき＋まばらな雨だれ
//   - 森   … ピンクノイズの帯域通過（葉ずれ）＋風＋小鳥
//   - 小川 … 帯域ノイズを速い振幅ゆらぎでゴボゴボ＋上昇ピッチの気泡
//   - 焚き火 … 低い唸り＋帯域ノイズの破裂（大小の爆ぜ）
//   - 風   … 低域ノイズのそよぎ＋うっすらした笛鳴り
//   - ホワイト … 均一なノイズ
//  各音は独立レベルで、単独でも重ねても鳴らせる。左右で別経路にしてステレオ感を出す。
//

import Foundation
import AVFoundation

nonisolated final class AmbienceGenerator {
    var sampleRate: Double = 44_100 {
        didSet { updateCoefficients() }
    }

    // MARK: - 目標レベル（0...1、メインスレッドから設定）
    private var oceanTarget: Double = 0
    private var rainTarget: Double = 0
    private var forestTarget: Double = 0
    private var streamTarget: Double = 0
    private var fireTarget: Double = 0
    private var windTarget: Double = 0
    private var whiteTarget: Double = 0

    func setTarget(_ kind: AmbienceKind, _ value: Double) {
        switch kind {
        case .ocean:  oceanTarget = value
        case .rain:   rainTarget = value
        case .forest: forestTarget = value
        case .stream: streamTarget = value
        case .fire:   fireTarget = value
        case .wind:   windTarget = value
        case .white:  whiteTarget = value
        }
    }

    // MARK: - レベル平滑化（クリック防止）
    private var oceanCur: Float = 0, rainCur: Float = 0, forestCur: Float = 0
    private var streamCur: Float = 0, fireCur: Float = 0, windCur: Float = 0, whiteCur: Float = 0
    private var levelSmooth: Float = 0.0004

    // MARK: - フィルター係数
    private var coefs = AmbCoefs()

    // MARK: - 揺れのLFO
    private var swell1Phase: Double = 0
    private var swell2Phase: Double = 1.7
    private var gustPhase: Double = 0

    // MARK: - 小鳥のさえずり（森・モノラル）
    private var chirpCountdown = 40_000
    private var chirpActive = false
    private var chirpPhase: Double = 0
    private var chirpFreq: Double = 3_000
    private var chirpSamplesLeft = 0
    private var chirpTotalSamples = 1
    private var chirpRng: UInt32 = 0x1234_ABCD

    private let outputAmp: Float = 0.6

    private var chL = AmbChannel(rng: 0x2545_F491)
    private var chR = AmbChannel(rng: 0x9E37_79B1)

    init() {
        updateCoefficients()
    }

    private func updateCoefficients() {
        func lp(_ fc: Double) -> Float { Float(1.0 - exp(-2.0 * Double.pi * fc / sampleRate)) }
        coefs.aOceanLP  = lp(320)
        coefs.aFoamHP   = lp(1_200)
        coefs.aLeafHi   = lp(700)
        coefs.aLeafLo   = lp(3_200)
        coefs.aWhiteLP  = lp(9_000)
        coefs.aRainHi   = lp(250)     // これ以下を削る
        coefs.aRainLo   = lp(6_500)   // 高域の平滑
        coefs.aRainSpark = lp(3_000)  // さらに高域寄りの明るいサーッ
        coefs.aStreamHP = lp(300)     // 中域に寄せる
        coefs.aStreamLP = lp(2_500)
        coefs.aStreamMod = lp(7)      // 速い振幅ゆらぎ
        coefs.aFireLP   = lp(700)     // より低く重い帯域
        coefs.aFireMod  = lp(5)       // 炎のゆらぎ
        coefs.aWindLP   = lp(450)
        coefs.aWindBpHi = lp(600)
        coefs.aWindBpLo = lp(1_200)
        levelSmooth = Float(1.0 - exp(-1.0 / (0.15 * sampleRate)))
    }

    var isSilent: Bool {
        oceanTarget <= 0 && rainTarget <= 0 && forestTarget <= 0 && streamTarget <= 0 &&
        fireTarget <= 0 && windTarget <= 0 && whiteTarget <= 0 &&
        oceanCur < 0.0005 && rainCur < 0.0005 && forestCur < 0.0005 && streamCur < 0.0005 &&
        fireCur < 0.0005 && windCur < 0.0005 && whiteCur < 0.0005
    }

    // MARK: - 合成

    func render(frameCount: Int, audioBufferList: UnsafeMutablePointer<AudioBufferList>) {
        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard abl.count > 0 else { return }
        let leftPtr = abl[0].mData?.assumingMemoryBound(to: Float.self)
        let rightPtr = abl.count > 1 ? abl[1].mData?.assumingMemoryBound(to: Float.self) : leftPtr
        guard let left = leftPtr, let right = rightPtr else { return }

        let twoPi = 2.0 * Double.pi
        let oT = Float(oceanTarget), rT = Float(rainTarget), fT = Float(forestTarget)
        let sT = Float(streamTarget), fiT = Float(fireTarget), wiT = Float(windTarget), whT = Float(whiteTarget)

        for frame in 0..<frameCount {
            oceanCur  += (oT - oceanCur)  * levelSmooth
            rainCur   += (rT - rainCur)   * levelSmooth
            forestCur += (fT - forestCur) * levelSmooth
            streamCur += (sT - streamCur) * levelSmooth
            fireCur   += (fiT - fireCur)  * levelSmooth
            windCur   += (wiT - windCur)  * levelSmooth
            whiteCur  += (whT - whiteCur) * levelSmooth

            swell1Phase += twoPi * 0.09 / sampleRate; if swell1Phase >= twoPi { swell1Phase -= twoPi }
            swell2Phase += twoPi * 0.13 / sampleRate; if swell2Phase >= twoPi { swell2Phase -= twoPi }
            gustPhase   += twoPi * 0.06 / sampleRate; if gustPhase   >= twoPi { gustPhase -= twoPi }

            let swellRaw = 0.7 * (0.5 + 0.5 * sin(swell1Phase)) + 0.3 * (0.5 + 0.5 * sin(swell2Phase))
            let mod = AmbMod(
                swell: Float(swellRaw * swellRaw),
                gust: Float(0.55 + 0.45 * (0.5 + 0.5 * sin(gustPhase)))
            )
            let lv = AmbLevels(ocean: oceanCur, rain: rainCur, forest: forestCur,
                               stream: streamCur, fire: fireCur, wind: windCur, white: whiteCur)

            var l = chL.process(lv, mod, coefs, sr: sampleRate)
            var r = chR.process(lv, mod, coefs, sr: sampleRate)

            let chirp = nextChirpSample(forestLevel: forestCur, twoPi: twoPi)
            l += chirp
            r += chirp

            left[frame] = tanhf(l * outputAmp)
            right[frame] = tanhf(r * outputAmp)
        }
    }

    // MARK: - さえずり

    private func chirpRandom() -> Double {
        var x = chirpRng
        x ^= x << 13; x ^= x >> 17; x ^= x << 5
        chirpRng = x
        return Double(x) / Double(UInt32.max)
    }

    private func nextChirpSample(forestLevel: Float, twoPi: Double) -> Float {
        guard forestLevel > 0.02 else { chirpActive = false; return 0 }
        if !chirpActive {
            chirpCountdown -= 1
            if chirpCountdown <= 0 {
                chirpActive = true
                chirpFreq = 2_400 + chirpRandom() * 1_800
                chirpTotalSamples = Int((0.08 + chirpRandom() * 0.10) * sampleRate)
                chirpSamplesLeft = chirpTotalSamples
                chirpPhase = 0
                chirpCountdown = Int((4.0 + chirpRandom() * 6.0) * sampleRate)
            }
            return 0
        }
        let progress = 1.0 - Double(chirpSamplesLeft) / Double(max(1, chirpTotalSamples))
        let freq = chirpFreq * (1.0 + 0.15 * progress)
        chirpPhase += twoPi * freq / sampleRate
        if chirpPhase >= twoPi { chirpPhase -= twoPi }
        let envShape = Float(sin(Double.pi * progress))
        chirpSamplesLeft -= 1
        if chirpSamplesLeft <= 0 { chirpActive = false }
        return Float(sin(chirpPhase)) * envShape * 0.12 * forestLevel
    }
}

// MARK: - 補助データ

private struct AmbLevels {
    var ocean: Float = 0, rain: Float = 0, forest: Float = 0
    var stream: Float = 0, fire: Float = 0, wind: Float = 0, white: Float = 0
}

private struct AmbMod {
    var swell: Float = 0, gust: Float = 0
}

private struct AmbCoefs {
    var aOceanLP: Float = 0.04, aFoamHP: Float = 0.15
    var aLeafHi: Float = 0.08, aLeafLo: Float = 0.25, aWhiteLP: Float = 0.5
    var aRainHi: Float = 0.03, aRainLo: Float = 0.6, aRainSpark: Float = 0.4
    var aStreamHP: Float = 0.05, aStreamLP: Float = 0.5, aStreamMod: Float = 0.001
    var aFireLP: Float = 0.2, aFireMod: Float = 0.0007
    var aWindLP: Float = 0.05, aWindBpHi: Float = 0.08, aWindBpLo: Float = 0.15
}

/// 単発イベントの発音器（自己スケジューリング）。
/// kind: 0=ping（正弦の減衰）, 1=bubble（上昇ピッチの減衰）, 2=noiseBurst（帯域通過ノイズの破裂）
private struct Grain {
    var rng: UInt32
    var firing = false
    var countdown = 3_000
    var env: Float = 0
    var decayCoef: Float = 0.99
    var amp: Float = 1
    var phase: Double = 0
    var freq: Double = 800
    var sweep: Double = 1
    // 帯域通過（noiseBurst 用）
    var bpHi: Float = 0
    var bpLo: Float = 0
    var aBpHi: Float = 0.2
    var aBpLo: Float = 0.4

    mutating func rand() -> Float {
        var x = rng; x ^= x << 13; x ^= x >> 17; x ^= x << 5; rng = x
        return Float(x) / Float(UInt32.max)
    }

    mutating func next(sr: Double, gapMin: Double, gapMax: Double,
                       decaySec: Double, freqMin: Double, freqMax: Double,
                       ampMin: Float, ampMax: Float, kind: Int, sweepAmt: Double) -> Float {
        if !firing {
            countdown -= 1
            if countdown <= 0 {
                firing = true
                env = 1
                decayCoef = expf(Float(-1.0 / (decaySec * sr)))
                freq = freqMin + Double(rand()) * (freqMax - freqMin)
                amp = ampMin + rand() * (ampMax - ampMin)
                phase = 0
                sweep = 1.0 + sweepAmt / (decaySec * sr)
                if kind == 2 {
                    aBpHi = Float(1 - exp(-2 * Double.pi * (freq * 0.5) / sr))
                    aBpLo = Float(1 - exp(-2 * Double.pi * (freq * 2.0) / sr))
                    bpHi = 0; bpLo = 0
                }
            } else {
                return 0
            }
        }
        var s: Float
        switch kind {
        case 2: // 帯域通過ノイズの破裂
            let n = rand() * 2 - 1
            bpHi += aBpHi * (n - bpHi)
            let hp = n - bpHi
            bpLo += aBpLo * (hp - bpLo)
            s = bpLo * env * amp * 3.0
        case 1: // 上昇ピッチの気泡
            freq *= sweep
            phase += 2.0 * Double.pi * freq / sr
            if phase >= 2.0 * Double.pi { phase -= 2.0 * Double.pi }
            s = Float(sin(phase)) * env * amp
        default: // 正弦の減衰
            phase += 2.0 * Double.pi * freq / sr
            if phase >= 2.0 * Double.pi { phase -= 2.0 * Double.pi }
            s = Float(sin(phase)) * env * amp
        }
        env *= decayCoef
        if env < 0.003 {
            firing = false
            countdown = max(1, Int((gapMin + Double(rand()) * (gapMax - gapMin)) * sr))
        }
        return s
    }
}

/// 1チャンネル分のノイズ経路（左右で独立させ、ステレオの広がりを出す）
private struct AmbChannel {
    var rng: UInt32
    // ocean
    var brownO: Float = 0, lpOcean: Float = 0, lpFoam: Float = 0
    // pink（森・雨で共有）
    var pink0: Float = 0, pink1: Float = 0, pink2: Float = 0, pink3: Float = 0
    var pink4: Float = 0, pink5: Float = 0, pink6: Float = 0
    // forest
    var lpLeafHi: Float = 0, lpLeafLo: Float = 0
    // rain
    var lpRainHi: Float = 0, lpRainLo: Float = 0, lpRainSpark: Float = 0
    // stream
    var lpStreamHP: Float = 0, lpStreamLP: Float = 0, lpStreamMod: Float = 0
    // fire
    var brownF: Float = 0, lpFire: Float = 0, lpFireMod: Float = 0
    // wind
    var brownW: Float = 0, lpWind: Float = 0, lpWindBpHi: Float = 0, lpWindBpLo: Float = 0
    // white
    var lpWhite: Float = 0
    // 単発イベント
    var rainDrop: Grain
    var streamBubble1: Grain
    var streamBubble2: Grain
    var fireCrackle: Grain
    var fireTick: Grain

    init(rng: UInt32) {
        self.rng = rng
        rainDrop      = Grain(rng: rng &* 6_364_136 &+ 1)
        streamBubble1 = Grain(rng: rng &* 2_246_822 &+ 7)
        streamBubble2 = Grain(rng: rng &* 3_512_401 &+ 11)
        fireCrackle   = Grain(rng: rng &* 1_103_515 &+ 13)
        fireTick      = Grain(rng: rng &* 8_121_048 &+ 17)
    }

    mutating func white() -> Float {
        var x = rng; x ^= x << 13; x ^= x >> 17; x ^= x << 5; rng = x
        return Float(Int32(bitPattern: x)) / Float(Int32.max)
    }

    mutating func process(_ lv: AmbLevels, _ m: AmbMod, _ c: AmbCoefs, sr: Double) -> Float {
        let w = white()

        // ピンクノイズ（森・雨で共有）
        pink0 = 0.99886 * pink0 + w * 0.0555179
        pink1 = 0.99332 * pink1 + w * 0.0750759
        pink2 = 0.96900 * pink2 + w * 0.1538520
        pink3 = 0.86650 * pink3 + w * 0.3104856
        pink4 = 0.55000 * pink4 + w * 0.5329522
        pink5 = -0.7616 * pink5 - w * 0.0168980
        let pinkN = (pink0 + pink1 + pink2 + pink3 + pink4 + pink5 + pink6 + w * 0.5362) * 0.11
        pink6 = w * 0.115926

        var out: Float = 0

        // 海
        if lv.ocean > 0.001 {
            brownO = (brownO + 0.02 * w) / 1.02
            lpOcean += c.aOceanLP * (brownO - lpOcean)
            let body = lpOcean * 3.5
            lpFoam += c.aFoamHP * (w - lpFoam)
            let foam = w - lpFoam
            out += ((body + foam * 0.35 * m.swell) * m.swell) * lv.ocean
        }

        // 雨（明るく高域の「サーッ」＋高いパラパラという細かい雨粒）
        if lv.rain > 0.001 {
            lpRainSpark += c.aRainSpark * (w - lpRainSpark)
            let sizzle = w - lpRainSpark           // 高域の広い帯域＝明るい雨音
            lpRainHi += c.aRainHi * (pinkN - lpRainHi)
            let body = pinkN - lpRainHi            // 低域を少しだけ足して厚みを
            var rainSig = sizzle * 0.38 + body * 0.05
            let drop = rainDrop.next(sr: sr, gapMin: 0.03, gapMax: 0.20,
                                     decaySec: 0.025, freqMin: 3_000, freqMax: 6_500,
                                     ampMin: 0.06, ampMax: 0.22, kind: 0, sweepAmt: 0)
            rainSig += drop
            out += rainSig * (0.9 + 0.1 * m.gust) * lv.rain
        }

        // 森
        if lv.forest > 0.001 {
            lpLeafHi += c.aLeafHi * (pinkN - lpLeafHi)
            let hp = pinkN - lpLeafHi
            lpLeafLo += c.aLeafLo * (hp - lpLeafLo)
            out += lpLeafLo * m.gust * 1.6 * lv.forest
        }

        // 小川（速い振幅ゆらぎのゴボゴボ＋上昇ピッチの気泡）
        if lv.stream > 0.001 {
            lpStreamHP += c.aStreamHP * (w - lpStreamHP)
            let hp = w - lpStreamHP
            lpStreamLP += c.aStreamLP * (hp - lpStreamLP)
            let bed = lpStreamLP
            lpStreamMod += c.aStreamMod * (w - lpStreamMod)
            let flutter = 0.4 + 0.6 * min(1, max(-1, lpStreamMod * 3.5))
            let b1 = streamBubble1.next(sr: sr, gapMin: 0.010, gapMax: 0.06,
                                        decaySec: 0.03, freqMin: 400, freqMax: 1_000,
                                        ampMin: 0.15, ampMax: 0.40, kind: 1, sweepAmt: 0.4)
            let b2 = streamBubble2.next(sr: sr, gapMin: 0.015, gapMax: 0.09,
                                        decaySec: 0.04, freqMin: 600, freqMax: 1_500,
                                        ampMin: 0.12, ampMax: 0.30, kind: 1, sweepAmt: 0.5)
            out += (bed * 2.6 * flutter + (b1 + b2) * 0.5) * lv.stream
        }

        // 焚き火（低い唸り＋大小の爆ぜ）
        if lv.fire > 0.001 {
            brownF = (brownF + 0.02 * w) / 1.02
            lpFire += c.aFireLP * (brownF - lpFire)
            lpFireMod += c.aFireMod * (w - lpFireMod)
            let flicker = 0.6 + 0.4 * min(1, max(-1, lpFireMod * 4))
            let bed = lpFire * 3.0 * flicker
            let crk = fireCrackle.next(sr: sr, gapMin: 0.02, gapMax: 0.30,
                                       decaySec: 0.025, freqMin: 200, freqMax: 1_000,
                                       ampMin: 0.35, ampMax: 1.4, kind: 2, sweepAmt: 0)
            let tick = fireTick.next(sr: sr, gapMin: 0.05, gapMax: 0.40,
                                     decaySec: 0.006, freqMin: 1_500, freqMax: 3_500,
                                     ampMin: 0.05, ampMax: 0.30, kind: 2, sweepAmt: 0)
            out += (bed * 0.7 + crk * 0.95 + tick * 0.3) * lv.fire
        }

        // 風
        if lv.wind > 0.001 {
            brownW = (brownW + 0.02 * w) / 1.02
            lpWind += c.aWindLP * (brownW - lpWind)
            let base = lpWind * 3.0 * m.gust
            lpWindBpHi += c.aWindBpHi * (w - lpWindBpHi)
            let bpHp = w - lpWindBpHi
            lpWindBpLo += c.aWindBpLo * (bpHp - lpWindBpLo)
            out += (base * 1.4 + lpWindBpLo * 0.25 * m.gust) * lv.wind
        }

        // ホワイト
        if lv.white > 0.001 {
            lpWhite += c.aWhiteLP * (w - lpWhite)
            out += lpWhite * 0.5 * lv.white
        }

        return out
    }
}
