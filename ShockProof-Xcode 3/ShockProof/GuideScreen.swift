import SwiftUI
import Foundation

// MARK: - Per-field help (looked up by field title in MoneyField)

enum FieldHelp {
    static let text: [String: String] = [
        "Savings balance":
            "Money in a savings account that you can withdraw today without a penalty. It counts as cash in the simulation.",
        "Savings interest (APY)":
            "The yearly interest your savings account pays (APY = annual percentage yield). Find it on your bank's website or statement. We compare it with a 4.5% high-yield account, an assumption you can see in the rescue plan, to estimate what moving your cash would earn.",
        "Locked deposit / CD":
            "Money locked in a certificate of deposit or term deposit until its maturity date. It is NOT counted as cash, because spending it early costs a penalty. If your risk stays high, the rescue plan may suggest breaking it as a last resort.",
        "Deposit rate (APY)":
            "The yearly interest the locked deposit earns. Together with the penalty below, it tells us how much you would lose by withdrawing early.",
        "Car insurance deductible":
            "What you pay yourself before insurance pays on a claim. It's printed on your policy. The 'Car accident' event on the Futures tab uses this number as your out-of-pocket cost.",
        "Home / renters deductible":
            "What you pay yourself before home or renters insurance pays on a claim. The 'Home or renters claim' event on the Futures tab uses this number as your out-of-pocket cost.",
    ]
}

struct HelpButton: View {
    let title: String
    let text: String
    @State private var show = false
    var body: some View {
        Button { show = true } label: {
            Image(systemName: "questionmark.circle").font(.subheadline)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What is \(title)?")
        .sheet(isPresented: $show) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(rounded(24))
                Text(text).font(.body)
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .screen()
            .presentationDetents([.medium])
        }
    }
}

// MARK: - Guide

struct GuideStep: Identifiable {
    let id: Int
    let icon: String
    let title: String
    let body: String
    let tips: [String]
}

enum Glossary {
    static let items: [(term: String, meaning: String)] = [
        ("Starting cash",
         "The money the simulation starts with: checking plus savings you can spend today. Locked deposits are not included. You can edit it on the Foundation tab under \"Total Cash for Simulation\"."),
        ("Risk of running out of cash",
         "We replay your money through thousands of possible futures. This is the share of them where your cash hits zero at some point in the time window. \"1 in 10\" means about 10% of futures. It is not a prediction of what will happen. It measures how fragile your finances are to bad luck."),
        ("How far ahead",
         "The length of the future we simulate: 1, 3, 5 or 10 years. Longer windows give more time for a bad shock to land, so the risk number usually rises."),
        ("Life events",
         "Things you choose to add: a baby, a new car, a home, a raise, a job loss. Each one changes your monthly income or costs from the month you pick."),
        ("Random risks",
         "Ordinary-life shocks like car repairs, medical bills, layoffs and storms, each with a realistic chance and cost. Some cluster together, for example layoffs during recessions. \"About you\" and the Risks tab decide which ones apply to you."),
        ("Fan chart",
         "The dark line is the most likely path of your cash. The darker band covers the middle half of outcomes and the lighter band covers nearly all of them. The dashed red line is zero: if the shaded area dips below it, some futures run out of cash."),
        ("Worst-case cash",
         "A bad-luck outcome: only about 1 in 20 simulated futures ends with less cash than this."),
        ("Rescue plan",
         "A list of fixes, cheapest first: move savings to a higher rate, cancel subscriptions, trim spending, break a deposit, pick up extra work. Each step is re-simulated, so the risk shown after it is real, not guessed."),
        ("Cash cushion",
         "How much starting cash would bring your risk down to the target. The chart re-runs the simulation with different starting balances."),
        ("APY",
         "Annual percentage yield: the interest an account pays per year, including compounding."),
        ("Locked deposit / CD",
         "A deposit you agreed not to touch until a set date in exchange for a higher rate."),
        ("Early-withdrawal penalty",
         "What you forfeit if you take a deposit out early, usually a number of months of interest. Check your deposit agreement for the exact terms. The app estimates it as months of interest on the amount."),
        ("Deductible",
         "The part of an insurance claim you pay yourself before the insurer pays the rest."),
        ("Transfers",
         "Money moving between your own accounts, such as checking to savings or a credit card payment. We ignore them so they aren't counted as income or spending."),
        ("Sample data",
         "Demo transactions the backend loads when you link a bank without real credentials. Upload your own statements and turn on \"Replace the sample data\" to use your real numbers."),
        ("Assumptions",
         "Gig pay of $110 per shift and a 4.5% savings rate are assumptions used in the rescue plan. Everything else comes from your statements or the backend's risk catalog."),
    ]
}

