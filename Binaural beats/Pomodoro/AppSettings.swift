//
//  AppSettings.swift
//  Binaural beats
//
//  アプリ全体の設定。現在は iCloud 同期の利用可否を保持する。
//  値は UserDefaults に永続化し、変更時に onChangeUseICloud で保存先ストアへ通知する。
//

import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {

    /// iCloud 同期を利用するか（既定: オン）。
    var useICloud: Bool {
        didSet {
            guard useICloud != oldValue else { return }
            UserDefaults.standard.set(useICloud, forKey: Self.key)
            onChangeUseICloud?(useICloud)
        }
    }

    /// トグル変更を保存先ストアへ伝えるためのフック。
    var onChangeUseICloud: ((Bool) -> Void)?

    private static let key = "settings.useICloud"

    init() {
        // 初回起動時は既定でオンにする。
        if UserDefaults.standard.object(forKey: Self.key) == nil {
            UserDefaults.standard.set(true, forKey: Self.key)
        }
        useICloud = UserDefaults.standard.bool(forKey: Self.key)
    }
}
