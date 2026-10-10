import SwiftUI
import AppKit

/// Offline synthetic metadata only, using the actual store, aggregation and dashboard.
@main enum UsagePresentationTests {
    static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 1
        return calendar
    }
    static func date(_ day: Int, month: Int = 10) -> Date {
        calendar().date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }
    static func seed(_ store: UsageMetricsStore, fixture: String) {
        guard fixture != "empty", store.snapshot().archive.dictations.isEmpty else { return }
        let costs = [0.022, 0.005, 0.000056, 0.0006]
        for i in 0..<4 {
            let at = date(i + 1)
            let provider = i == 3 ? "cloudflare" : "openrouter"
            let id = UUID()
            let dictation = UsageDictation(id: id, recordedAt: at, originalSeconds: [724.0, 720, 442, 18][i], engine: provider, provider: provider, model: "synthetic")
            let run = store.begin(dictation, at: at, engine: provider, provider: provider, model: "synthetic")
            let request = UsageRequest(id: UUID(), dictationID: id, runID: run, startedAt: at, provider: provider, model: "synthetic", phase: "transcription", uploadedSeconds: 30)
            store.beginRequest(request)
            let cost: UsageCost
            switch fixture {
            case "unknown": cost = UsageCost()
            case "zero": cost = UsageCost(kind: .actual, usd: 0)
            case "estimate": cost = UsageCost(kind: .estimate, usd: costs[i])
            default: cost = UsageCost(kind: .actual, usd: costs[i])
            }
            store.finishRequest(request.id, outcome: "httpSuccess", cost: cost, at: at)
            if fixture == "mixed" {
                let cleanup = UsageRequest(id: UUID(), dictationID: id, runID: run, startedAt: at, provider: provider, model: "synthetic", phase: "cleanup", uploadedSeconds: nil)
                store.beginRequest(cleanup)
                store.finishRequest(cleanup.id, outcome: "httpSuccess", cost: UsageCost(kind: .estimate, usd: costs[i] / 2), at: at)
            }
            store.finishRun(run, outcome: "success", at: at)
        }
    }
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if CommandLine.arguments.count == 2 {
            for fixture in ["reported", "estimate", "mixed", "zero", "unknown", "empty"] {
                let url = root.appendingPathComponent("test-\(fixture)/usage.json")
                let store = UsageMetricsStore(url: url)
                seed(store, fixture: fixture)
                let archive = store.snapshot().archive
                for period in UsagePeriod.allCases {
                    for provider in [nil, "openrouter", "cloudflare", "parakeet"] as [String?] {
                        let buckets = UsageAggregation.buckets(archive, start: date(1), end: date(5), period: period, provider: provider, calendar: calendar())
                        let actual = buckets.reduce(0) { $0 + $1.actualUSD }
                        let estimate = buckets.reduce(0) { $0 + $1.estimatedUSD }
                        let unknown = buckets.reduce(0) { $0 + $1.unknownCosts }
                        let expected = provider == "parakeet" || fixture == "empty" ? 0 : provider == "cloudflare" ? 0.0006 : provider == "openrouter" ? 0.027056 : 0.027656
                        assert(abs(actual - (["reported", "mixed"].contains(fixture) ? expected : 0)) < 1e-12)
                        assert(abs(estimate - (fixture == "estimate" ? expected : fixture == "mixed" ? expected / 2 : 0)) < 1e-12)
                        assert(UsageCostPresentation.hasBothSeries(buckets) == (fixture == "mixed" && expected > 0))
                        assert(unknown == (fixture == "unknown" ? (provider == "parakeet" ? 0 : provider == "openrouter" ? 3 : provider == "cloudflare" ? 1 : 4) : 0))
                        for bucket in buckets {
                            assert(Double(UsageCostPresentation.exact(bucket.actualUSD)) == bucket.actualUSD)
                            assert(Double(UsageCostPresentation.exact(bucket.estimatedUSD)) == bucket.estimatedUSD)
                        }
                        let ticks = UsageCalendarAxis.ticks(buckets, period: period, calendar: calendar())
                        assert(ticks.count <= 4)
                        assert(ticks.first == UsageCalendarAxis.center(buckets.first!.start, period: period, calendar: calendar()))
                        assert(ticks.last == UsageCalendarAxis.center(buckets.last!.start, period: period, calendar: calendar()))
                    }
                }
            }
            let weeklyRange = UsageAggregation.buckets(UsageArchive(), start: date(5, month: 9), end: date(5), period: .weekly, calendar: calendar())
            let weeklyTicks = UsageCalendarAxis.ticks(weeklyRange, period: .weekly, calendar: calendar())
            assert(weeklyTicks.count == weeklyRange.count)
            for bucket in weeklyRange {
                assert(weeklyTicks.contains(UsageCalendarAxis.center(bucket.start, period: .weekly, calendar: calendar())))
            }
            assert(UsageCostPresentation.exact(0.000056) == "0.000056")
            for value in [Double.leastNonzeroMagnitude, 1e-100, 1e-20, 0.00005555555555555556, 0.02741666666666666, 1e20] {
                assert(Double(UsageCostPresentation.exact(value)) == value)
            }
            var disjoint = [UsageBucket(start: date(1)), UsageBucket(start: date(2))]
            disjoint[0].actualUSD = 0.022
            disjoint[1].estimatedUSD = 0.005
            assert(UsageCostPresentation.hasBothSeries(disjoint))
            assert(UsageCostPresentation.exact(0) == "0")
            assert(UsageCostPresentation.exact(0.000000000056) != "0")
            assert(!UsageCostPresentation.hasBothSeries([]))
            assert(UsageCalendarAxis.ticks([], period: .daily, calendar: calendar()).isEmpty)
            // DST uses the true calendar interval, not 24-hour offsets.
            let spring = date(8, month: 3)
            let interval = calendar().dateInterval(of: .day, for: spring)!
            assert(interval.duration == 23 * 3600)
            assert(UsageCalendarAxis.center(spring, period: .daily, calendar: calendar()) == interval.start.addingTimeInterval(11.5 * 3600))
            var monday = calendar()
            monday.firstWeekday = 2
            assert(UsageCalendarAxis.label(date(4), period: .weekly, calendar: monday) == "Week of Sep 28")
            let fall = date(1, month: 11)
            assert(calendar().dateInterval(of: .day, for: fall)!.duration == 25 * 3600)
            assert(UsageCalendarAxis.label(date(4), period: .weekly, calendar: calendar()) == "Week of Oct 4")
            assert(UsageCalendarAxis.label(date(4), period: .monthly, calendar: calendar()) == "Oct 2026")
            print("PASS production presentation: six fixtures, three periods, four provider filters, exact positive/zero values, calendar ticks and DST")
            return
        }
        let fixture = CommandLine.arguments[2]
        let period = UsagePeriod.allCases.first { $0.rawValue.lowercased() == CommandLine.arguments[3] }!
        let width = Double(CommandLine.arguments[4])!
        let provider = CommandLine.arguments.count > 5 ? CommandLine.arguments[5] : "all"
        let range = CommandLine.arguments.count > 6 ? CommandLine.arguments[6] : "30"
        let name = "\(fixture)-\(period.rawValue.lowercased())-\(Int(width))-\(provider)" + (range == "30" ? "" : "-\(range)")
        let store = UsageMetricsStore(url: root.appendingPathComponent("\(name)/usage.json"))
        seed(store, fixture: fixture)
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: width, height: 1200), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Synthetic dashboard probe"
        let host = NSHostingView(rootView: UsageDashboard(store: store, initialProvider: provider, initialPeriod: period, initialRange: range, initialCostBucket: calendar().startOfDay(for: date(3)), referenceDate: date(4)))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
            do { try data.write(to: root.appendingPathComponent(name + ".png")) } catch { print(error); exit(1) }
            print("Rendered \(name), actual production dashboard/store, synthetic isolated profile")
            window.close()
            application.terminate(nil)
        }
        application.run()
    }
}
