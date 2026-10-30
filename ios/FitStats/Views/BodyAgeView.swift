import Charts
import SwiftUI

/// The Body age tab: the age whose typical person has their fitness, steps, exercise and sleep,
/// what each adds or takes off, what would change it, and how it moved over the months. The
/// server works it out from published studies (lib/bodyage.ts).
struct BodyAgeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var open: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let b = model.stats?.bodyAge {
                        hero(b)
                        factors(b)
                        if !b.whatIf.isEmpty { whatIf(b) }
                        if b.history.count >= 2 { history(b) }
                        if let vo2 = b.vo2max { fitness(vo2) }
                        if !b.missing.isEmpty { missing(b) }
                        AskCoachRow(prompts: [
                            ("sparkles", "Explain my body age", "About my body age: what drives it, and is it a fair estimate for me?"),
                            ("arrow.down.right", "How can I lower it?", "About my body age: what's the most realistic change to lower it over the next 2 months?"),
                        ])
                        note(b)
                    } else {
                        Card {
                            EmptyStateView(icon: "hourglass", title: "No body age yet",
                                           message: "It needs about two weeks of your band's data and your age from your Google account. It's worked out on the server after a sync (server 1.14.0 or later).")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .refreshable { await model.pullToRefresh() }
            .screenBackground()
            .navigationTitle("Body age")
            .swipeBackFromAnywhere()
            .navigationDestination(for: String.self) { if $0 == "method" { BodyAgeMethodView() } }
        }
    }

    // MARK: sections

    private func hero(_ b: BodyAge) -> some View {
        Card {
            VStack(spacing: 8) {
                Text(Format.number(b.bodyAge, decimals: 1))
                    .font(Theme.number(64))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text("years · you're \(b.age)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                Text(Self.differenceText(b.difference))
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Self.color(b.difference).opacity(0.18)))
                    .foregroundStyle(Self.color(b.difference))
                AgeScale(age: Double(b.age), bodyAge: b.bodyAge)
                    .frame(height: 34)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("bodyage-hero")
    }

    private func factors(_ b: BodyAge) -> some View {
        Card {
            SectionHeader(title: "What makes it up", subtitle: "Last 30 days, \(Format.shortDay(b.window.from)) – \(Format.shortDay(b.window.to))")
            ForEach(b.factors) { f in
                factorRow(f)
                if f.id != b.factors.last?.id { Divider().overlay(Theme.track) }
            }
            if b.factors.contains(where: { $0.key == "steps" }) && b.factors.contains(where: { $0.key == "exercise" }) {
                Text("Steps and exercise measure much the same activity, so the total uses their average.")
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }

    private func factorRow(_ f: BodyAge.Factor) -> some View {
        let expanded = open.contains(f.key)
        return Button {
            withAnimation(.snappy) {
                if expanded { open.remove(f.key) } else { open.insert(f.key) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Image(systemName: Self.icon(f.key))
                        .font(.subheadline)
                        .foregroundStyle(Self.tint(f.key))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Self.tint(f.key).opacity(0.15)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.label).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        Text("\(Format.number(f.value, decimals: f.value < 100 ? 1 : 0)) \(f.unit)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 6)
                    Text(Self.yearsText(f.years))
                        .font(Theme.number(15, weight: .semibold))
                        .foregroundStyle(Self.color(f.years))
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                if expanded {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Compared with: \(f.reference)").foregroundStyle(Theme.secondary)
                        Text(f.detail).foregroundStyle(Theme.secondary)
                        Text("Source: \(f.source) · \(f.days) days of data").foregroundStyle(Theme.tertiary)
                    }
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 44)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("bodyage-factor-\(f.key)")
    }

    private func whatIf(_ b: BodyAge) -> some View {
        Card {
            SectionHeader(title: "What would lower it", subtitle: "One change at a time, the rest as it is")
            ForEach(b.whatIf) { w in
                HStack {
                    Image(systemName: "arrow.down.right.circle.fill").foregroundStyle(Theme.recoveryGreen)
                    Text(w.change).font(.subheadline).foregroundStyle(.white)
                    Spacer(minLength: 8)
                    Text(Self.yearsText(w.years)).font(Theme.number(15, weight: .semibold)).foregroundStyle(Theme.recoveryGreen)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("bodyage-whatif")
    }

    private func history(_ b: BodyAge) -> some View {
        let points = b.history.compactMap { p in Format.date(p.date).map { HistoryPoint(date: $0, value: p.bodyAge) } }
        let values = points.map(\.value) + [Double(b.age)]
        let lo = (values.min() ?? 0) - 1.5, hi = (values.max() ?? 0) + 1.5
        return Card {
            SectionHeader(title: "Over time", subtitle: "Each point: the 30 days up to that week")
            Chart {
                RuleMark(y: .value("Your age", Double(b.age)))
                    .foregroundStyle(Theme.tertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Your age").font(.caption2).foregroundStyle(Theme.tertiary)
                    }
                ForEach(points) { p in
                    LineMark(x: .value("Week", p.date), y: .value("Body age", p.value))
                        .foregroundStyle(Theme.recoveryGreen)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Week", p.date), y: .value("Body age", p.value))
                        .foregroundStyle(Theme.recoveryGreen)
                        .symbolSize(18)
                }
            }
            .chartYScale(domain: lo...hi)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine().foregroundStyle(Theme.track)
                    AxisValueLabel(format: .dateTime.month(.abbreviated)).foregroundStyle(Theme.tertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Theme.track)
                    AxisValueLabel().foregroundStyle(Theme.tertiary)
                }
            }
            .frame(height: 160)
        }
        .accessibilityIdentifier("bodyage-history")
    }

    private func fitness(_ vo2: BodyAge.Vo2) -> some View {
        Card {
            SectionHeader(title: "Estimated VO₂ max", subtitle: "Your band doesn't report it, so it's worked out from heart rate")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.number(vo2.value, decimals: 1)).font(Theme.number(30)).foregroundStyle(.white)
                Text("ml/kg/min").font(.caption).foregroundStyle(Theme.tertiary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Format.number(vo2.typicalForAge, decimals: 1)).font(Theme.number(17, weight: .semibold)).foregroundStyle(Theme.secondary)
                    Text("typical for your age").font(.caption2).foregroundStyle(Theme.tertiary)
                }
            }
            Text("\(vo2.method). It can be off by about ±\(Format.number(vo2.errorMlKgMin, decimals: 1)).")
                .font(.caption)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func missing(_ b: BodyAge) -> some View {
        Card {
            SectionHeader(title: "Not counted yet", subtitle: "Needs 14 days in the last 30")
            ForEach(b.missing, id: \.self) { m in
                Label(m.prefix(1).uppercased() + m.dropFirst(), systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    private func note(_ b: BodyAge) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(b.note)
                .font(.caption)
                .foregroundStyle(Theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink(value: "method") {
                Label("How it's calculated", systemImage: "function")
                    .font(.footnote.weight(.semibold))
            }
            .accessibilityIdentifier("bodyage-method")
        }
        .padding(.horizontal, 4)
    }

    // MARK: helpers

    static func differenceText(_ d: Double) -> String {
        if abs(d) < 0.05 { return "The same as your age" }
        return "\(Format.number(abs(d), decimals: 1)) years \(d < 0 ? "younger" : "older")"
    }

    static func yearsText(_ y: Double) -> String {
        if abs(y) < 0.05 { return "±0 yr" }
        return "\(y > 0 ? "+" : "−")\(Format.number(abs(y), decimals: 1)) yr"
    }

    static func color(_ years: Double) -> Color {
        if years <= -0.05 { return Theme.recoveryGreen }
        if years < 0.05 { return Theme.secondary }
        return years < 3 ? Theme.recoveryYellow : Theme.recoveryRed
    }

    static func icon(_ key: String) -> String {
        switch key {
        case "fitness": return "heart.circle.fill"
        case "steps": return "figure.walk"
        case "exercise": return "figure.run"
        default: return "bed.double.fill"
        }
    }

    static func tint(_ key: String) -> Color {
        switch key {
        case "fitness": return Theme.heart
        case "steps": return Theme.body
        case "exercise": return Theme.strain
        default: return Theme.sleep
        }
    }
}

private struct HistoryPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// A line from 10 years younger to 10 older than their age, with their age and body age on it.
private struct AgeScale: View {
    let age: Double
    let bodyAge: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x = { (v: Double) -> CGFloat in w * CGFloat(min(1, max(0, (v - age + 10) / 20))) }
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Theme.recoveryGreen, Theme.recoveryYellow, Theme.recoveryRed], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 6)
                    .clipShape(Capsule())
                    .opacity(0.55)
                    .offset(y: 4)
                Rectangle().fill(.white.opacity(0.6)).frame(width: 2, height: 14).offset(x: x(age) - 1)
                Circle().fill(.white).frame(width: 14, height: 14).offset(x: x(bodyAge) - 7)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                Text("−10").font(.caption2).foregroundStyle(Theme.tertiary).offset(y: 18)
                Text("your age").font(.caption2).foregroundStyle(Theme.tertiary)
                    .fixedSize()
                    .frame(width: 80)
                    .offset(x: x(age) - 40, y: 18)
                Text("+10").font(.caption2).foregroundStyle(Theme.tertiary).frame(width: w, alignment: .trailing).offset(y: 18)
            }
        }
        .accessibilityHidden(true)
    }
}

/// How body age is worked out, with the studies behind it.
struct BodyAgeMethodView: View {
    private let sources: [(String, String)] = [
        ("Uth et al. 2004, 2005 (Eur J Appl Physiol; Int J Sports Med)", "VO₂ max ≈ 15.3 (men) or 14.5 (women) × max heart rate ÷ resting heart rate. Tested in trained men and women; about ±4.7 ml/kg/min with an estimated max heart rate."),
        ("Loe et al. 2013 (PLoS One)", "Healthy Norwegians, 20–90 years: VO₂ max 54.4 (men) and 43.0 (women) at 20–29, about 3.5 lower per decade."),
        ("Kodama et al. 2009 (JAMA)", "33 studies: each 1 MET (3.5 ml/kg/min) higher fitness goes with 13% lower mortality (RR 0.87)."),
        ("Paluch et al. 2022 (Lancet Public Health)", "15 studies, 47,471 adults: against 3,553 steps a day, mortality was 40%, 45% and 53% lower at 5,801, 7,842 and 10,901 steps; no more benefit past 6,000–8,000 (60+) or 8,000–10,000 (under 60)."),
        ("Arem et al. 2015 (JAMA Intern Med)", "661,137 adults: against no leisure activity, 20% lower mortality below the 150-minute minimum, 31% at 1–2×, 37% at 2–3× and 39% at 3–5× (the upper threshold of benefit)."),
        ("Cappuccio et al. 2010 (Sleep)", "16 studies, 1.4 million people: short sleep RR 1.12 and long sleep RR 1.30 against 7–8 hours (sleep as people reported it, which is closer to time in bed)."),
        ("Finch et al. 1990 (Science)", "Human mortality doubles about every 8 years, so a relative risk RR is worth 8 × log₂(RR) years of age."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card {
                    SectionHeader(title: "The idea")
                    Text("Each factor's link with the risk of dying, from large studies, is turned into years of age: someone whose risk is like that of a person 2 years older gets +2 years. Fitness, activity (the average of steps and exercise) and sleep are added up, within ±15 years.")
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                    Text("It's FitStats' own combination of published numbers, not a validated test, and it says nothing about your cells or genes. Resting heart rate counts once, through the fitness estimate. Sleep regularity isn't included: your band's data can't be compared with how the study measured it.")
                        .font(.footnote).foregroundStyle(Theme.tertiary)
                }
                Card {
                    SectionHeader(title: "Sources")
                    ForEach(sources.indices, id: \.self) { i in
                        let s = sources[i]
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.0).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            Text(s.1).font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle("How it's calculated")
        .navigationBarTitleDisplayMode(.inline)
    }
}
