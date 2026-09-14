import Foundation
import Testing

@testable import AppTape

/// The sidebar's day grouping.
@MainActor
struct RecordingDayTests {
    private let calendar = Calendar.current

    /// Local midnight `days` ago, plus `minutes` — so a case can sit either side of a boundary
    /// without depending on what time the suite happens to run at.
    private func midnight(daysAgo days: Int, plusMinutes minutes: Double = 0) -> Date {
        let today = calendar.startOfDay(for: .now)
        let day = calendar.date(byAdding: .day, value: -days, to: today) ?? today
        return day.addingTimeInterval(minutes * 60)
    }

    @Test func daysComeNewestFirst() {
        let today = Recording.stub("today", recordedAt: midnight(daysAgo: 0, plusMinutes: 600))
        let yesterday = Recording.stub("yesterday", recordedAt: midnight(daysAgo: 1, plusMinutes: 600))
        let lastWeek = Recording.stub("lastWeek", recordedAt: midnight(daysAgo: 9, plusMinutes: 600))

        // Handed over in the wrong order on purpose.
        let days = RecordingDay.group([lastWeek, today, yesterday])
        #expect(days.map { $0.recordings.map(\.name) } == [["today"], ["yesterday"], ["lastWeek"]])
    }

    @Test func withinADayTheOrderIsTheOneItWasGiven() {
        // The store has already sorted newest-first, and grouping must not undo that — it buckets
        // by day and keeps each bucket in the order it arrived.
        let later = Recording.stub("later", recordedAt: midnight(daysAgo: 0, plusMinutes: 800))
        let earlier = Recording.stub("earlier", recordedAt: midnight(daysAgo: 0, plusMinutes: 400))

        let days = RecordingDay.group([later, earlier])
        #expect(days.count == 1)
        #expect(days[0].recordings.map(\.name) == ["later", "earlier"])
    }

    @Test func twoRecordingsOnOneDayShareOneHeader() {
        let a = Recording.stub("a", recordedAt: midnight(daysAgo: 2, plusMinutes: 100))
        let b = Recording.stub("b", recordedAt: midnight(daysAgo: 2, plusMinutes: 900))
        let days = RecordingDay.group([b, a])
        #expect(days.count == 1)
        #expect(days[0].recordings.count == 2)
    }

    @Test func todayAndYesterdayAreNamedRatherThanDated() {
        let today = Recording.stub("today", recordedAt: midnight(daysAgo: 0, plusMinutes: 600))
        let yesterday = Recording.stub("yesterday", recordedAt: midnight(daysAgo: 1, plusMinutes: 600))
        let days = RecordingDay.group([today, yesterday])
        #expect(days.map(\.title) == ["Today", "Yesterday"])
    }

    @Test func insideAWeekTheTitleIsTheWeekdayAndBeyondItTheDate() throws {
        let midWeek = Recording.stub("midWeek", recordedAt: midnight(daysAgo: 3, plusMinutes: 600))
        let longAgo = Recording.stub("longAgo", recordedAt: midnight(daysAgo: 30, plusMinutes: 600))
        let days = RecordingDay.group([midWeek, longAgo])
        #expect(days.count == 2)

        // Three days back is neither Today nor Yesterday, so it is spoken as a weekday.
        let expectedWeekday = try #require(midWeek.recordedAt).formatted(.dateTime.weekday(.wide))
        #expect(days[0].title == expectedWeekday)
        #expect(days[0].title != "Today" && days[0].title != "Yesterday")

        // A month back, the weekday no longer identifies it, so the day and month do.
        let expectedDate = try #require(longAgo.recordedAt).formatted(.dateTime.day().month(.abbreviated))
        #expect(days[1].title == expectedDate)
    }

    /// the own consequence, and nothing checked it: `recordedAt` is when capture *started*, so a
    /// Recording that ran across midnight is filed under the day it began.
    @Test func aRecordingThatRanAcrossMidnightIsFiledUnderTheDayItBegan() {
        let acrossMidnight = Recording.stub(
            "acrossMidnight",
            seconds: 40 * 60,
            recordedAt: midnight(daysAgo: 0, plusMinutes: -10))
        let days = RecordingDay.group([acrossMidnight])
        #expect(days.count == 1)
        #expect(days[0].title == "Yesterday")
    }

    @Test func aRecordingWithNoDateIsStillListedRatherThanDropped() {
        // Its date could not be read; it is still a Recording, and it goes in the oldest bucket.
        let dated = Recording.stub("dated", recordedAt: midnight(daysAgo: 0, plusMinutes: 600))
        let undated = Recording.stub("undated", recordedAt: nil)

        let days = RecordingDay.group([dated, undated])
        #expect(days.count == 2)
        #expect(days[0].recordings.map(\.name) == ["dated"])
        #expect(days[1].recordings.map(\.name) == ["undated"])
        #expect(days[1].date == calendar.startOfDay(for: .distantPast))
    }

    @Test func anEmptyLibraryGroupsToNoDays() {
        #expect(RecordingDay.group([]).isEmpty)
    }

    @Test func aDayIsIdentifiedByItsDate() {
        // `RecordingDay: Identifiable` keyed on the date, which is what keeps `ForEach` stable
        // across a refresh that re-adopted a row.
        let days = RecordingDay.group([Recording.stub(recordedAt: midnight(daysAgo: 1))])
        #expect(days.count == 1)
        #expect(days[0].id == days[0].date)
    }
}
