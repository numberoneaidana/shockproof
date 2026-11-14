import Foundation

// MARK: - Client (talks to the FastAPI backend: shockwaveAPI)

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum API {
    static var base: String {
        get { UserDefaults.standard.string(forKey: "apiBase") ?? "http://127.0.0.1:8000" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "apiBase") }
    }

    private struct Detail: Decodable { let detail: String }

    private static func makeRequest(_ path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: base + path) else {
            throw APIError(message: "Invalid URL: \(base + path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    static func get<T: Decodable>(_ path: String) async throws -> T {
        try await run(makeRequest(path, method: "GET"))
    }

    static func post<T: Decodable>(_ path: String) async throws -> T {
        try await run(makeRequest(path, method: "POST"))
    }

    static func post<T: Decodable, Body: Encodable>(_ path: String, _ body: Body) async throws -> T {
        var req = try makeRequest(path, method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase // ✅ ADDED THIS
        req.httpBody = try encoder.encode(body)
        
        return try await run(req)
    }
    static func upload<T: Decodable>(_ path: String, fileURL: URL, fields: [String: String] = [:]) async throws -> T {
        var req = try makeRequest(path, method: "POST")
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        let fileData: Data
        do { fileData = try Data(contentsOf: fileURL) }
        catch { throw APIError(message: "Couldn't read the file: \(error.localizedDescription)") }

        var body = Data()
        func add(_ s: String) { body.append(Data(s.utf8)) }
        for (k, v) in fields {
            add("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n")
        }
        let mime: String
        switch fileURL.pathExtension.lowercased() {
        case "pdf": mime = "application/pdf"
        case "csv", "txt": mime = "text/csv"
        default: mime = "application/octet-stream"
        }
        add("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\nContent-Type: \(mime)\r\n\r\n")
        body.append(fileData)
        add("\r\n--\(boundary)--\r\n")
        req.httpBody = body
        return try await run(req)
    }

    private static func run<T: Decodable>(_ req: URLRequest) async throws -> T {
        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError(message: error.localizedDescription)
        }

        guard let http = result.1 as? HTTPURLResponse else {
            throw APIError(message: "Invalid response")
        }

        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(Detail.self, from: result.0))?.detail
                    ?? "HTTP \(http.statusCode)"
            throw APIError(message: msg)
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase // ✅ ADDED THIS
            return try decoder.decode(T.self, from: result.0)
        } catch {
            throw APIError(message: "Failed to decode response: \(error.localizedDescription)")
        }
    }
}
// MARK: - Responses

struct Health: Decodable { let ok: Bool; let plaidLive: Bool }
struct LinkToken: Decodable { let linkToken: String?; let mock: Bool? }
struct ExchangeResult: Decodable { let accountId: String; let itemId: String; let mock: Bool }
struct SyncResult: Decodable { let accountId: String; let fetched: Int; let inserted: Int }

struct Baseline: Decodable {
    let monthlyIncome, monthlyFixed, monthlyVariableMean, monthlyVariableStd: Double
    let monthlyNetMean, monthlyNetStd, essentialMonthly, liquidBalance: Double
    let emergencyRunwayMonths, savingsRate, monthlyIncomeVolatility: Double
}

struct Recurring: Decodable, Identifiable {
    let merchant, label, category, cadence: String
    let avgAmount, amountCv: Double
    let occurrences: Int
    let monthlyEquivalent: Double
    let lastDate, nextExpected: String
    let confidence: Double
    let isIncome, essential: Bool
    var id: String { merchant }
}

struct OverdraftForecast: Decodable {
    let startDate: String
    let days: Int
    let dates: [String]
    let balance: [Double]
    let minBalance: Double
    let minBalanceDate: String
    let overdraftRisk: Bool
    let firstOverdraftDate: String?
}

struct AccountBalances: Decodable {
    let checking: Double
    let savings: Double
    let creditCardDebt: Double
    let creditCardLimit: Double
    
    // Available cash is checking + savings (if savings is liquid)
    var availableCash: Double {
        checking + savings
    }
    
    // Credit utilization is the percentage of limit used (e.g., 0.30 = 30%)
    // We protect against dividing by zero if the user has no credit card limit
    var creditUtilization: Double {
        guard creditCardLimit > 0 else { return 0 }
        return creditCardDebt / creditCardLimit
    }
    
    // A safe default in case the backend hasn't sent these fields yet
    init() {
        checking = 0
        savings = 0
        creditCardDebt = 0
        creditCardLimit = 0
    }