struct GuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    static let steps: [GuideStep] = [
        GuideStep(id: 0, icon: "tray.and.arrow.up", title: "Add your money data",
                  body: "Go to the Accounts tab and add a statement from your bank (PDF or CSV). We read every transaction, skip duplicates, and ignore transfers between your own accounts. Add several files to cover more months or more accounts.",
                  tips: ["Turn on \"Replace the sample data\" the first time, so demo numbers don't mix with yours.",
                         "More months means better detection. One month finds almost no recurring bills, because bills are found by repeating.",
                         "Scanned PDFs can't be read. Download the text-based PDF or the CSV from your bank's website."]),
        GuideStep(id: 1, icon: "checkmark.seal", title: "Check what we read",
                  body: "On the Accounts tab, \"What we read from your files\" shows how many transactions were parsed, the date range, and a few recent rows. The Foundation tab shows the paychecks, bills and subscriptions we found automatically.",
                  tips: ["If a paycheck or your rent is missing, add an older statement.",
                         "If amounts look flipped (a deposit shown as spending), re-export the CSV from your bank.",
                         "Your starting cash is editable on the Foundation tab."]),
        GuideStep(id: 2, icon: "banknote", title: "Add what a bank feed can't see",
                  body: "Savings balance and rate, a locked deposit or CD, and your insurance deductibles are not in your transactions. Add them on the Accounts tab. Tap the ? next to a field to see what it means.",
                  tips: ["A locked deposit is not counted as cash, but it can show up as a last-resort rescue step.",
                         "Deductibles decide how much a car or home claim costs you.",
                         "Turn on \"I have a mortgage\" so homeowner risks apply to you."]),
        GuideStep(id: 3, icon: "bolt", title: "Choose what could go wrong",
                  body: "On the Futures tab, add life events and shocks, tell us about yourself, and pick how far ahead to look. The \"random risks of life\" switch adds everyday shocks on top. Use the Risks tab to switch off the ones that don't apply to you.",
                  tips: ["\"About you\" (age, state, housing, kids, pets, car) decides which risks apply.",
                         "Each event has a start month. Try the same event earlier and later and compare."]),
        GuideStep(id: 4, icon: "chart.line.uptrend.xyaxis", title: "Read your odds",
                  body: "Tap \"Simulate my future\". The headline says how often your cash runs out across thousands of simulated futures. The fan chart shows the range of paths, and \"Random risks that hurt most\" shows which shocks add the most risk.",
                  tips: ["The odds are not a forecast. They show how well your cash absorbs bad luck.",
                         "Switch between \"Today's path\", \"With events\" and \"With plan\" to see what changes."]),
        GuideStep(id: 5, icon: "lifepreserver", title: "Fix it",
                  body: "The rescue plan lists fixes from easiest to hardest. Each one is simulated again, so you see the real risk after it. The cash cushion shows how much starting cash reaches your target risk.",
                  tips: ["Cancelled subscriptions and a better savings rate are the easy wins.",
                         "Gig pay and the 4.5% savings rate are assumptions, and the app says so."]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("How ShockProof works").font(rounded(20))
                Spacer()
                Button("Close") { dismiss() }.font(.subheadline.weight(.semibold))
            }.padding(20)

            TabView(selection: $page) {
                ForEach(Self.steps) { s in
                    StepPage(step: s, total: Self.steps.count).tag(s.id)
                }
                GlossaryPage().tag(Self.steps.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            HStack(spacing: 12) {
                if page > 0 {
                    Button { withAnimation { page -= 1 } } label: { Text("Back") }
                        .buttonStyle(StickerButton(color: .white, text: Theme.ink))
                }
                Button {
                    if page == Self.steps.count { dismiss() } else { withAnimation { page += 1 } }
                } label: { Text(page == Self.steps.count ? "Done" : "Next") }
                    .buttonStyle(StickerButton(color: Theme.violet))
            }
            .padding(.horizontal, 20).padding(.bottom, 8)
        }
        .screen()
    }
}

