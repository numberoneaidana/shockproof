import SwiftUI
import Foundation
import Charts

// Layer 2: life-event simulation. Every number in the results comes from POST /api/simulate.
struct FuturesView: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ScreenTitle(title: "Simulate your future",
                                sub: "Stack life events and shocks, then see how often your cash hits zero.")
                    EventsCard()
                    AboutYouCard()
                    SettingsCard()
                    Button { Task { await m.runFutures() } } label: {
                        if m.running { ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 16) }
                        else { Text("Simulate my future") }
                    }
                    .buttonStyle(StickerButton(color: Theme.coral)).disabled(m.running)
                    if let e = m.error { Text(e).font(.footnote).foregroundStyle(Theme.coral) }
                }.padding(20)
            }
            .screen().toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $m.showResults) { ResultsView() }
        }
    }
}

func fmtParam(_ v: Double, _ unit: String) -> String {
    switch unit {
    case "$": return v.usd
    case "%": return v == v.rounded() ? "\(Int(v))%" : String(format: "%.2f%%", v)
    case "mo": return "\(Int(v)) mo"
    case "yr": return "\(Int(v)) yr"
    default: return "\(Int(v))"
    }
}

struct ParamRow: View {
    let def: ParamDef
    @Binding var value: Double
    var body: some View {
        Stepper(value: $value, in: def.min...def.max, step: def.step) {
            HStack { Text(def.label).font(.subheadline); Spacer(); Text(fmtParam(value, def.unit)).font(rounded(15, .bold)).inputBox() }
        }
    }
}

struct DraftEditor: View {
    @EnvironmentObject var m: AppModel
    @Binding var draft: EventDraft
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(draft.template.label).font(rounded(18))
                Spacer()
                Button { m.drafts.removeAll { $0.id == draft.id } } label: { Image(systemName: "xmark.circle.fill").font(.title3) }
            }
            Text(draft.template.blurb).font(.footnote)
            Stepper(value: $draft.startMonth, in: 0...max(0, m.horizon - 1)) {
                HStack { Text("Starts in").font(.subheadline); Spacer()
                    Text(draft.startMonth == 0 ? "now" : "\(draft.startMonth) months").font(rounded(15, .bold)).inputBox() }
            }
            ForEach(draft.template.params) { p in
                ParamRow(def: p, value: Binding(get: { draft.values[p.key] ?? p.value }, set: { draft.values[p.key] = $0 }))
            }
            let line = m.describe(draft)
            if !line.isEmpty { Pill(text: line, fill: Theme.sun) }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.bg))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.ink, lineWidth: 1.5))
    }
}

struct EventsCard: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Life events and shocks").font(rounded(20))
                if m.drafts.isEmpty { Text("Nothing added yet. The simulation will only use the random risks of normal life.").font(.footnote) }
                ForEach($m.drafts) { $d in DraftEditor(draft: $d) }
                Menu {
                    ForEach(EventTemplate.all) { t in Button(t.label) { m.addDraft(t) } }
                } label: { StickerLabel(text: "Add an event", color: Theme.sun, fg: Theme.ink) }
            }
        }
    }
}

struct AboutYouCard: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        Card {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Stepper("Age \(m.user.age)", value: $m.user.age, in: 18...80)
                    Picker("State", selection: $m.user.state) { ForEach(usStates, id: \.self) { Text($0).tag($0) } }
                    Picker("Housing", selection: $m.user.housing) {
                        Text("Renting").tag("rent"); Text("Own a house").tag("own_house")
                        Text("Own a condo").tag("own_condo"); Text("With family").tag("with_parents")
                    }
                    Picker("Work", selection: $m.user.employment) {
                        Text("Employed").tag("employed"); Text("Self-employed").tag("self"); Text("Gig work").tag("gig")
                    }
                    Toggle("Married", isOn: $m.user.married)
                    Stepper("Children: \(m.user.children)", value: $m.user.children, in: 0...6)
                    Toggle("Pets", isOn: $m.user.hasPets)
                    Toggle("Own a car", isOn: $m.user.ownsCar)
                    Toggle("Could have a child", isOn: $m.user.canBirth)
                }.padding(.top, 8)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("About you").font(rounded(20))
                    Text("Decides which of the \(m.risks.count) risks apply: hurricanes need a coastal state, pets need pets.").font(.footnote)
                }
            }.tint(Theme.ink)
        }
    }
}

