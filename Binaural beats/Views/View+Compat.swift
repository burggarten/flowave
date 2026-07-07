//
//  View+Compat.swift
//  Binaural beats
//
//  マルチプラットフォーム（iOS / macOS / visionOS）向けの薄い互換ヘルパー。
//

import SwiftUI

extension View {
    /// ナビゲーションタイトルをインライン表示にする（macOS では該当 API が無いので無視）。
    @ViewBuilder
    func inlineNavigationTitleIfAvailable() -> some View {
        #if os(macOS)
        self
        #else
        self.navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