    enum CodingKeys: String, CodingKey {
        case checking, savings, creditCardDebt, creditCardLimit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Using try? and ?? 0 prevents the "data is missing" crash if Python skips a field
        checking = (try? c.decode(Double.self, forKey: .checking)) ?? 0
        savings = (try? c.decode(Double.self, forKey: .savings)) ?? 0
        creditCardDebt = (try? c.decode(Double.self, forKey: .creditCardDebt)) ?? 0
        creditCardLimit = (try? c.decode(Double.self, forKey: .creditCardLimit)) ?? 0
    }
}

struct Profile: Decodable {
    let baseline: Baseline
    let recurring: [Recurring]
    let overdraftForecast: OverdraftForecast
    let accounts: AccountBalances // ✅ Added this

    // Safely decode the profile
    enum CodingKeys: String, CodingKey {
        case baseline, recurring, overdraftForecast, accounts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseline = try c.decode(Baseline.self, forKey: .baseline)
        recurring = (try? c.decode([Recurring].self, forKey: .recurring)) ?? []
        overdraftForecast = try c.decode(OverdraftForecast.self, forKey: .overdraftForecast)
        // Default to 0s if the backend hasn't added this yet
        accounts = (try? c.decode(AccountBalances.self, forKey: .accounts)) ?? AccountBalances()
    }
}
struct BankTxn: Decodable, Identifiable {
    let txnId, accountId, date: String
    let amount: Double                 // + inflow, - outflow
    let merchantRaw, merchant, category, subcategory: String
    let isEssential, pending: Bool
    var id: String { txnId }
}
struct TxnList: Decodable { let count: Int; let transactions: [BankTxn] }

struct Risk: Decodable, Identifiable {
    let key, label, category: String
    let annualProbability, medianCost, p90Cost, coverage, durationMonthsMean, incomeLossFraction: Double
    let correlationGroup: String
    let essential: Bool
    var id: String { key }
}
struct RiskList: Decodable { let count: Int; let categories: [String]; let risks: [Risk] }

struct SimSummary: Decodable {
    let nPaths, horizonMonths: Int
    let startingBalance, ruinFloor, probabilityOfRuin: Double
    let medianEndBalance, p5EndBalance, p95EndBalance, expectedShortfall5pct: Double
    let medianMinBalance, p5MinBalance: Double
    let medianMonthsToRuin: Int?
    let expectedTotalShockCost, monthlyNetMean, monthlyNetStd: Double

    // Default initializer in case the entire summary is missing
    init() {
        nPaths = 0; horizonMonths = 0
        startingBalance = 0; ruinFloor = 0; probabilityOfRuin = 0
        medianEndBalance = 0; p5EndBalance = 0; p95EndBalance = 0; expectedShortfall5pct = 0
        medianMinBalance = 0; p5MinBalance = 0
        medianMonthsToRuin = nil
        expectedTotalShockCost = 0; monthlyNetMean = 0; monthlyNetStd = 0
    }

    enum CodingKeys: String, CodingKey {
        case nPaths, horizonMonths, startingBalance, ruinFloor, probabilityOfRuin
        case medianEndBalance, p5EndBalance, p95EndBalance, expectedShortfall5pct
        case medianMinBalance, p5MinBalance, medianMonthsToRuin
        case expectedTotalShockCost, monthlyNetMean, monthlyNetStd
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nPaths = (try? c.decode(Int.self, forKey: .nPaths)) ?? 0
        horizonMonths = (try? c.decode(Int.self, forKey: .horizonMonths)) ?? 0
        startingBalance = (try? c.decode(Double.self, forKey: .startingBalance)) ?? 0
        ruinFloor = (try? c.decode(Double.self, forKey: .ruinFloor)) ?? 0
        probabilityOfRuin = (try? c.decode(Double.self, forKey: .probabilityOfRuin)) ?? 0
        medianEndBalance = (try? c.decode(Double.self, forKey: .medianEndBalance)) ?? 0
        p5EndBalance = (try? c.decode(Double.self, forKey: .p5EndBalance)) ?? 0
        p95EndBalance = (try? c.decode(Double.self, forKey: .p95EndBalance)) ?? 0
        expectedShortfall5pct = (try? c.decode(Double.self, forKey: .expectedShortfall5pct)) ?? 0
        medianMinBalance = (try? c.decode(Double.self, forKey: .medianMinBalance)) ?? 0
        p5MinBalance = (try? c.decode(Double.self, forKey: .p5MinBalance)) ?? 0
        medianMonthsToRuin = try? c.decodeIfPresent(Int.self, forKey: .medianMonthsToRuin)
        expectedTotalShockCost = (try? c.decode(Double.self, forKey: .expectedTotalShockCost)) ?? 0
        monthlyNetMean = (try? c.decode(Double.self, forKey: .monthlyNetMean)) ?? 0
        monthlyNetStd = (try? c.decode(Double.self, forKey: .monthlyNetStd)) ?? 0
    }
}

