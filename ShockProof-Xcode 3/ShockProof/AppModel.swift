import Foundation
import SwiftUI
import Combine

// MARK: - Life-event templates (editable; the math runs on YOUR detected income and rent)

struct ParamDef: Identifiable {
    let key, label, unit: String
    let value, min, max, step: Double
    var id: String { key }
}
private func P(_ key: String, _ label: String, _ unit: String, _ v: Double, _ lo: Double, _ hi: Double, _ step: Double) -> ParamDef {
    ParamDef(key: key, label: label, unit: unit, value: v, min: lo, max: hi, step: step)
}

enum EventKind { case baby, car, home, raise, rentUp, jobLoss, bill, custom }

struct EventTemplate: Identifiable {
    let id: String
    let kind: EventKind
    let label: String
    let blurb: String
    let startMonth: Int
    let params: [ParamDef]

    static let all: [EventTemplate] = [
        EventTemplate(id: "transmission", kind: .bill, label: "Car transmission fails", blurb: "A surprise repair bill.", startMonth: 1,
                      params: [P("amount", "Repair bill", "$", 2200, 100, 30000, 100), P("coverage", "Covered by insurance", "%", 0, 0, 100, 5)]),
        EventTemplate(id: "medical", kind: .bill, label: "Surprise medical bill", blurb: "ER visit or procedure after insurance.", startMonth: 1,
                      params: [P("amount", "Bill", "$", 5000, 100, 100000, 250), P("coverage", "Covered by insurance", "%", 0, 0, 100, 5)]),
        EventTemplate(id: "jobloss", kind: .jobLoss, label: "Lose your job", blurb: "Paychecks stop. Lower the percent to model unemployment benefits.", startMonth: 1,
                      params: [P("months", "Months without work", "mo", 3, 1, 24, 1), P("lost", "Income lost", "%", 100, 10, 100, 10)]),
        EventTemplate(id: "rentup", kind: .rentUp, label: "Rent goes up", blurb: "Applied to the rent we detected in your bank history.", startMonth: 1,
                      params: [P("pct", "Increase", "%", 10, 1, 50, 1)]),
        EventTemplate(id: "baby", kind: .baby, label: "Have a baby", blurb: "Monthly costs plus delivery and gear. Edit to match your plan.", startMonth: 12,
                      params: [P("monthly", "Extra cost per month", "$", 1250, 0, 5000, 50), P("upfront", "Up-front costs", "$", 3000, 0, 20000, 250)]),
        EventTemplate(id: "car", kind: .car, label: "Replace the car", blurb: "We compute the loan payment from price, down payment and rate.", startMonth: 12,
                      params: [P("price", "Price", "$", 28000, 5000, 90000, 1000), P("down", "Down payment", "$", 4000, 0, 50000, 500),
                               P("apr", "Loan rate", "%", 7, 0, 20, 0.5), P("term", "Loan length", "mo", 60, 12, 84, 12),
                               P("insurance", "Extra insurance per month", "$", 60, 0, 400, 10)]),
        EventTemplate(id: "home", kind: .home, label: "Buy a home", blurb: "Mortgage plus upkeep, minus the rent you stop paying.", startMonth: 24,
                      params: [P("price", "Price", "$", 350000, 80000, 1500000, 10000), P("downPct", "Down payment", "%", 10, 3, 50, 1),
                               P("apr", "Mortgage rate", "%", 6.5, 2, 12, 0.25), P("years", "Loan length", "yr", 30, 10, 30, 5),
                               P("upkeepPct", "Tax, insurance, upkeep per year", "%", 1.5, 0, 4, 0.25), P("closingPct", "Closing costs", "%", 3, 0, 6, 0.5)]),
        EventTemplate(id: "raise", kind: .raise, label: "Raise or new job", blurb: "Applied to your detected monthly income.", startMonth: 6,
                      params: [P("pct", "Change in income", "%", 10, -50, 100, 5)]),
        EventTemplate(id: "custom", kind: .custom, label: "Custom event", blurb: "Anything else. Set months to 0 to make it permanent.", startMonth: 0,
                      params: [P("monthly", "Extra cost per month", "$", 0, -5000, 5000, 50), P("oneTime", "One-time cost", "$", 0, 0, 100000, 500),
                               P("months", "Lasts (0 = forever)", "mo", 0, 0, 120, 1)]),
        EventTemplate(id: "caraccident", kind: .bill, label: "Car accident (your deductible)", blurb: "Insurance pays the rest. You pay the deductible.", startMonth: 1,
                      params: [P("amount", "Your deductible", "$", 1000, 0, 10000, 250)]),
        EventTemplate(id: "homeclaim", kind: .bill, label: "Home or renters claim (your deductible)", blurb: "Fire, theft or water damage. You pay the deductible.", startMonth: 1,
                      params: [P("amount", "Your deductible", "$", 2500, 0, 20000, 250)]),
    ]
    
}

