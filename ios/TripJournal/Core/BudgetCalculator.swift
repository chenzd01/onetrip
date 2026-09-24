import Foundation

struct BudgetLine: Identifiable {
    var id: String
    var title: String
    var amount: Double
    var currency: String
    // rate is home currency per one unit of local currency.
    func converted(to target: String, rate: Double) -> Double {
        currency == target ? amount : currency == TripConfig.current.currency.local ? amount * rate : amount / rate
    }
}
enum BudgetCalculator {
    static func lines(budget b: Budget) -> [BudgetLine] {
        let c = TripConfig.current.currency
        return [
            .init(id: "flightOut", title: "去程机票", amount: b.flightOut, currency: c.home),
            .init(id: "flightReturn", title: "回程机票", amount: b.flightReturn, currency: c.home),
            .init(id: "hotel", title: "住宿", amount: b.hotel, currency: c.local),
            .init(id: "food", title: "餐饮", amount: b.food, currency: c.local),
            .init(id: "transport", title: "当地交通", amount: b.transport, currency: c.local),
            .init(id: "other", title: "其他费用", amount: b.other, currency: c.local)
        ]
    }
}

struct BudgetDraft {
    private(set) var budget: Budget
    private(set) var currency: String
    private(set) var texts: [String: String] = [:]
    private var originals: [String: String] = [:]
    let rate: Double

    init(budget: Budget, currency: String, rate: Double) {
        self.budget = budget; self.currency = currency; self.rate = rate
        refreshTexts()
    }
    mutating func setText(_ text: String, for id: String) { texts[id] = text }
    mutating func changeCurrency(to currency: String) throws {
        guard self.currency != currency else { return }
        budget = try resolvedBudget()
        self.currency = currency
        refreshTexts()
    }
    func resolvedBudget() throws -> Budget {
        guard rate.isFinite, rate > 0 else { throw TripError.message("汇率暂不可用，请稍后重试。") }
        var next = budget
        for line in BudgetCalculator.lines(budget: budget) where texts[line.id] != originals[line.id] {
            let text = (texts[line.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
            guard let amount = Double(text.isEmpty ? "0" : text), amount.isFinite, amount >= 0 else {
                throw TripError.message("请检查\(line.title)：请输入不小于 0 的金额。")
            }
            let stored = BudgetLine(id: line.id, title: line.title, amount: amount, currency: currency).converted(to: line.currency, rate: rate)
            guard stored.isFinite, (0...PlanValidation.maximumBudget).contains(stored) else { throw TripError.message("\(line.title)金额超出可保存范围。") }
            switch line.id {
            case "flightOut": next.flightOut = stored
            case "flightReturn": next.flightReturn = stored
            case "hotel": next.hotel = stored
            case "food": next.food = stored
            case "transport": next.transport = stored
            case "other": next.other = stored
            default: break
            }
        }
        return next
    }
    private mutating func refreshTexts() {
        texts = Dictionary(uniqueKeysWithValues: BudgetCalculator.lines(budget: budget).map {
            ($0.id, $0.converted(to: currency, rate: rate).formatted(.number.grouping(.never).precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US_POSIX"))))
        })
        originals = texts
    }
}