struct FanChart: Decodable {
    let months: [Int]
    let p5, p25, p50, p75, p95: [Double]

    init() {
        months = []; p5 = []; p25 = []; p50 = []; p75 = []; p95 = []
    }

    enum CodingKeys: String, CodingKey {
        case months, p5, p25, p50, p75, p95
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        months = (try? c.decode([Int].self, forKey: .months)) ?? []
        p5 = (try? c.decode([Double].self, forKey: .p5)) ?? []
        p25 = (try? c.decode([Double].self, forKey: .p25)) ?? []
        p50 = (try? c.decode([Double].self, forKey: .p50)) ?? []
        p75 = (try? c.decode([Double].self, forKey: .p75)) ?? []
        p95 = (try? c.decode([Double].self, forKey: .p95)) ?? []
    }
}

struct Attribution: Decodable, Identifiable {
    let key, label, category: String
    let annualProbability, pOccursInHorizon, meanNetCost: Double
    let conditionalRuinRate: Double
    let deltaRuin: Double?
    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, label, category, annualProbability, pOccursInHorizon, meanNetCost, conditionalRuinRate, deltaRuin
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? c.decode(String.self, forKey: .key)) ?? UUID().uuidString
        label = (try? c.decode(String.self, forKey: .label)) ?? "Unknown"
        category = (try? c.decode(String.self, forKey: .category)) ?? ""
        annualProbability = (try? c.decode(Double.self, forKey: .annualProbability)) ?? 0
        pOccursInHorizon = (try? c.decode(Double.self, forKey: .pOccursInHorizon)) ?? 0
        meanNetCost = (try? c.decode(Double.self, forKey: .meanNetCost)) ?? 0
        conditionalRuinRate = (try? c.decode(Double.self, forKey: .conditionalRuinRate)) ?? 0
        deltaRuin = try? c.decodeIfPresent(Double.self, forKey: .deltaRuin)
    }
}

struct SimResult: Decodable {
    let summary: SimSummary
    let fanChart: FanChart
    let riskAttribution: [Attribution]
    let topDrivers: [Attribution]

    enum CodingKeys: String, CodingKey {
        case summary, fanChart, riskAttribution, topDrivers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = (try? c.decode(SimSummary.self, forKey: .summary)) ?? SimSummary()
        fanChart = (try? c.decode(FanChart.self, forKey: .fanChart)) ?? FanChart()
        riskAttribution = (try? c.decode([Attribution].self, forKey: .riskAttribution)) ?? []
        topDrivers = (try? c.decode([Attribution].self, forKey: .topDrivers)) ?? []
    }
}

struct StressScenario: Decodable, Identifiable {
    let key, label: String
    let probabilityOfRuin, medianEndBalance, p5EndBalance, medianMinBalance: Double
    let medianMonthsToRuin: Int?
    var id: String { key }
}
struct StressResult: Decodable { let scenarios: [StressScenario] }

// MARK: - Requests

struct ExchangeBody: Encodable { let publicToken: String; let institution: String; let accountId: String? }

struct LifeEvent: Encodable, Identifiable {
    var id = UUID()
    var label: String
    var month = 0
    var durationMonths: Int? = nil            // nil = permanent
    var incomeDelta = 0.0                     // + more income per month
    var expenseDelta = 0.0                    // + more spending per month
    var oneTimeCost = 0.0
    enum CodingKeys: String, CodingKey { case label, month, durationMonths, incomeDelta, expenseDelta, oneTimeCost }
}

struct ForcedEvent: Encodable {
    var key: String
    var month = 0
    var durationMonths = 1
    var grossCost = 0.0
    var coverage = 0.0                        // 0...1 covered by insurance
    var incomeLossFraction = 0.0              // 0...1 of monthly income lost
}

struct UserProfile: Encodable {
    var age = 30
    var state = "NY"
    var housing = "rent"                      // rent | own_house | own_condo | with_parents
    var employment = "employed"               // employed | self | gig
    var married = false
    var children = 0
    var hasPets = false
    var ownsCar = true
    var canBirth = true
}

struct SimRequest: Encodable {
    var accountId: String
    var horizonMonths: Int
    var nPaths: Int
    var seed: Int?
    var startingBalance: Double?
    var riskKeys: [String]?                   // nil = every risk in the catalog, [] = none
    var excludeRiskKeys: [String]
    var lifeEvents: [LifeEvent]
    var forcedEvents: [ForcedEvent]
    var ruinFloor: Double
    var profile: UserProfile
}

struct StressRequest: Encodable {
    let accountId: String
    let scenarioKeys: [String]?
    let startingBalance: Double?
    let horizonMonths: Int
}
