//
//  PomodoroView.swift
//  Binaural beats
//
//  ポモドーロ機能。シンプル／サイクルの2モードを切り替え、時間を自由に設定できる。
//  集中フェーズでは選択中のバイノーラルビートを再生し、休憩／完了で停止する。
//

import SwiftUI

struct PomodoroView: View {
    @Environment(BinauralAudioEngine.self) private var audio
    @Environment(PomodoroTimer.self) private var timer

    var body: some View {
        @Bindable var timer = timer

        NavigationStack {
            Form {
                if timer.phase == .idle {
                    setupSections(timer: timer)
                } else {
                    runningSection(timer: timer)
                }
            }
            .navigationTitle("ポモドーロ")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("設定", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("settingsButton")
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        PomodoroHistoryView()
                    } label: {
                        Label("履歴", systemImage: "chart.bar.xaxis")
                    }
                    .accessibilityIdentifier("historyButton")
                }
            }
            .onChange(of: timer.phase) { _, newPhase in
                handlePhaseChange(newPhase)
            }
        }
    }

    // MARK: - 設定画面（未開始時）

    @ViewBuilder
    private func setupSections(timer: PomodoroTimer) -> some View {
        @Bindable var timer = timer

        Section {
            Picker("モード", selection: $timer.mode) {
                ForEach(PomodoroTimer.Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text(timer.mode == .simple
                 ? "設定した時間だけ集中し、終了で通知します。" as LocalizedStringKey
                 : "作業と休憩を繰り返します。各フェーズの切替を通知します。")
        }

        Section("時間の設定") {
            if timer.mode == .simple {
                MinuteStepper(title: "集中時間", value: $timer.simpleMinutes, range: 1...240)
            } else {
                MinuteStepper(title: "作業時間", value: $timer.focusMinutes, range: 1...120)
                MinuteStepper(title: "休憩時間", value: $timer.breakMinutes, range: 1...60)
                Stepper(value: $timer.totalSets, in: 1...12) {
                    LabeledContent("セット数", value: String(localized: "\(timer.totalSets) セット"))
                }
            }
        }

        Section {
            Toggle("休憩中は音を止める", isOn: $timer.pauseAudioOnBreak)
        } footer: {
            if let title = audio.current?.title {
                Text("集中中の再生曲：\(title)")
            } else {
                Text("「サウンド」タブで曲を選ぶと、集中中に自動再生されます。")
            }
        }

        Section {
            Button {
                timer.start()
            } label: {
                Label("開始", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("startButton")
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - 実行中画面

    @ViewBuilder
    private func runningSection(timer: PomodoroTimer) -> some View {
        Section {
            VStack(spacing: 20) {
                Text(timer.phaseTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(timer.phase == .breakTime ? .green : .primary)

                TimerRing(progress: timer.progress,
                          text: timer.remainingText,
                          color: ringColor(for: timer.phase))
                    .frame(width: 240, height: 240)
                    .padding(.vertical, 8)

                controlButtons(timer: timer)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func controlButtons(timer: PomodoroTimer) -> some View {
        HStack(spacing: 16) {
            if timer.phase == .finished {
                Button {
                    timer.reset()
                } label: {
                    Label("完了", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    timer.reset()
                    audio.pause()
                } label: {
                    Label("リセット", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    timer.togglePause()
                    if timer.isPaused {
                        audio.pause()
                    } else if timer.phase == .focus {
                        audio.resume()
                    }
                } label: {
                    Label(timer.isPaused ? "再開" : "一時停止",
                          systemImage: timer.isPaused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - フェーズに応じた音声制御

    private func handlePhaseChange(_ phase: PomodoroTimer.Phase) {
        switch phase {
        case .focus:
            if audio.current != nil {
                audio.resume()
            }
        case .breakTime:
            if timer.pauseAudioOnBreak {
                audio.pause()
            }
        case .finished, .idle:
            audio.pause()
        }
    }

    private func ringColor(for phase: PomodoroTimer.Phase) -> Color {
        switch phase {
        case .breakTime: return .green
        case .finished:  return .blue
        default:         return .orange
        }
    }
}

// MARK: - 補助ビュー

/// 分数を設定するステッパー行
private struct MinuteStepper: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        Stepper(value: $value, in: range) {
            LabeledContent(title, value: String(localized: "\(value)分"))
        }
    }
}

/// 残り時間を表示する進捗リング
private struct TimerRing: View {
    let progress: Double
    let text: String
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 14)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
            Text(text)
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }
}

#Preview {
    let notifications = NotificationManager()
    let cloud = CloudKeyValueStore(useICloud: false)
    let history = PomodoroHistoryStore(cloud: cloud)
    PomodoroView()
        .environment(AppSettings())
        .environment(BinauralAudioEngine())
        .environment(PomodoroTimer(notifications: notifications, history: history, cloud: cloud))
        .environment(history)
}