struct EventDraft: Identifiable {
    let id = UUID()
    let template: EventTemplate
    var startMonth: Int
    var values: [String: Double] = [:]
}

struct CushionPoint: Identifiable {
    let id = UUID()
    let balance: Double
    let ruin: Double
}

struct RescueStep: Identifiable {
    let id = UUID()
    let group: String
    let title: String
    let detail: String
    let monthly: Double
    let pain: String
    let event: LifeEvent
    var ruinAfter = 1.0
    var result: SimResult? = nil
}

let usStates = ["AK","AL","AR","AZ","CA","CO","CT","DC","DE","FL","GA","HI","IA","ID","IL","IN","KS","KY","LA","MA","MD","ME","MI","MN","MO","MS","MT","NC","ND","NE","NH","NJ","NM","NV","NY","OH","OK","OR","PA","RI","SC","SD","TN","TX","UT","VA","VT","WA","WI","WV","WY"]

// MARK: - App state

@MainActor
final class AppModel: ObservableObject {
    // connection + layer 1
    @Published var connected = false
    @Published var busy = false
    @Published var status = ""
    @Published var error: String?
    @Published var plaidLive: Bool?
    @Published var accountId: String?
    @Published var profile: Profile?
    @Published var transactions: [BankTxn] = []
    @Published var risks: [Risk] = []
    @Published var cash = 0.0

    // layer 2 inputs
    @Published var user = UserProfile()
    @Published var drafts: [EventDraft] = []
    @Published var horizon = 60
    @Published var randomRisks = true
    @Published var excluded: Set<String> = []

    // layer 2 outputs
    @Published var baselineSim: SimResult?
    @Published var scenarioSim: SimResult?
    @Published var running = false
    @Published var showResults = false
    @Published var steps: [RescueStep] = []
    @Published var rescuing = false
    @Published var rescueTarget = 0.05
    @Published var rescueAchieved = false
    @Published var cushion: [CushionPoint] = []
    @Published var cushionNeeded: Double?
    @Published var stress: [StressScenario] = []
    @Published var stressBusy = false
    
    // accounts screen
    @Published var holdings = Holdings()
    @Published var importNote: String?

    // MARK: connect (Layer 1)

    func checkHealth() async {
        do { let h: Health = try await API.get("/health"); plaidLive = h.plaidLive; error = nil }
        catch { plaidLive = nil; self.error = error.localizedDescription }
    }

    func connect(publicToken: String = "") async {
        busy = true; error = nil
        defer { busy = false }
        do {
            let h: Health = try await API.get("/health")
            plaidLive = h.plaidLive
            var token = publicToken.trimmingCharacters(in: .whitespaces)
            if h.plaidLive {
                guard !token.isEmpty else { throw APIError(message: "The backend is using live Plaid. Paste a sandbox public_token from Plaid Link.") }
            } else {
                status = "Creating a secure link"
                let _: LinkToken = try await API.post("/api/link/create?user_id=demo-user")
                token = "public-sandbox-mock"
            }
            status = "Exchanging the token with Plaid"
            let ex: ExchangeResult = try await API.post("/api/link/exchange",
                ExchangeBody(publicToken: token, institution: "First Platypus Bank", accountId: nil))
            accountId = ex.accountId
            status = "Syncing 14 months of transactions"
            let _: SyncResult = try await API.post("/api/accounts/\(ex.accountId)/sync?months=14")
            status = "Finding your paychecks, rent and recurring bills"
            async let p: Profile = API.get("/api/accounts/\(ex.accountId)/profile")
            async let t: TxnList = API.get("/api/accounts/\(ex.accountId)/transactions?limit=1000")
            async let r: RiskList = API.get("/api/risks")
            let (prof, txs, rl) = try await (p, t, r)
            profile = prof; transactions = txs.transactions; risks = rl.risks
            cash = prof.baseline.liquidBalance.rounded()
            drafts = ["transmission", "jobloss"].compactMap { id in
                EventTemplate.all.first { $0.id == id }.map { EventDraft(template: $0, startMonth: $0.startMonth) }
            }
            connected = true
        } catch { self.error = error.localizedDescription }
    }

