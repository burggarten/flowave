//
//  PomodoroHistoryView.swift
//  Binaural beats
//
//  集中セッションの履歴を Swift Charts でグラフ化する画面。
//  日ごとの集中時間を棒グラフで表示し、期間（7日／30日）を切り替えられる。
//

import SwiftUI
import Charts

struct PomodoroHistoryView: View {
    @Environment(PomodoroHistoryStore.self) private var history

    /// 表示期間。
    private enum Span: String, CaseIterable, Identifiable {
        case week
        case month
        var id: String { rawValue }
        var title: String { self == .week ? String(localized: "7日間") : String(localized: "30日間") }
        var days: Int { self == .week ? 7 : 30 }
    }

    @State private var span: Span = .week
    @State private var showClearConfirm = false

    var body: some View {
        List {
            if history.sessions.isEmpty {
                Section {
                    ContentUnavailableView(
                        "履歴はまだありません",
                        systemImage: "chart.bar.xaxis",
                        description: Text("集中フェーズを最後まで完了すると、ここに記録されます。")
                    )
                }
            } else {
                Section {
                    Picker("期間", selection: $span) {
                        ForEach(Span.allCases) { span in
                            Text(span.title).tag(span)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("日ごとの集中時間") {
                    chart
                        .frame(height: 240)
                        .padding(.vertical, 8)
                }

                Section("サマリー") {
                    LabeledContent("合計集中時間", value: durationText(totalMinutes))
                    LabeledContent("完了セッション", value: String(localized: "\(totalSessions) 回"))
                    LabeledContent("1日あたり平均", value: durationText(totalMinutes / max(1, span.days)))
                }

                Section {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("履歴を消去", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("履歴")
        .inlineNavigationTitleIfAvailable()
        .confirmationDialog("すべての履歴を消去しますか？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("消去", role: .destructive) { history.clearAll() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この操作は取り消せません。iCloud 上の履歴もすべての端末から削除されます。")
        }
    }

    // MARK: - グラフ

    @ViewBuilder
    private var chart: some View {
        Chart(dailyStats) { stat in
            BarMark(
                x: .value("日", stat.date, unit: .day),
                y: .value("分", stat.minutes)
            )
            .foregroundStyle(.orange.gradient)
            .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: span == .week ? 1 : 5)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let minutes = value.as(Int.self) {
                        Text("\(minutes)分")
                    }
                }
            }
        }
    }

    // MARK: - 集計

    /// 1日分の集計値。
    private struct DailyStat: Identifiable {
        let date: Date
        let minutes: Int
        let count: Int
        var id: Date { date }
    }

    /// 表示期間内の、日ごとの集計（データの無い日も 0 として含める）。
    private var dailyStats: [DailyStat] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(span.days - 1), to: today) else {
            return []
        }

        var buckets: [Date: (minutes: Int, count: Int)] = [:]
        for session in history.sessions {
            let day = calendar.startOfDay(for: session.date)
            guard day >= start else { continue }
            var bucket = buckets[day] ?? (0, 0)
            bucket.minutes += session.focusMinutes
            bucket.count += 1
            buckets[day] = bucket
        }

        return (0..<span.days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let bucket = buckets[day] ?? (0, 0)
            return DailyStat(date: day, minutes: bucket.minutes, count: bucket.count)
        }
    }

    private var totalMinutes: Int {
        dailyStats.reduce(0) { $0 + $1.minutes }
    }

    private var totalSessions: Int {
        dailyStats.reduce(0) { $0 + $1.count }
    }

    /// 分数を「1時間30分」のような文字列にする。
    private func durationText(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return mins > 0
                ? String(localized: "\(hours)時間\(mins)分")
                : String(localized: "\(hours)時間")
        }
        return String(localized: "\(mins)分")
    }
}

#Preview {
    let store = PomodoroHistoryStore(cloud: CloudKeyValueStore(useICloud: false))
    return NavigationStack {
        PomodoroHistoryView()
            .environment(store)
    }
}
