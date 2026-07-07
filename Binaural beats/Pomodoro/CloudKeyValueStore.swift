//
//  CloudKeyValueStore.swift
//  Binaural beats
//
//  キー・バリューの保存先を「iCloud（NSUbiquitousKeyValueStore）」と
//  「ローカル（UserDefaults）」で切り替えられる薄いラッパー。
//  iCloud 利用の可否は AppSettings のトグルで制御し、無効時はこの端末内にのみ保存する。
//  常にローカルへもミラーするため、オフライン時や iCloud 無効化後もデータは失われない。
//

import Foundation

@MainActor
final class CloudKeyValueStore {

    private let cloud = NSUbiquitousKeyValueStore.default
    private let local = UserDefaults.standard
    private(set) var useICloud: Bool

    /// 外部（他端末）からの変更、または iCloud 利用切替時に呼ばれるリスナ群。
    private var listeners: [() -> Void] = []

    init(useICloud: Bool) {
        self.useICloud = useICloud

        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.useICloud else { return }
                self.notifyListeners()
            }
        }

        if useICloud {
            cloud.synchronize()
        }
    }

    /// 外部変更／切替を受け取るリスナを登録する。
    func addListener(_ handler: @escaping () -> Void) {
        listeners.append(handler)
    }

    private func notifyListeners() {
        for listener in listeners { listener() }
    }

    // MARK: - 読み書き

    func data(forKey key: String) -> Data? {
        if useICloud {
            // まだ iCloud から降ってきていない場合に備え、ローカルミラーへフォールバック。
            return cloud.data(forKey: key) ?? local.data(forKey: key)
        }
        return local.data(forKey: key)
    }

    /// data が nil の場合はキーを削除する。
    func set(_ data: Data?, forKey key: String) {
        if let data {
            local.set(data, forKey: key)
            if useICloud {
                cloud.set(data, forKey: key)
                cloud.synchronize()
            }
        } else {
            local.removeObject(forKey: key)
            if useICloud {
                cloud.removeObject(forKey: key)
                cloud.synchronize()
            }
        }
    }

    // MARK: - iCloud 利用切替

    func setUseICloud(_ value: Bool) {
        guard value != useICloud else { return }
        useICloud = value
        if value {
            cloud.synchronize()
        }
        // 保存先が変わったので、各ストアに再読み込み（＆ローカル固有データの押し上げ）を促す。
        notifyListeners()
    }
}
