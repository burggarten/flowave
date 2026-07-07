//
//  BinauralAudioEngine.swift
//  Binaural beats
//
//  アプリのオーディオエンジン。3系統の音源をリアルタイム生成して同一ミキサーへ流す：
//   - Constant electric sound … 純音のバイノーラルビート（ToneGenerator）
//   - Modular synth           … BGM風のモジュラーシンセ（ModularSynthGenerator）
//   - 環境音（アンビエンス）  … 海／森／ホワイトノイズ（AmbienceGenerator）
//  メイン音源（上2つ）はゲインのクロスフェードで切り替え、環境音は独立に重ねられる。
//  バックグラウンド再生（.playback）とロック画面の再生操作に対応。
//

import Foundation
import AVFoundation
import MediaPlayer
import Observation

@MainActor
@Observable
final class BinauralAudioEngine {
    // MARK: - 公開状態（UI が監視）
    /// メイン音源が再生中か
    private(set) var isPlaying = false
    /// 現在選択中のメイン音源（バイノーラル or モジュラー）
    private(set) var current: NowPlayingItem?

    /// マスター音量（0...1）… メイン音源に適用
    var volume: Double = 0.7 {
        didSet {
            toneGenerator.volume = volume
            synthGenerator.volume = volume
        }
    }

    // MARK: - 環境音（7種、独立に ON/OFF・音量調整でき、重ねがけ可能）
    private(set) var ambienceEnabled: Set<AmbienceKind> = []
    private(set) var ambienceLevels: [AmbienceKind: Double] =
        Dictionary(uniqueKeysWithValues: AmbienceKind.allCases.map { ($0, $0.defaultLevel) })

    func isAmbienceEnabled(_ kind: AmbienceKind) -> Bool { ambienceEnabled.contains(kind) }
    func ambienceLevel(_ kind: AmbienceKind) -> Double { ambienceLevels[kind] ?? kind.defaultLevel }

    func setAmbienceEnabled(_ kind: AmbienceKind, _ on: Bool) {
        if on { ambienceEnabled.insert(kind) } else { ambienceEnabled.remove(kind) }
        applyAmbience(kind)
    }

    func setAmbienceLevel(_ kind: AmbienceKind, _ value: Double) {
        ambienceLevels[kind] = value
        applyAmbience(kind)
    }

    var anyAmbienceOn: Bool {
        AmbienceKind.allCases.contains { ambienceEnabled.contains($0) && (ambienceLevels[$0] ?? 0) > 0 }
    }

    // MARK: - 内部
    private let engine = AVAudioEngine()
    private let toneGenerator = ToneGenerator()
    private let synthGenerator = ModularSynthGenerator()
    private let ambienceGenerator = AmbienceGenerator()
    private var toneNode: AVAudioSourceNode?
    private var synthNode: AVAudioSourceNode?
    private var ambienceNode: AVAudioSourceNode?
    private var stopTask: Task<Void, Never>?
    private var isConfigured = false

    init() {
        toneGenerator.volume = volume
        synthGenerator.volume = volume
        setupEngine()
        configureSession()
        setupRemoteCommands()
        observeInterruptions()
    }

    // MARK: - セットアップ

    private func setupEngine() {
        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
        toneGenerator.sampleRate = sampleRate
        synthGenerator.sampleRate = sampleRate
        ambienceGenerator.sampleRate = sampleRate

        let tone = AVAudioSourceNode(format: format) { [toneGenerator] _, _, frameCount, audioBufferList in
            toneGenerator.render(frameCount: Int(frameCount), audioBufferList: audioBufferList)
            return noErr
        }
        let synth = AVAudioSourceNode(format: format) { [synthGenerator] _, _, frameCount, audioBufferList in
            synthGenerator.render(frameCount: Int(frameCount), audioBufferList: audioBufferList)
            return noErr
        }
        let ambience = AVAudioSourceNode(format: format) { [ambienceGenerator] _, _, frameCount, audioBufferList in
            ambienceGenerator.render(frameCount: Int(frameCount), audioBufferList: audioBufferList)
            return noErr
        }
        engine.attach(tone)
        engine.attach(synth)
        engine.attach(ambience)
        engine.connect(tone, to: engine.mainMixerNode, format: format)
        engine.connect(synth, to: engine.mainMixerNode, format: format)
        engine.connect(ambience, to: engine.mainMixerNode, format: format)
        toneNode = tone
        synthNode = synth
        ambienceNode = ambience
        engine.prepare()
    }