struct StepPage: View {
    let step: GuideStep
    let total: Int
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Pill(text: "Step \(step.id + 1) of \(total)", fill: Theme.sun)
                Image(systemName: step.icon).font(.system(size: 40, weight: .bold)).foregroundStyle(Theme.violet)
                Text(step.title).font(rounded(30))
                Text(step.body).font(.body)
                if !step.tips.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(step.tips, id: \.self) { t in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.mint)
                                    Text(t).font(.subheadline)
                                }
                            }
                        }
                    }
                }
            }
            .padding(20).padding(.bottom, 40)
        }
    }
}

struct GlossaryPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Pill(text: "Glossary", fill: Theme.mint)
                Text("What every term means").font(rounded(30))
                ForEach(Glossary.items, id: \.term) { item in
                    Card {
                        DisclosureGroup {
                            Text(item.meaning).font(.subheadline).padding(.top, 6)
                        } label: {
                            Text(item.term).fontWeight(.bold)
                        }.tint(Theme.ink)
                    }
                }
            }
            .padding(20).padding(.bottom, 40)
        }
    }
}

// MARK: - What we parsed (raw statement -> transactions -> detected series -> forecast)

struct ParsePreviewCard: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        let tx = m.transactions
        let dates = tx.compactMap { isoDate($0.date) }
        let first = dates.min(), last = dates.max()
        let days: Int = {
            guard let a = first, let b = last else { return 0 }
            return Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
        }()
        let months = tx.isEmpty ? 0 : max(1, Int((Double(days) / 30.4).rounded()))
        let uncategorized = tx.filter { $0.category == "Uncategorized" }.count
        let recurring = m.profile?.recurring ?? []
        let paychecks = recurring.filter { $0.isIncome }.count
        let bills = recurring.filter { !$0.isIncome && $0.confidence >= 0.7 }.count
        let recent = Array(tx.sorted { $0.date > $1.date }.prefix(5))

        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("What we read from your files").font(rounded(20))
                Text("Statement, then transactions, then paychecks and bills, then your forecast. Check each step looks right before you trust the odds.")
                    .font(.footnote)
                if tx.isEmpty {
                    Text("Nothing loaded yet. Add a statement above.").font(.subheadline.weight(.semibold))
                } else {
                    HStack {
                        StatTile(title: "Transactions", value: "\(tx.count)")
                        StatTile(title: "Months covered", value: "\(months)")
                        StatTile(title: "Uncategorized", value: "\(uncategorized)",
                                 tint: uncategorized > tx.count / 4 ? Theme.coral : Theme.ink)
                    }
                    if let a = first, let b = last {
                        Text("From \(a.formatted(.dateTime.month(.abbreviated).day().year())) to \(b.formatted(.dateTime.month(.abbreviated).day().year())).")
                            .font(.caption)
                    }
                    Text("Found \(paychecks) paycheck series and \(bills) bills or subscriptions.").font(.subheadline.weight(.semibold))
                    if months < 3 {
                        Text("Only \(months) month\(months == 1 ? "" : "s") of data. Monthly bills are found by repeating, so add older statements for a fuller picture.")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.coral)
                    }
                    Divider().overlay(Theme.ink.opacity(0.2))
                    Text("Latest rows we parsed").font(.caption.weight(.semibold))
                    ForEach(recent) { t in
                        HStack {
                            Text(prettyDate(t.date)).font(rounded(13, .bold)).frame(width: 56, alignment: .leading)
                            Text(t.merchant.isEmpty ? t.merchantRaw : t.merchant).lineLimit(1)
                            Spacer()
                            Text(t.amount.signedUsd).fontWeight(.bold)
                        }.font(.subheadline)
                    }
                    if let b = m.profile?.baseline {
                        Divider().overlay(Theme.ink.opacity(0.2))
                        Text("These numbers drive your forecast").font(.caption.weight(.semibold))
                        Text("Income \(b.monthlyIncome.usd) a month, fixed bills \(b.monthlyFixed.usd), everyday spending \(b.monthlyVariableMean.usd) (swings by about \(b.monthlyVariableStd.usd)).")
                            .font(.footnote)
                    }
                }
            }
        }
    }
}
