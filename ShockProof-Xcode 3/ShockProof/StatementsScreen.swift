import SwiftUI
import Foundation
import UniformTypeIdentifiers

// MARK: - Models

/// Response of POST /api/accounts/{id}/import  (decoded with convertFromSnakeCase in API.run)
struct ImportResult: Decodable {
    let accountId: String
    let rows, inserted, skippedDuplicates, transfersExcluded: Int
    let firstDate, lastDate: String
    let warning: String?
}

/// Things a bank feed can't tell us. Everything is optional; zero means "none".
struct Holdings: Equatable {
    var savingsBalance = 0.0        // liquid savings, counted as cash
    var savingsApy = 0.5            // percent
    var depositAmount = 0.0         // CD / locked deposit, NOT counted as cash
    var depositApy = 4.5            // percent
    var depositPenaltyMonths = 3.0  // early-withdrawal penalty, in months of interest
    var autoDeductible = 1000.0
    var homeDeductible = 2500.0
    var hasMortgage = false

    var depositPenalty: Double { depositAmount * depositApy / 1200 * depositPenaltyMonths }
    var depositNet: Double { max(0, depositAmount - depositPenalty) }
}

// MARK: - Small inputs

/// Label with a ? button on the left, editable number box on the right.
struct FieldLabel: View {
    let title: String
    var bold = false
    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.subheadline).fontWeight(bold ? .semibold : .regular)
            if let h = FieldHelp.text[title] { HelpButton(title: title, text: h) }
        }
    }
}

struct MoneyField: View {
    let title: String
    @Binding var value: Double
    var suffix = ""
    var body: some View {
        HStack {
            FieldLabel(title: title)
            Spacer(minLength: 8)
            NumberInput(value: $value, prefix: suffix.isEmpty ? "$" : "", suffix: suffix)
        }
    }
}

// MARK: - Screen

struct StatementsView: View {
    @EnvironmentObject var m: AppModel
    @State private var picking = false
    @State private var replaceSample = true
    @State private var showGuide = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ScreenTitle(title: "Your accounts",
                                sub: "Add statements and the things your bank can't see.")
                    Button { showGuide = true } label: { Label("How this works", systemImage: "questionmark.circle") }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    importCard
                    ParsePreviewCard()
                    savingsCard
                    protectionCard
                }.padding(20)
            }
            .screen().toolbar(.hidden, for: .navigationBar)
            .keyboardDoneButton()
            .sheet(isPresented: $showGuide) { GuideView() }
            .fileImporter(isPresented: $picking,
                          allowedContentTypes: [.commaSeparatedText, .plainText, .pdf],
                          allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                Task {
                    for (i, u) in urls.enumerated() { await m.importStatement(u, replace: replaceSample && i == 0) }
                    await m.reloadProfile()
                }
            }
        }
    }

    private var importCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Bank statements").font(rounded(20))
                Text("Download a PDF or CSV from your bank's website. You can add several files.")
                    .font(.footnote)
                Toggle(isOn: $replaceSample) { FieldLabel(title: "Replace the sample data", bold: true) }
                if m.busy {
                    HStack(spacing: 10) { ProgressView(); Text("Reading your statement").font(.subheadline) }
                } else {
                    Button { picking = true } label: { Text("Add statement (PDF or CSV)") }
                        .buttonStyle(StickerButton(color: Theme.violet))
                }
                if let n = m.importNote {
                    Text(n).font(.footnote.weight(.semibold)).padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.mint.opacity(0.5)))
                }
                if let e = m.error { Text(e).font(.footnote).foregroundStyle(Theme.coral) }
            }
        }
    }

    private var savingsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Savings and deposits").font(rounded(20))
                MoneyField(title: "Savings balance", value: $m.holdings.savingsBalance)
                MoneyField(title: "Savings interest (APY)", value: $m.holdings.savingsApy, suffix: "%")
                Divider().overlay(Theme.ink.opacity(0.2))
                MoneyField(title: "Locked deposit / CD", value: $m.holdings.depositAmount)
                if m.holdings.depositAmount > 0 {
                    MoneyField(title: "Deposit rate (APY)", value: $m.holdings.depositApy, suffix: "%")
                    Stepper(value: $m.holdings.depositPenaltyMonths, in: 0...12, step: 1) {
                        HStack {
                            FieldLabel(title: "Early-withdrawal penalty")
                            Spacer(minLength: 4)
                            Text("\(Int(m.holdings.depositPenaltyMonths)) mo").font(rounded(15, .bold)).inputBox()
                        }
                    }
                    Text("Breaking it early frees \(m.holdings.depositNet.usd) after a \(m.holdings.depositPenalty.usd) penalty.")
                        .font(.footnote)
                }
                Button("Use as starting cash") { m.applyHoldingsToCash() }
                    .buttonStyle(StickerButton(color: Theme.sun, text: Theme.ink))
                HStack(spacing: 6) {
                    Text("Starting cash now: \(m.cash.usd)").font(.caption.weight(.semibold))
                    if let h = FieldHelp.text["Starting cash"] { HelpButton(title: "Starting cash", text: h) }
                }
            }
        }
    }

    private var protectionCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Insurance and home").font(rounded(20))
                Text("What you pay yourself when you file a claim.").font(.footnote)
                MoneyField(title: "Car insurance deductible", value: $m.holdings.autoDeductible)
                MoneyField(title: "Home / renters deductible", value: $m.holdings.homeDeductible)
                Toggle(isOn: $m.holdings.hasMortgage) { FieldLabel(title: "I have a mortgage", bold: true) }
                    .onChange(of: m.holdings.hasMortgage) { on in
                        m.user.housing = on ? "own_house" : "rent"
                    }
            }
        }
    }
}