struct SettingsCard: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("How far ahead").font(rounded(20))
                Picker("Horizon", selection: $m.horizon) {
                    Text("1 yr").tag(12); Text("3 yrs").tag(36); Text("5 yrs").tag(60); Text("10 yrs").tag(120)
                }.pickerStyle(.segmented)
                Toggle("Include the random risks of life", isOn: $m.randomRisks).fontWeight(.semibold)
                Text(m.randomRisks ? "Up to \(max(0, m.risks.count - m.excluded.count)) risk types run together with realistic correlation. Change them in the Risks tab."
                                   : "Only your events and your normal month-to-month swings.").font(.footnote)
            }
        }
    }
}

// MARK: - Results

struct ResultsView: View {
    @EnvironmentObject var m: AppModel
    @State private var mode = 1

    var body: some View {
        if let base = m.baselineSim, let scen = m.scenarioSim {
            ScrollView {
                VStack(spacing: 20) {
                    HeadlineCard(base: base.summary, scen: scen.summary)
                    ChartCard(mode: $mode, base: base, scen: scen)
                    NumbersCard(s: scen.summary)
                    DriversCard(sim: scen)
                    RescueCard(scen: scen.summary)
                }.padding(20)
            }
            .screen().navigationTitle("Your futures").navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct HeadlineCard: View {
    let base: SimSummary
    let scen: SimSummary
    var body: some View {
        let p = scen.probabilityOfRuin
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: p > 0.3 ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                        .font(.largeTitle)
                        .foregroundStyle(p > 0.3 ? Theme.coral : Theme.mint)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("Your overall risk").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink.opacity(0.7))
                            if let h = FieldHelp.text["Your overall risk"] { HelpButton(title: "Your overall risk", text: h) }
                        }
                        Text(riskHeadline(p)).font(rounded(24))
                    }
                }

                Divider().overlay(Theme.ink.opacity(0.2))

                HStack(alignment: .top, spacing: 4) {
                    StatTile(title: "Most likely cash in \(horizonText(scen.horizonMonths))", value: scen.medianEndBalance.usd)
                    if let h = FieldHelp.text["Most likely cash"] { HelpButton(title: "Most likely cash", text: h) }
                }

                if let mo = scen.medianMonthsToRuin {
                    Callout {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Danger zone: month \(mo + 1)").font(rounded(18))
                            Text("In the futures that go wrong, cash usually runs out around month \(mo + 1). Your \(scen.startingBalance.usd) cushion is too small for a shock like a job loss.")
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
    }
}
struct ChartCard: View {
    @EnvironmentObject var m: AppModel
    @Binding var mode: Int
    let base: SimResult
    let scen: SimResult
    var body: some View {
        let plan = m.steps.last?.result
        let shown: SimResult = mode == 0 ? base : (mode == 2 ? (plan ?? scen) : scen)
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Picker("View", selection: $mode) {
                    Text("Today's path").tag(0); Text("With events").tag(1)
                    if plan != nil { Text("With plan").tag(2) }
                }.pickerStyle(.segmented)
                
                FanChartView(fan: shown.fanChart)
                
                HStack(spacing: 12) {
                    Label("Best case", systemImage: "circle.fill").foregroundStyle(Theme.violet.opacity(0.3))
                    Label("Most likely", systemImage: "minus").foregroundStyle(Theme.ink)
                    Label("Worst case", systemImage: "circle.fill").foregroundStyle(Theme.violet.opacity(0.1))
                }.font(.caption.weight(.semibold))
                
                Text("The thick line is your most likely path. If the shaded area drops below zero (the red line), you run out of cash.")
                    .font(.footnote)
            }
        }
    }
}

