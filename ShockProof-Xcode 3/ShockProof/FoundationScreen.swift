import SwiftUI
import Foundation
import Charts

// Layer 1: everything here comes from the parsed bank history.
struct FoundationView: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        NavigationStack {
            ScrollView {
                if let p = m.profile {
                    VStack(spacing: 22) {
                        ScreenTitle(title: "Your financial twin",
                                    sub: "Built from \(m.transactions.count) transactions. " + (m.plaidLive == true ? "Plaid live." : "Sample bank data."))
                        HeroCard(b: p.baseline)
                        FlowCard(b: p.baseline)
                        DetectedCard(recurring: p.recurring)
                        CategoriesCard()
                        TimingCard(f: p.overdraftForecast, b: p.baseline)
                        UpcomingCard(recurring: p.recurring)
                        Button("Unlink bank") { m.disconnect() }.font(.footnote.weight(.semibold))
                    }.padding(20)
                }
            }
            .screen().toolbar(.hidden, for: .navigationBar)
            .keyboardDoneButton()
        }
    }
}

struct HeroCard: View {
    @EnvironmentObject var m: AppModel
    let b: Baseline
    var body: some View {
        Card(fill: b.monthlyNetMean >= 0 ? Theme.mint : Theme.coral) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Left over each month").font(.subheadline.weight(.semibold))
                Text(b.monthlyNetMean.usd).font(rounded(56))
                
                Divider().overlay(Theme.ink)
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("Checking").font(.caption)
                        Text(m.cash.usd).font(.headline)
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("Savings").font(.caption)
                        Text(m.holdings.savingsBalance.usd).font(.headline)
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("Credit Debt").font(.caption).foregroundStyle(Theme.coral)
                        Text("$0").font(.headline).foregroundStyle(Theme.coral)
                    }
                }
                .padding(.vertical, 8)

                HStack {
                    FieldLabel(title: "Starting cash", bold: true)
                    Spacer(minLength: 8)
                    NumberInput(value: $m.cash, prefix: "$")
                }
            }
        }
    }
}
struct FlowCard: View {
    let b: Baseline
    var body: some View {
        let inc = max(b.monthlyIncome, 1)
        let left = max(0, b.monthlyNetMean)
        let rows: [(String, Color, Double)] = [("Fixed bills", Theme.violet, b.monthlyFixed),
                                               ("Everyday spending", Theme.sun, b.monthlyVariableMean),
                                               ("Left over", Theme.mint, left)]
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Where \(b.monthlyIncome.usd) a month goes").font(rounded(20))
                SplitBar(parts: rows.map { ($0.1, $0.2 / inc) })
                ForEach(rows.indices, id: \.self) { i in
                    HStack {
                        Circle().fill(rows[i].1).frame(width: 12, height: 12).overlay(Circle().stroke(Theme.ink, lineWidth: 1.5))
                        Text(rows[i].0); Spacer(); Text(rows[i].2.usd).fontWeight(.bold)
                    }
                }
                Text("Everyday spending swings by about \(b.monthlyVariableStd.usd) from month to month. The simulator replays that swing.")
                    .font(.footnote)
            }
        }
    }
}

struct SeriesRow: View {
    let r: Recurring
    var showConfidence = false
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.label).fontWeight(.semibold)
                Text(cadenceText(r.cadence) + (showConfidence ? ", \(Int((r.confidence * 100).rounded()))% sure" : ""))
                    .font(.caption).foregroundStyle(Theme.ink.opacity(0.7))
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(r.avgAmount.signedUsd).fontWeight(.bold).foregroundStyle(r.isIncome ? Color(red: 0.05, green: 0.5, blue: 0.35) : Theme.ink)
                Text("next \(prettyDate(r.nextExpected))").font(.caption).foregroundStyle(Theme.ink.opacity(0.7))
            }
        }
    }
}

struct DetectedCard: View {
    let recurring: [Recurring]
    var body: some View {
        let regular = ["monthly", "biweekly", "weekly", "semimonthly"]
        let lumpy = ["quarterly", "semiannual", "annual"]
        let income = recurring.filter { $0.isIncome }
        let bills = recurring.filter { !$0.isIncome && $0.confidence >= 0.7 && regular.contains($0.cadence) }
        let surprise = recurring.filter { !$0.isIncome && $0.confidence >= 0.7 && lumpy.contains($0.cadence) }
        let maybe = recurring.filter { !$0.isIncome && $0.confidence < 0.7 }
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("What we found in your bank").font(rounded(20))
                Text("Found automatically from merchant names, amounts and dates.").font(.footnote)
                if !income.isEmpty {
                    Pill(text: "Paychecks", fill: Theme.mint)
                    ForEach(income) { SeriesRow(r: $0) }
                }
                if !bills.isEmpty {
                    Pill(text: "Bills and subscriptions", fill: Theme.sun)
                    ForEach(bills) { SeriesRow(r: $0) }
                }
                if !surprise.isEmpty {
                    Pill(text: "Feels random, but we saw it coming", fill: Theme.coral)
                    ForEach(surprise) { SeriesRow(r: $0) }
                }
                if !maybe.isEmpty {
                    DisclosureGroup("Maybe recurring (\(maybe.count))") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(maybe) { SeriesRow(r: $0, showConfidence: true) }
                        }.padding(.top, 6)
                    }.font(.subheadline.weight(.semibold))
                }
            }
        }
    }
}

