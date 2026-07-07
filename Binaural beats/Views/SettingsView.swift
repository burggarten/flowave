//
//  SettingsView.swift
//  Binaural beats
//
//  アプリの設定画面。iCloud 同期の利用可否を切り替えられる。
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("iCloud を使用", isOn: $settings.useICloud)
            } header: {
                Text("同期")
            } footer: {
                Text(settings.useICloud
                     ? "ポモドーロの履歴と実行中のセッションが、iCloud を通じてお使いのすべての端末で同期されます。" as LocalizedStringKey
                     : "履歴と実行中のセッションはこの端末内にのみ保存され、他の端末とは同期されません。")
            }
        }
        .navigationTitle("設定")
        .inlineNavigationTitleIfAvailable()
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AppSettings())
    }
}
