//
//  SoundsView.swift
//  Binaural beats
//
//  2つのグループを切り替えて音源を選ぶ：
//   - Constant electric sound … 30曲の純音バイノーラルビート（帯域別）
//   - Modular synth           … 20曲のBGM風モジュラーシンセ（雰囲気別）
//  下部に再生コントロール（Now Playing バー）を常駐させる。
//

import SwiftUI

struct SoundsView: View {
    @Environment(BinauralAudioEngine.self) private var audio

    /// 表示中のライブラリ（グループ）
    private enum Library: String, CaseIterable, Identifiable {
        case constant = "Constant electric sound"
        case modular = "Modular synth"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .constant: return String(localized: "電子音（定常）")
            case .modular:  return String(localized: "モジュラーシンセ")
            }
        }
        /// ナビゲーションバーのタイトル（`rawValue` を翻訳テーブルのキーとして引く）
        var navigationTitle: String {
            switch self {
            case .constant: return String(localized: "Constant electric sound")
            case .modular:  return String(localized: "Modular synth")
            }
        }
    }

    @State private var library: Library = .constant
    @State private var showsAmbience = false

    var body: some View {
        NavigationStack {
            Group {
                switch library {
                case .constant: constantList
                case .modular:  modularList
                }
            }
            .navigationTitle(library.navigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsAmbience = true
                    } label: {
                        Label("環境音", systemImage: audio.anyAmbienceOn ? "leaf.fill" : "leaf")
                    }
                    .tint(audio.anyAmbienceOn ? .green : nil)
                    .accessibilityIdentifier("ambienceButton")
                }
            }
            .sheet(isPresented: $showsAmbience) {
                AmbienceView()
                    .presentationDetents([.medium, .large])
            }
            .safeAreaInset(edge: .top) {
                Picker("グループ", selection: $library) {
                    ForEach(Library.allCases) { lib in
                        Text(lib.title).tag(lib)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .safeAreaInset(edge: .bottom) {
                if audio.current != nil {
                    NowPlayingBar()
                }
            }
        }
    }

    // MARK: - Constant electric sound（バイノーラル）

    private var constantList: some View {
        List {
            Section {
                Label("ヘッドフォン／イヤホンの使用を推奨します。左右で異なる周波数を聴くことで効果が生まれます。",
                      systemImage: "headphones")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(BinauralPreset.grouped(), id: \.band) { group in
                Section {
                    ForEach(group.presets) { preset in
                        SoundRow(
                            title: preset.localizedName,
                            detail: preset.localizedDetail,
                            trailing: preset.beatText,
                            color: preset.band.color,
                            isCurrent: audio.isCurrent(preset),
                            isPlaying: audio.isPlaying && audio.isCurrent(preset)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if audio.isCurrent(preset) {
                                audio.togglePlayPause()
                            } else {
                                audio.play(preset)
                            }
                        }
                    }
                } header: {
                    Label {
                        Text("\(group.band.title) ・ \(group.band.range)")
                    } icon: {
                        Image(systemName: group.band.systemImage)
                            .foregroundStyle(group.band.color)
                    }
                } footer: {
                    Text(group.band.purpose)
                }
            }
        }
    }

    // MARK: - Modular synth（BGM）

    private var modularList: some View {
        List {
            ForEach(ModularTrack.grouped(), id: \.mood) { group in
                Section {
                    ForEach(group.tracks) { track in
                        SoundRow(
                            title: track.localizedName,
                            detail: track.localizedDetail,
                            trailing: track.bpmText,
                            color: track.mood.color,
                            isCurrent: audio.isCurrent(track),
                            isPlaying: audio.isPlaying && audio.isCurrent(track)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if audio.isCurrent(track) {
                                audio.togglePlayPause()
                            } else {
                                audio.play(track)
                            }
                        }
                    }
                } header: {
                    Label {
                        Text(group.mood.title)
                    } icon: {
                        Image(systemName: group.mood.systemImage)
                            .foregroundStyle(group.mood.color)
                    }
                } footer: {
                    Text(group.mood.purpose)
                }
            }
        }
    }
}

/// 音源1行（共通）
private struct SoundRow: View {
    let title: String
    let detail: String
    let trailing: String
    let color: Color
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: isPlaying ? "waveform" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
                    .symbolEffect(.variableColor.iterative, isActive: isPlaying)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(isCurrent ? .semibold : .regular)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(trailing)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.12), in: Capsule())
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let notifications = NotificationManager()
    let cloud = CloudKeyValueStore(useICloud: false)
    let history = PomodoroHistoryStore(cloud: cloud)
    SoundsView()
        .environment(BinauralAudioEngine())
        .environment(PomodoroTimer(notifications: notifications, history: history, cloud: cloud))
        .environment(history)
}