struct CategoriesCard: View {
    @EnvironmentObject var m: AppModel
    private var rows: [(String, Double)] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) else { return [] }
        var totals: [String: Double] = [:]
        for t in m.transactions where t.amount < 0 && !t.pending {
            if let d = isoDate(t.date), d >= cutoff {
                totals[t.category == "Uncategorized" ? "Other" : t.category, default: 0] += -t.amount
            }
        }
        return totals.map { ($0.key, $0.value / 3) }.sorted { $0.1 > $1.1 }.prefix(8).map { $0 }
    }
    var body: some View {
        let data = rows
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Where your money goes").font(rounded(20))
                Text("Average per month over the last 90 days. \(m.transactions.count) transactions sorted automatically.").font(.footnote)
                Chart(data, id: \.0) { r in
                    BarMark(x: .value("Per month", r.1), y: .value("Category", r.0))
                        .foregroundStyle(Theme.violet).cornerRadius(6)
                        .annotation(position: .trailing) { Text(r.1.usd).font(.caption.weight(.semibold)) }
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(max(1, data.count)) * 36 + 10)
            }
        }
    }
}

struct TimingCard: View {
    @EnvironmentObject var m: AppModel
    let f: OverdraftForecast
    let b: Baseline

    private var points: [(Date, Double)] {
        let shift = m.cash - b.liquidBalance
        return zip(f.dates, f.balance).compactMap { d, v in isoDate(d).map { ($0, v + shift) } }
    }
    var body: some View {
        let pts = points
        let low = pts.min { $0.1 < $1.1 }
        let first = pts.first { $0.1 < 0 }
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Next 60 days, day by day").font(rounded(20))
                if let first {
                    Text("Heads up: your balance dips below zero around \(first.0.formatted(.dateTime.month(.abbreviated).day())).")
                        .fontWeight(.semibold).foregroundStyle(Theme.coral)
                } else if let low {
                    Text("No overdraft expected. Lowest point is \(low.1.usd) around \(low.0.formatted(.dateTime.month(.abbreviated).day())).")
                        .fontWeight(.semibold)
                }
                Chart {
                    ForEach(pts, id: \.0) { p in
                        AreaMark(x: .value("Day", p.0), y: .value("Balance", p.1)).foregroundStyle(Theme.violet.opacity(0.15))
                        LineMark(x: .value("Day", p.0), y: .value("Balance", p.1)).foregroundStyle(Theme.violet)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                    }
                    RuleMark(y: .value("Zero", 0)).foregroundStyle(Theme.coral).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    ForEach(low.map { [$0] } ?? [], id: \.0) { p in
                        PointMark(x: .value("Day", p.0), y: .value("Balance", p.1)).foregroundStyle(Theme.coral).symbolSize(90)
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 14)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text(compactUsd(d)) } } } }
                .frame(height: 190)
                Text("Paydays and bills are placed on their real dates, so rent clearing before a paycheck shows up even when the month adds up.")
                    .font(.footnote)
            }
        }
    }
}

struct UpcomingCard: View {
    let recurring: [Recurring]
    var body: some View {
        let end = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        let items = recurring.filter { r in
            r.confidence >= 0.7 && (isoDate(r.nextExpected).map { $0 <= end && $0 >= Calendar.current.startOfDay(for: Date()) } ?? false)
        }.sorted { $0.nextExpected < $1.nextExpected }
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Coming up in the next 30 days").font(rounded(20))
                if items.isEmpty { Text("Nothing scheduled that we are confident about.").font(.footnote) }
                ForEach(items) { r in
                    HStack {
                        Text(prettyDate(r.nextExpected)).font(rounded(14, .bold)).frame(width: 56, alignment: .leading)
                        Text(r.label).lineLimit(1)
                        Spacer()
                        Text(r.avgAmount.signedUsd).fontWeight(.bold)
                    }
                }
            }
        }
    }
}