    func disconnect() {
        connected = false; profile = nil; accountId = nil; baselineSim = nil; scenarioSim = nil
        steps = []; stress = []; showResults = false
    }

    // MARK: statements + holdings

    func importStatement(_ url: URL, replace: Bool) async {
        guard let id = accountId else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let r: ImportResult = try await API.upload("/api/accounts/\(id)/import", fileURL: url,
                                                       fields: ["replace": replace ? "true" : "false"])
            importNote = "\(r.inserted) new transactions (\(r.firstDate) to \(r.lastDate)), \(r.skippedDuplicates) duplicates skipped, \(r.transfersExcluded) transfers ignored"
                + (r.warning.map { ". \($0)" } ?? "")
        } catch { self.error = error.localizedDescription }
    }

    func reloadProfile() async {
        guard let id = accountId else { return }
        do {
            async let p: Profile = API.get("/api/accounts/\(id)/profile")
            async let t: TxnList = API.get("/api/accounts/\(id)/transactions?limit=1000")
            let (prof, txs) = try await (p, t)
            profile = prof; transactions = txs.transactions
            cash = prof.baseline.liquidBalance.rounded()
        } catch { self.error = error.localizedDescription }
    }

    func applyHoldingsToCash() {
        cash = ((profile?.accounts.checking ?? 0) + holdings.savingsBalance).rounded()
    }
    // MARK: events

    /// Rent = the largest monthly Housing bill we detected.
    var rent: Double? {
        profile?.recurring
            .filter { !$0.isIncome && $0.category == "Housing" && $0.cadence == "monthly" && abs($0.avgAmount) >= 400 }
            .map { abs($0.avgAmount) }.max()
    }

    var riskCategories: [String] { Array(Set(risks.map { $0.category })).sorted() }

    func addDraft(_ t: EventTemplate) {
        var d = EventDraft(template: t, startMonth: min(t.startMonth, max(0, horizon - 1)))
        if t.id == "caraccident" { d.values["amount"] = holdings.autoDeductible }
        if t.id == "homeclaim" { d.values["amount"] = holdings.homeDeductible }
        drafts.append(d)
    }

    private func pmt(_ principal: Double, aprPct: Double, months: Int) -> Double {
        guard months > 0, principal > 0 else { return 0 }
        let r = aprPct / 1200
        return r == 0 ? principal / Double(months) : principal * r / (1 - pow(1 + r, -Double(months)))
    }

    func toAPI(_ d: EventDraft) -> (life: LifeEvent?, forced: ForcedEvent?) {
        let b = profile?.baseline
        func v(_ k: String) -> Double { d.values[k] ?? d.template.params.first { $0.key == k }?.value ?? 0 }
        let label = d.template.label, month = d.startMonth
        switch d.template.kind {
        case .baby:
            return (LifeEvent(label: label, month: month, expenseDelta: v("monthly"), oneTimeCost: v("upfront")), nil)
        case .car:
            let loan = max(0, v("price") - v("down"))
            let pay = pmt(loan, aprPct: v("apr"), months: Int(v("term")))
            return (LifeEvent(label: label, month: month, durationMonths: Int(v("term")),
                              expenseDelta: pay + v("insurance"), oneTimeCost: v("down")), nil)
        case .home:
            let price = v("price")
            let mortgage = pmt(price * (1 - v("downPct") / 100), aprPct: v("apr"), months: Int(v("years")) * 12)
            let upkeep = price * v("upkeepPct") / 100 / 12
            return (LifeEvent(label: label, month: month, expenseDelta: mortgage + upkeep - (rent ?? 0),
                              oneTimeCost: price * (v("downPct") + v("closingPct")) / 100), nil)
        case .raise:
            return (LifeEvent(label: label, month: month, incomeDelta: (b?.monthlyIncome ?? 0) * v("pct") / 100), nil)
        case .rentUp:
            let base = rent ?? (b?.monthlyFixed ?? 0) * 0.5
            return (LifeEvent(label: label, month: month, expenseDelta: base * v("pct") / 100), nil)
        case .jobLoss:
            return (nil, ForcedEvent(key: "layoff", month: month, durationMonths: Int(v("months")), incomeLossFraction: v("lost") / 100))
        case .bill:
            return (nil, ForcedEvent(key: "emergency_bill", month: month, durationMonths: 1, grossCost: v("amount"), coverage: v("coverage") / 100))
        case .custom:
            let months = Int(v("months"))
            return (LifeEvent(label: label, month: month, durationMonths: months > 0 ? months : nil,
                              expenseDelta: v("monthly"), oneTimeCost: v("oneTime")), nil)
        }
    }

    /// One plain-English line showing what the numbers resolve to for this person.
    func describe(_ d: EventDraft) -> String {
        let r = toAPI(d)
        if let l = r.life {
            var parts: [String] = []
            let net = l.incomeDelta - l.expenseDelta
            if abs(net) >= 1 {
                parts.append("\(net >= 0 ? "+" : "-")\(abs(net).usd) a month" + (l.durationMonths.map { " for \($0) months" } ?? ""))
            }
            if l.oneTimeCost > 0 { parts.append("\(l.oneTimeCost.usd) up front") }
            return parts.joined(separator: ", ")
        }
        if let f = r.forced {
            if f.key == "layoff" {
                let loss = (profile?.baseline.monthlyIncome ?? 0) * f.incomeLossFraction
                return "You lose \(loss.usd) a month for \(f.durationMonths) months"
            }
            return "\((f.grossCost * (1 - f.coverage)).usd) out of pocket"
        }
        return ""
    }

    // MARK: simulate (Layer 2)

    func request(life: [LifeEvent], forced: [ForcedEvent], paths: Int = 3000) -> SimRequest {
        SimRequest(accountId: accountId ?? "", horizonMonths: horizon, nPaths: paths, seed: 42, startingBalance: cash,
                   riskKeys: randomRisks ? nil : [], excludeRiskKeys: Array(excluded),
                   lifeEvents: life, forcedEvents: forced, ruinFloor: 0, profile: user)
    }

    func runFutures() async {
        guard profile != nil, accountId != nil else { return }
        running = true; error = nil
        defer { running = false }
        let built = drafts.map { toAPI($0) }
        let life = built.compactMap { $0.life }
        let forced = built.compactMap { $0.forced }
        let baseReq = request(life: [], forced: [])
        let scenReq = request(life: life, forced: forced)
        do {
            async let a: SimResult = API.post("/api/simulate", baseReq)
            async let s: SimResult = API.post("/api/simulate", scenReq)
            let (bs, ss) = try await (a, s)
            baselineSim = bs; scenarioSim = ss; steps = []
            showResults = true
            await buildRescue(scenario: scenReq, scenarioRuin: ss.summary.probabilityOfRuin, baselineRuin: bs.summary.probabilityOfRuin)
        } catch { self.error = error.localizedDescription }
    }

    // MARK: rescue plan (every number below is re-simulated by the backend)

    private func evaluate(_ cand: [RescueStep], base: SimRequest) async -> [SimResult?] {
        await withTaskGroup(of: (Int, SimResult?).self) { group in
            for i in cand.indices {
                var req = base
                req.lifeEvents = base.lifeEvents + cand[0...i].map { $0.event }
                let r = req
                group.addTask {
                    let res = try? await API.post("/api/simulate", r) as SimResult
                    return (i, res)
                }
            }
            var out = [SimResult?](repeating: nil, count: cand.count)
            for await (i, res) in group { out[i] = res }
            return out
        }
    }

    func buildRescue(scenario: SimRequest, scenarioRuin: Double, baselineRuin: Double) async {
        guard let p = profile else { return }
        rescuing = true
        defer { rescuing = false }
        let target = max(0.05, baselineRuin + 0.02)
        rescueTarget = target
        cushion = []; cushionNeeded = nil
        if scenarioRuin <= target { steps = []; rescueAchieved = true; return }

        var cand: [RescueStep] = []
        let gainPct = max(0, 4.5 - holdings.savingsApy)
        let interest = max(0, cash) * gainPct / 1200
        if interest >= 1 {
            cand.append(RescueStep(group: "hysa", title: "Move cash to a 4.5% APY savings account",
                                   detail: "Your \(cash.usd) earns \(String(format: "%.1f", holdings.savingsApy))% today", monthly: interest, pain: "Easy",
                                   event: LifeEvent(label: "High-yield savings", incomeDelta: interest)))
        }
        let cuttable = ["Subscriptions", "Entertainment", "Health"]
        let subs = p.recurring.filter { !$0.isIncome && !$0.essential && $0.confidence >= 0.7 && $0.cadence == "monthly"
                                        && cuttable.contains($0.category) && abs($0.avgAmount) <= 150 }
            .sorted { abs($0.avgAmount) > abs($1.avgAmount) }
        for s in subs {
            let amt = abs(s.avgAmount)
            cand.append(RescueStep(group: "sub", title: "Cancel \(s.label)", detail: "Detected \(cadenceText(s.cadence)), \(amt.usd) each time",
                                   monthly: amt, pain: "Easy", event: LifeEvent(label: "Cancel \(s.label)", expenseDelta: -amt)))
        }
        let var10 = p.baseline.monthlyVariableMean * 0.10
        for n in 1...3 {
            cand.append(RescueStep(group: "trim", title: "Trim everyday spending by \(n * 10)%",
                                   detail: "About \((var10 * Double(n)).usd) less a month than your \(p.baseline.monthlyVariableMean.usd) average",
                                   monthly: var10 * Double(n), pain: n == 3 ? "Hard" : "Medium",
                                   event: LifeEvent(label: "Trim spending", expenseDelta: -var10 * Double(n))))

        }
        if holdings.depositAmount > 0 {
            let net = holdings.depositNet
            cand.append(RescueStep(group: "cd", title: "Break your deposit early",
                                   detail: "Frees \(net.usd) after an estimated \(holdings.depositPenalty.usd) penalty",
                                   monthly: net, pain: "Medium",
                                   event: LifeEvent(label: "Break deposit", month: 0, durationMonths: 1, incomeDelta: net)))
        }
        let pay = 110.0
        for n in 1...8 {
            cand.append(RescueStep(group: "gig", title: "Pick up \(n) gig shift\(n == 1 ? "" : "s") in the next 90 days",
                                   detail: "About \(pay.usd) per shift (assumption)", monthly: pay * Double(n) / 3, pain: "Hard",
                                   event: LifeEvent(label: "Gig shift", month: 0, durationMonths: 3, incomeDelta: pay * Double(n) / 3)))
        }

        let results = await evaluate(cand, base: scenario)
        for i in cand.indices {
            cand[i].ruinAfter = results[i]?.summary.probabilityOfRuin ?? 1
            cand[i].result = results[i]
        }
        let chosen: [RescueStep]
        if let k = cand.firstIndex(where: { $0.ruinAfter <= target }) { chosen = Array(cand[0...k]); rescueAchieved = true }
        else { chosen = cand; rescueAchieved = false }

        var merged: [RescueStep] = []
        for s in chosen {
            if let last = merged.last, last.group == s.group, s.group == "trim" || s.group == "gig" { merged[merged.count - 1] = s }
            else { merged.append(s) }
        }
        steps = merged
        await computeCushion(scenario: scenario, target: target)
    }

    /// Same idea as the backend's emergency-fund chart: sweep the starting cash and find where risk meets the target.
    private func computeCushion(scenario: SimRequest, target: Double) async {
        let base = max(cash, 1000)
        let grid = [1.0, 1.5, 2, 3, 4, 6, 8, 12, 16, 24].map { base * $0 }
        let pts: [CushionPoint] = await withTaskGroup(of: CushionPoint?.self) { group in
            for b in grid {
                var req = scenario
                req.startingBalance = b
                let r = req
                group.addTask {
                    guard let res = try? await API.post("/api/simulate", r) as SimResult else { return nil }
                    return CushionPoint(balance: b, ruin: res.summary.probabilityOfRuin)
                }
            }
            var out: [CushionPoint] = []
            for await p in group { if let p { out.append(p) } }
            return out.sorted { $0.balance < $1.balance }
        }
        cushion = pts
        guard let i = pts.firstIndex(where: { $0.ruin <= target }) else { cushionNeeded = nil; return }
        if i == 0 { cushionNeeded = pts[0].balance; return }
        let a = pts[i - 1], b = pts[i]
        let t = (a.ruin - target) / max(a.ruin - b.ruin, 1e-9)
        cushionNeeded = ((a.balance + t * (b.balance - a.balance)) / 500).rounded(.up) * 500
    }

    // MARK: stress tests

    func runStress(months: Int) async {
        guard let id = accountId else { return }
        stressBusy = true
        defer { stressBusy = false }
        do {
            let r: StressResult = try await API.post("/api/stress-test",
                StressRequest(accountId: id, scenarioKeys: nil, startingBalance: cash, horizonMonths: months))
            stress = r.scenarios
        } catch { self.error = error.localizedDescription }
    }
}
