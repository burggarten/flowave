//
//  AmbienceView.swift
//  Binaural beats
//
//  環境音（7種）のコントロール。各音は独立に ON/OFF・音量調整でき、
//  単独でも組み合わせでも、メイン音源と重ねても再生できる。
//

import SwiftUI

struct AmbienceView: View {
    @Environment(BinauralAudioEngine.self) private var audio
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(AmbienceKind.allCases) { kind in
                        AmbienceRow(kind: kind)
                    }
                } footer: {
                    Text("7種の環境音は、それぞれ単独でも、組み合わせても再生できます。バイノーラルビートやモジュラーシンセと重ねることも可能です。")
                }
            }
            .navigationTitle("環境音")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                        .accessibilityIdentifier("doneButton")
                }
            }
        }
    }
}

private struct AmbienceRow: View {
    @Environment(BinauralAudioEngine.self) private var audio
    let kind: AmbienceKind

    private var isOn: Binding<Bool> {
        Binding(
            get: { audio.isAmbienceEnabled(kind) },
            set: { audio.setAmbienceEnabled(kind, $0) }
        )
    }

    private var level: Binding<Double> {
        Binding(
            get: { audio.ambienceLevel(kind) },
            set: { audio.setAmbienceLevel(kind, $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: isOn) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title)
                        Text(kind.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: kind.systemImage)
                        .foregroundStyle(tint)
                }
            }

            if isOn.wrappedValue {
                HStack {
                    Image(systemName: "speaker.fill").font(.caption).foregroundStyle(.secondary)
                    Slider(value: level, in: 0...1)
                    Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var tint: Color {
        switch kind {
        case .ocean:  return .blue
        case .rain:   return .cyan
        case .forest: return .green
        case .stream: return .teal
        case .fire:   return .orange
        case .wind:   return .mint
        case .white:  return .gray
        }
    }
}

#Preview {
    AmbienceView()
        .environment(BinauralAudioEngine())
}
