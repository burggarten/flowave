//
//  ContentView.swift
//  Binaural beats
//
//  サウンド選択タブとポモドーロタブを持つルートビュー。
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SoundsView()
                .tabItem {
                    Label("サウンド", systemImage: "waveform")
                }

            PomodoroView()
                .tabItem {
                    Label("ポモドーロ", systemImage: "timer")
                }
        }
    }
}

#Preview {
    let notifications = NotificationManager()
    let cloud = CloudKeyValueStore(useICloud: false)
    let history = PomodoroHistoryStore(cloud: cloud)
    ContentView()
        .environment(AppSettings())
        .environment(BinauralAudioEngine())
        .environment(PomodoroTimer(notifications: notifications, history: history, cloud: cloud))
        .environment(history)
}