// ============================================================
// Guide, glossary and parse preview (merged from GuideScreen.swift)
// ============================================================

// MARK: - Per-field help (looked up by field title in MoneyField)

enum FieldHelp {
    static let text: [String: String] = [
        "Starting cash":
            "The money we start the simulation with: checking plus savings you can spend today. Locked deposits are not included. You can also change it on the Foundation tab.",
        "Savings balance":
            "Money in savings that you can use today without a penalty. It counts as cash.",
        "Savings interest (APY)":
            "What your savings pays per year. APY just means yearly interest. You can find it in your bank's app.",
        "Locked deposit / CD":
            "Money your bank holds until a set date (a CD). We don't count it as cash, because taking it out early costs a penalty.",
        "Deposit rate (APY)":
            "The yearly interest your locked deposit earns.",
        "Early-withdrawal penalty":
            "The fee for taking a locked deposit out early, counted in months of interest. It's written in your deposit agreement.",
        "Car insurance deductible":
            "What you pay first when you make a claim. Insurance covers the rest. It's on your policy.",
        "Home / renters deductible":
            "What you pay first when you make a claim. Insurance covers the rest. It's on your policy.",
        "I have a mortgage":
            "Turn this on if you own your home with a loan. It adds homeowner risks, like big repairs.",
        "Your overall risk":
            "We replay your money through thousands of possible futures. This is how many of them hit zero cash. It's not a prediction. It shows how well your cash handles bad luck.",
        "Most likely cash":
            "The middle result of all the futures we tried. Half end with more cash than this, half with less.",
        "Replace the sample data":
            "The app starts with demo transactions. Turn this on so your own statement replaces them.",
    ]
}

struct HelpButton: View {
    let title: String
    let text: String
    @State private var show = false
    var body: some View {
        Button { show = true } label: {
            Image(systemName: "questionmark.circle.fill").font(.body).foregroundStyle(Theme.violet)
                .padding(4).contentShape(Rectangle())
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
         "The money the simulation starts with: checking plus savings you can spend today. Locked deposits are not included. You can edit it on the Foundation tab under \"Starting cash\"."),
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
                Text("Check this looks right before you trust the odds.")
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