struct FanChartView: View {
    let fan: FanChart
    var body: some View {
        let total = (fan.months.last ?? 0) + 1
        let tick = total <= 24 ? 3 : (total <= 72 ? 12 : 24)
        let finalMedian = fan.p50.last ?? 0
        
        Chart {
            ForEach(Array(fan.months.enumerated()), id: \.offset) { i, mo in
                AreaMark(x: .value("Month", mo), yStart: .value("p5", fan.p5[i]), yEnd: .value("p95", fan.p95[i]), series: .value("Band", "outer"))
                    .foregroundStyle(Theme.violet.opacity(0.10))
                
                AreaMark(x: .value("Month", mo), yStart: .value("p25", fan.p25[i]), yEnd: .value("p75", fan.p75[i]), series: .value("Band", "inner"))
                    .foregroundStyle(Theme.violet.opacity(0.25))
                
                LineMark(x: .value("Month", mo), y: .value("Median", fan.p50[i]), series: .value("Line", "median"))
                    .foregroundStyle(Theme.ink).lineStyle(StrokeStyle(lineWidth: 3))
                    .interpolationMethod(.catmullRom)
            }
            
            RuleMark(y: .value("Zero", 0)).foregroundStyle(Theme.coral).lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
            
            PointMark(x: .value("Month", total), y: .value("Median", finalMedian))
                .foregroundStyle(Theme.ink)
                .annotation(position: .topLeading, spacing: 4) {
                    Text("Likely: \(compactUsd(finalMedian))")
                        .font(.caption.weight(.bold))
                        .padding(4)
                        .background(Theme.bg)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.ink, lineWidth: 1))
                }
        }
        .chartXAxis {
            AxisMarks(values: Array(stride(from: 0, through: total, by: tick))) { v in
                AxisGridLine()
                AxisValueLabel {
                    if let mo = v.as(Int.self) { Text(mo == 0 ? "Now" : (total > 24 ? "Yr \(mo / 12)" : "Mo \(mo)")) }
                }
            }
        }
        .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text(compactUsd(d)) } } } }
        .frame(height: 280)
    }
}

struct NumbersCard: View {
    let s: SimSummary
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("The numbers behind it").font(rounded(20))
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                    GridRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Most likely cash in \(horizonText(s.horizonMonths))").font(.caption.weight(.semibold))
                            Text(compactUsd(s.medianEndBalance)).font(rounded(24))
                            Text("If you save your usual amount").font(.caption2).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Worst-case cash").font(.caption.weight(.semibold))
                            Text(compactUsd(s.p5EndBalance)).font(rounded(24)).foregroundStyle(Theme.coral)
                            Text("If you have bad luck with shocks").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    GridRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Average cost of shocks").font(.caption.weight(.semibold))
                            Text(compactUsd(s.expectedTotalShockCost)).font(rounded(24))
                            Text("E.g., car repairs, medical bills").font(.caption2).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Monthly savings").font(.caption.weight(.semibold))
                            Text(compactUsd(s.monthlyNetMean)).font(rounded(24)).foregroundStyle(Theme.mint)
                            Text("Your typical leftover cash").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
struct DriversCard: View {
    let sim: SimResult
    var body: some View {
        let drivers = sim.topDrivers.filter { ($0.deltaRuin ?? 0) > 0.005 }.prefix(6)
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Random risks that hurt most on top of this").font(rounded(20))
                Text("\(sim.riskAttribution.count) risk types simulated together. Layoffs cluster with recessions, storms with property damage.")
                    .font(.footnote)
                if drivers.isEmpty { Text("No single risk moves the odds much. Your cushion is doing its job.").font(.subheadline) }
                ForEach(Array(drivers)) { d in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(d.label).fontWeight(.semibold)
                            Spacer()
                            Text("+\(Int(((d.deltaRuin ?? 0) * 100).rounded())) pts").font(rounded(14, .bold))
                        }
                        SplitBar(parts: [(Theme.coral, min(1, d.deltaRuin ?? 0)), (Theme.bg, 1 - min(1, d.deltaRuin ?? 0))])
                        Text("\(pct(d.pOccursInHorizon)) chance it happens in this window").font(.caption)
                    }
                }
            }
        }
    }
}

