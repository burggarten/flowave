//
//  NowPlayingBar.swift
//  Binaural beats
//
//  画面下部に常駐する再生コントロール。再生／停止・音量・背景ノイズを操作する。
//  背景ノイズはバイノーラルビート再生時のみ表示する。
//

import SwiftUI

struct NowPlayingBar: View {
    @Environment(BinauralAudioEngine.self) private var audio
    @State private var showsSettings = false

    var body: some View {
        @Bindable var audio = audio

        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Button {
                    audio.togglePlayPause()
                } label: {
                    Image(systemName: audio.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 40))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(audio.current?.color ?? .accentColor)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(audio.current?.title ?? "—")
                        .font(.headline)
                        .lineLimit(1)
                    if let subtitle = audio.current?.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button {
                    showsSettings.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            if showsSettings {
                controls(audio: audio)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
        .animation(.easeInOut(duration: 0.2), value: showsSettings)
    }

    @ViewBuilder
    private func controls(audio: BinauralAudioEngine) -> some View {
        @Bindable var audio = audio
        HStack {
            Image(systemName: "speaker.fill").foregroundStyle(.secondary)
            Slider(value: $audio.volume, in: 0...1)
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
        }
    }
}
