import SwiftUI
import Foundation

struct StressView: View {
    @EnvironmentObject var m: AppModel
    @State private var months = 36

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ScreenTitle(title: "Stress-test lab",
                                sub: "Seven named disasters, each replayed on your own cash flow and cash on hand.")
                    Picker("Horizon", selection: $months) { Text("1 yr").tag(12); Text("3 yrs").tag(36); Text("5 yrs").tag(60) }
                        .pickerStyle(.segmented)
                    if m.stressBusy && m.stress.isEmpty { ProgressView().padding(.top, 30) }
                    ForEach(m.stress) { s in StressRow(s: s) }
                    if let e = m.error, m.stress.isEmpty { Text(e).font(.footnote).foregroundStyle(Theme.coral) }
                }.padding(20)
            }
            .screen().toolbar(.hidden, for: .navigationBar)
            .task { if m.stress.isEmpty { await m.runStress(months: months) } }
            .onChange(of: months) { new in Task { await m.runStress(months: new) } }
        }
    }
}

struct StressRow: View {
    let s: StressScenario
    var body: some View {
        let p = s.probabilityOfRuin
        Card(fill: p > 0.5 ? Theme.coral.opacity(0.25) : .white) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(s.label).fontWeight(.bold)
                    Spacer(minLength: 8)
                    Text(odds(p)).font(rounded(20)).foregroundStyle(p > 0.5 ? Theme.coral : Theme.ink)
                }
                SplitBar(parts: [(p > 0.5 ? Theme.coral : Theme.mint, p), (Theme.bg, 1 - p)])
                
                if let mo = s.medianMonthsToRuin {
                    Text("In this scenario, your cash runs out around month \(mo + 1). Lowest point: \(compactUsd(s.medianMinBalance)).").font(.footnote)
                } else {
                    Text("You survive this scenario. Your cash dips to \(compactUsd(s.medianMinBalance)) but holds.").font(.footnote)
                }
            }
        }
    }
}
struct RisksView: View {
    @EnvironmentObject var m: AppModel

    private func detail(_ r: Risk) -> String {
        let prob = r.annualProbability < 0.01 ? String(format: "%.1f", r.annualProbability * 100) : String(Int((r.annualProbability * 100).rounded()))
        var parts = ["\(prob)% a year"]
        if r.medianCost > 0 { parts.append("typically \(r.medianCost.usd), insurance covers \(Int((r.coverage * 100).rounded()))%") }
        if r.incomeLossFraction > 0 { parts.append("loses \(Int((r.incomeLossFraction * 100).rounded()))% of income for about \(Int(r.durationMonthsMean)) months") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ScreenTitle(title: "Risk universe",
                                sub: "\(m.risks.count) things that can go wrong, with how often and how much. Switch off any that don't apply to you.")
                    ForEach(m.riskCategories, id: \.self) { cat in
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(cat).font(rounded(18))
                                ForEach(m.risks.filter { $0.category == cat }) { r in
                                    Toggle(isOn: Binding(get: { !m.excluded.contains(r.key) },
                                                         set: { on in if on { m.excluded.remove(r.key) } else { m.excluded.insert(r.key) } })) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(r.label).fontWeight(.semibold)
                                            Text(detail(r)).font(.caption).foregroundStyle(Theme.ink.opacity(0.7))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }.padding(20)
            }
            .screen().toolbar(.hidden, for: .navigationBar)
        }
    }
}