struct RescueCard: View {
    @EnvironmentObject var m: AppModel
    let scen: SimSummary
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your rescue plan").font(rounded(22))
                if m.rescuing {
                    HStack(spacing: 10) { ProgressView(); Text("Testing fixes against the simulator").font(.subheadline) }
                } else if m.steps.isEmpty {
                    Text(m.rescueAchieved ? "Your risk is already close to normal. No rescue needed." : "No fixes found.").font(.subheadline)
                } else {
                    Text("Cheapest fixes first. Each one is re-simulated, so the risk shown after it is real.").font(.footnote)
                    ForEach(m.steps) { s in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top) {
                                Text(s.title).fontWeight(.bold)
                                Spacer(minLength: 8)
                                Pill(text: s.group == "cd" ? "+\(s.monthly.usd) once" : "+\(s.monthly.usd)/mo", fill: Theme.mint)
                            }
                            Text(s.detail).font(.subheadline).foregroundStyle(Theme.ink.opacity(0.7))
                            HStack {
                                Pill(text: s.pain, fill: s.pain == "Easy" ? Theme.mint : (s.pain == "Medium" ? Theme.sun : Theme.coral))
                                Text("Risk after: \(pct(s.ruinAfter))").font(.caption.weight(.semibold))
                            }
                        }
                        Divider().overlay(Theme.ink.opacity(0.2))
                    }
                    HStack {
                        VStack(alignment: .leading) { Text(pct(scen.probabilityOfRuin)).font(rounded(40)).foregroundStyle(Theme.coral); Text("risk now").font(.caption) }
                        Spacer(); Text("to").font(rounded(18, .bold)); Spacer()
                        VStack(alignment: .trailing) { Text(pct(m.steps.last?.ruinAfter ?? 1)).font(rounded(40)); Text("with this plan").font(.caption) }
                    }
                    .padding(14).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.mint.opacity(0.4)))
                    if !m.rescueAchieved {
                        Text("Cuts and extra income alone can't absorb this. Your target is \(pct(m.rescueTarget)).")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.coral)
                    }
                    Text("Gig pay and the 4.5% savings rate are assumptions. Everything else comes from your bank history.").font(.caption)
                }
                if !m.cushion.isEmpty { CushionView() }
            }
        }
    }
}

struct CushionView: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Theme.ink)
            Text("Cash cushion").font(rounded(18))
            if let need = m.cushionNeeded {
                Text("About \(need.usd) in cash gets this scenario down to \(pct(m.rescueTarget)) risk. You have \(m.cash.usd).").font(.subheadline.weight(.semibold))
            } else {
                Text("Even \((m.cushion.last?.balance ?? 0).usd) in cash doesn't reach \(pct(m.rescueTarget)) risk here.").font(.subheadline.weight(.semibold))
            }
            Chart {
                ForEach(m.cushion) { p in
                    LineMark(x: .value("Cash", p.balance), y: .value("Risk", p.ruin * 100)).foregroundStyle(Theme.violet).lineStyle(StrokeStyle(lineWidth: 3))
                    PointMark(x: .value("Cash", p.balance), y: .value("Risk", p.ruin * 100)).foregroundStyle(Theme.violet)
                }
                RuleMark(y: .value("Target", m.rescueTarget * 100)).foregroundStyle(Theme.mint).lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }
            .chartXAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text(compactUsd(d)) } } } }
            .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d))%") } } } }
            .frame(height: 150)
            Text("Chance of running out of cash for different starting balances, re-simulated by the backend.").font(.caption)
        }
    }
}
