import SwiftUI
import Foundation
import UIKit

enum Theme {
    static let bg     = Color(red: 0.96, green: 0.95, blue: 1.00)
    static let ink    = Color(red: 0.10, green: 0.10, blue: 0.23)
    static let violet = Color(red: 0.42, green: 0.36, blue: 0.91)
    static let coral  = Color(red: 1.00, green: 0.36, blue: 0.48)
    static let mint   = Color(red: 0.36, green: 0.86, blue: 0.68)
    static let sun    = Color(red: 1.00, green: 0.84, blue: 0.29)
}

func rounded(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font { .system(size: size, weight: weight, design: .rounded) }
func pct(_ x: Double) -> String {
    let v = x * 100
    return v > 0 && v < 1 ? "<1%" : "\(Int(v.rounded()))%"
}
func odds(_ p: Double) -> String {
    if p < 0.01 { return "Less than 1 in 100" }
    if p >= 0.95 { return "Almost certain" }
    if p >= 0.15 { return "\(Int((p * 10).rounded())) in 10" }   // 0.7 -> "7 in 10"
    return "1 in \(Int((1.0 / p).rounded()))"
}
/// One plain sentence for the big headline.
func riskHeadline(_ p: Double) -> String {
    if p < 0.01 { return "You are very unlikely to run out of cash." }
    if p >= 0.95 { return "You will almost certainly run out of cash." }
    return "There is a \(odds(p)) chance you run out of cash."
}
func compactUsd(_ d: Double) -> String {
    let a = abs(d), s = d < 0 ? "-" : ""
    if a >= 1_000_000 { return "\(s)$\(String(format: "%.1f", a / 1_000_000))M" }
    if a >= 1_000 { return "\(s)$\(Int((a / 1_000).rounded()))k" }
    return "\(s)$\(Int(a.rounded()))"
}
extension Double {
    var usd: String { formatted(.currency(code: "USD").precision(.fractionLength(0))) }
    var signedUsd: String { (self >= 0 ? "+" : "-") + abs(self).usd }
}
extension View { func screen() -> some View { foregroundStyle(Theme.ink).background(Theme.bg.ignoresSafeArea()) } }

private let isoFmt: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
}()
func isoDate(_ s: String) -> Date? { isoFmt.date(from: s) }
func prettyDate(_ s: String) -> String {
    guard let d = isoFmt.date(from: s) else { return s }
    return d.formatted(.dateTime.month(.abbreviated).day())
}
func cadenceText(_ c: String) -> String {
    ["weekly": "every week", "biweekly": "every 2 weeks", "semimonthly": "twice a month", "monthly": "every month",
     "quarterly": "every 3 months", "semiannual": "twice a year", "annual": "once a year"][c] ?? c
}
func horizonText(_ months: Int) -> String {
    if months == 12 { return "a year" }
    if months < 24 { return "\(months) months" }
    return months % 12 == 0 ? "\(months / 12) years" : "\(months) months"
}

/// White card with an ink outline and a hard offset shadow.
struct Card<Content: View>: View {
    let fill: Color
    let content: Content
    init(fill: Color = .white, @ViewBuilder content: () -> Content) { self.fill = fill; self.content = content() }
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(fill))
            .overlay(shape.stroke(Theme.ink, lineWidth: 2))
            .background(shape.fill(Theme.ink).offset(x: 4, y: 5))
            .padding(.trailing, 4).padding(.bottom, 5)
    }
}

struct StickerLabel: View {
    let text: String
    var color: Color = Theme.violet
    var fg: Color = .white
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Text(text).font(.system(.headline, design: .rounded, weight: .bold)).foregroundStyle(fg)
            .padding(.vertical, 16).frame(maxWidth: .infinity)
            .background(shape.fill(color)).overlay(shape.stroke(Theme.ink, lineWidth: 2))
            .background(shape.fill(Theme.ink).offset(y: 5)).padding(.bottom, 5)
    }
}

struct StickerButton: ButtonStyle {
    var color: Color = Theme.violet
    var text: Color = .white
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .bold)).foregroundStyle(text)
            .multilineTextAlignment(.center)
            .padding(.vertical, 16).frame(maxWidth: .infinity)
            .background(shape.fill(color)).overlay(shape.stroke(Theme.ink, lineWidth: 2))
            .background(shape.fill(Theme.ink).offset(y: configuration.isPressed ? 1 : 5))
            .offset(y: configuration.isPressed ? 4 : 0).padding(.bottom, 5)
    }
}

struct Pill: View {
    let text: String
    var fill: Color = Theme.sun
    var body: some View {
        Text(text).font(rounded(12, .bold)).padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(fill)).overlay(Capsule().stroke(Theme.ink, lineWidth: 1.5))
    }
}

struct ScreenTitle: View {
    let title: String
    var sub: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(rounded(32))
            if let sub { Text(sub).font(.subheadline) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var tint: Color = Theme.ink
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold))
            Text(value).font(rounded(24)).foregroundStyle(tint)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SplitBar: View {
    let parts: [(Color, Double)]
    var body: some View {
        GeometryReader { g in
            HStack(spacing: 0) {
                ForEach(parts.indices, id: \.self) { i in
                    Rectangle().fill(parts[i].0).frame(width: g.size.width * max(0, parts[i].1))
                }
            }
        }.frame(height: 22).clipShape(Capsule()).overlay(Capsule().stroke(Theme.ink, lineWidth: 2))
    }
}

// MARK: - Editable values (one look everywhere)


struct InputBox: ViewModifier {
    var focused = false
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(shape.fill(Theme.bg))
            .overlay(shape.stroke(focused ? Theme.violet : Theme.ink, lineWidth: focused ? 2.5 : 1.5))
    }
}
extension View {
    func inputBox(focused: Bool = false) -> some View { modifier(InputBox(focused: focused)) }

    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }.fontWeight(.bold)
            }
        }
    }
}

struct NumberInput: View {
    @Binding var value: Double
    var prefix = ""
    var suffix = ""
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 4) {
            if !prefix.isEmpty { Text(prefix).foregroundStyle(Theme.ink.opacity(0.6)) }
            TextField("0", value: $value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .font(rounded(17, .bold))
                .frame(width: 84)
            if !suffix.isEmpty { Text(suffix).foregroundStyle(Theme.ink.opacity(0.6)) }
            Image(systemName: "pencil").font(.caption.weight(.bold)).foregroundStyle(Theme.violet)
        }
        .inputBox(focused: focused)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}

/// Tinted note inside a card. Same outline as the input boxes.
struct Callout<Content: View>: View {
    var tint: Color = Theme.coral
    let content: Content
    init(tint: Color = Theme.coral, @ViewBuilder content: () -> Content) { self.tint = tint; self.content = content() }
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        content.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(tint.opacity(0.25)))
            .overlay(shape.stroke(Theme.ink, lineWidth: 1.5))
    }
}