    private func configureSession() {
        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            isConfigured = true
        } catch {
            print("AVAudioSession の設定に失敗: \(error)")
        }
        #else
        isConfigured = true
        #endif
    }

    // MARK: - メイン音源の再生制御

    /// バイノーラルビートを再生する。
    func play(_ preset: BinauralPreset) {
        current = .binaural(preset)
        toneGenerator.leftFrequency = preset.leftFrequency
        toneGenerator.rightFrequency = preset.rightFrequency
        isPlaying = true
        applyActiveSource()
        updateEngineActive()
        updateNowPlaying()
    }

    /// モジュラーシンセのBGMを再生する。
    func play(_ track: ModularTrack) {
        current = .modular(track)
        synthGenerator.load(track)
        isPlaying = true
        applyActiveSource()
        updateEngineActive()
        updateNowPlaying()
    }

    /// 現在選択中のメイン音源で再生を再開する。
    func resume() {
        guard current != nil else { return }
        isPlaying = true
        applyActiveSource()
        updateEngineActive()
        updateNowPlaying()
    }

    /// メイン音源に応じて、鳴らす側のゲインを上げ、他方を下げる。
    private func applyActiveSource() {
        switch current {
        case .binaural:
            toneGenerator.targetGain = 1.0
            synthGenerator.targetGain = 0.0
        case .modular:
            synthGenerator.targetGain = 1.0
            toneGenerator.targetGain = 0.0
        case .none:
            toneGenerator.targetGain = 0.0
            synthGenerator.targetGain = 0.0
        }
    }

    /// メイン音源を停止（環境音が鳴っていればエンジンは動かし続ける）。
    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        toneGenerator.targetGain = 0.0
        synthGenerator.targetGain = 0.0
        updateNowPlaying()
        updateEngineActive()
    }

    /// 再生／停止をトグル。
    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    // MARK: - 環境音

    private func applyAmbience(_ kind: AmbienceKind) {
        let level = ambienceEnabled.contains(kind) ? (ambienceLevels[kind] ?? 0) : 0
        ambienceGenerator.setTarget(kind, level)
        updateEngineActive()
        updateNowPlaying()
    }

    // MARK: - エンジンの稼働管理（メイン or 環境音のどちらかが鳴るなら動かす）

    private func updateEngineActive() {
        let shouldRun = isPlaying || anyAmbienceOn
        if shouldRun {
            stopTask?.cancel()
            stopTask = nil
            startEngineIfNeeded()
        } else {
            scheduleEngineStop()
        }
    }

    private func startEngineIfNeeded() {
        #if !os(macOS)
        if !isConfigured { configureSession() }
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("AVAudioEngine の起動に失敗: \(error)")
            }
        }
    }

    private func scheduleEngineStop() {
        stopTask?.cancel()
        stopTask = Task { [weak self] in
            // フェードアウトの完了を待ってからエンジンを止める
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, !Task.isCancelled else { return }
            if !self.isPlaying && !self.anyAmbienceOn {
                self.engine.pause()
            }
        }
    }

    // MARK: - 現在再生中の判定（UI 用）

    func isCurrent(_ preset: BinauralPreset) -> Bool { current == .binaural(preset) }
    func isCurrent(_ track: ModularTrack) -> Bool { current == .modular(track) }

    // MARK: - ロック画面／コントロールセンター

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [:]
        let title = current?.title ?? (anyAmbienceOn
            ? String(localized: "環境音")
            : String(localized: "バイノーラルビート"))
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyArtist] = current?.subtitle ?? ""
        info[MPNowPlayingInfoPropertyPlaybackRate] = (isPlaying || anyAmbienceOn) ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - 割り込み（着信など）

    private func observeInterruptions() {
        #if !os(macOS)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleInterruption(notification)
            }
        }
        #endif
    }

    #if !os(macOS)
    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            toneGenerator.targetGain = 0.0
            synthGenerator.targetGain = 0.0
        case .ended:
            // セッションを復帰させ、必要なら再生を再開
            startEngineIfNeeded()
            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume),
               isPlaying {
                applyActiveSource()
            }
        @unknown default:
            break
        }
    }
    #endif
}
