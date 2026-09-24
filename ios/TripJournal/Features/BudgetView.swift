import SwiftUI

struct BudgetView: View {
    @Environment(TripStore.self) private var store
    @AppStorage("budget-currency") private var storedCurrency = TripConfig.current.currency.home
    @State private var draft: BudgetDraft?
    @State private var inputError: String?
    @FocusState private var focusedField: String?
    private var money: TripConfig.Currency { store.content.trip.currency }
    private var currency: String { [money.local, money.home].contains(storedCurrency) ? storedCurrency : money.home }
    private var rate: Double { money.homePerLocal }
    private var previewBudget: Budget { (try? draft?.resolvedBudget()) ?? draft?.budget ?? store.plan.budget }
    private var lines: [BudgetLine] { BudgetCalculator.lines(budget: previewBudget) }
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("\(store.content.trip.partySize) 人的旅行预算").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            if draft == nil { startEditing() } else { save() }
                        } label: {
                            Label(draft == nil ? "编辑" : "保存并锁定", systemImage: draft == nil ? "lock.fill" : "lock.open")
                                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        }.buttonStyle(.borderless)
                        .accessibilityIdentifier("budget-edit-lock")
                    }
                    Text(lines.reduce(0) { $0 + $1.converted(to: currency, rate: rate) }, format: .currency(code: currency).precision(.fractionLength(2)))
                        .font(.system(.largeTitle, design: .rounded, weight: .medium)).foregroundStyle(TripStyle.green)
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text(draft == nil ? "已锁定 · 所有金额均为全程合计" : "编辑中 · 直接填写全程合计")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(.vertical, 8).listRowSeparator(.hidden)
                Picker("货币", selection: Binding(get: { currency }, set: { changeCurrency($0) })) {
                    Text(money.homeSymbol + " " + money.home).tag(money.home)
                    if money.local != money.home { Text(money.localSymbol + " " + money.local).tag(money.local) }
                }.pickerStyle(.segmented)
                ForEach(lines) { line in
                    HStack {
                        Text(line.title)
                        Spacer(minLength: 16)
                        if draft != nil {
                            Text(currency == money.home ? money.homeSymbol : money.localSymbol).foregroundStyle(.secondary)
                            TextField("0", text: Binding(get: { draft?.texts[line.id] ?? "" }, set: { draft?.setText($0, for: line.id); inputError = nil }))
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                .frame(minWidth: 90, maxWidth: 150, minHeight: 44)
                                .focused($focusedField, equals: line.id)
                                .accessibilityLabel(line.title + "，全程合计，" + currency)
                                .accessibilityIdentifier("budget-" + line.id)
                        } else {
                            Text(line.converted(to: currency, rate: rate), format: .currency(code: currency).precision(.fractionLength(2)))
                                .monospacedDigit().frame(minHeight: 44)
                        }
                    }.font(.body).listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                if let error = inputError ?? draftError {
                    Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.red)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("其他费用可填写门票、保险、通信、购物等全部额外开销。")
                    Text("参考汇率：1 \(money.local) = \(rate, specifier: "%.6f") \(money.home) · \(money.rateDate)")
                }.font(.footnote).foregroundStyle(.secondary)
                if draft != nil {
                    Button("取消编辑", role: .cancel) { stopEditing() }.buttonStyle(.borderless)
                }
            }
        }.scrollContentBackground(.hidden).background(TripStyle.paper)
        .navigationTitle("旅行预算").navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(draft != nil)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("收起键盘") { focusedField = nil }
            }
        }
        .onDisappear { if draft != nil { stopEditing() } }
    }
    private var draftError: String? {
        do { _ = try draft?.resolvedBudget(); return nil }
        catch { return error.localizedDescription }
    }
    private func startEditing() {
        guard !store.hasConflicts else { inputError = "请先处理同步冲突，再编辑预算。"; return }
        draft = BudgetDraft(budget: store.plan.budget, currency: currency, rate: rate)
        inputError = nil
        store.editingForms += 1
    }
    private func changeCurrency(_ value: String) {
        do {
            try draft?.changeCurrency(to: value)
            storedCurrency = value; inputError = nil; focusedField = nil
        } catch { inputError = error.localizedDescription }
    }
    private func save() {
        do {
            guard let budget = try draft?.resolvedBudget() else { return }
            if store.edit({ $0.budget = budget }) { stopEditing(); Task { await store.synchronize() } }
        } catch { inputError = error.localizedDescription }
    }
    private func stopEditing() {
        focusedField = nil; draft = nil; inputError = nil
        store.editingForms -= 1
    }
}
