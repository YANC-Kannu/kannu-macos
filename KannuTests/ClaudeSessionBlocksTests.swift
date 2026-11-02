import XCTest

/// Pins the local 5-hour block that backs the "Session (local)" row: the plan's own window when
/// Claude reported its reset, the hour-floored reconstruction otherwise.
final class ClaudeSessionBlocksTests: XCTestCase {
    private func date(_ hour: Double) -> Date {
        // Hours after an arbitrary hour-aligned epoch, so flooring math is easy to reason about.
        Date(timeIntervalSince1970: 1_800_000_000 + hour * 3600)
    }

    /// Whole minutes after the same epoch, for times off the hour.
    private func minute(_ minutes: Int) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + TimeInterval(minutes * 60))
    }

    func testWithoutAResetTheBlockAnchorsAtTheFlooredFirstRecordAndSaysItIsApproximate() {
        let block = ClaudeSessionBlocks.currentBlock(
            records: [(date(0.5), 100), (date(1.0), 200)],
            now: date(2)
        )
        XCTAssertEqual(block?.startedAt, date(0), "anchor floors the first record to the hour")
        XCTAssertEqual(block?.resetsAt, date(5))
        XCTAssertEqual(block?.totalTokens, 300)
        XCTAssertEqual(block?.isApproximate, true, "the hour floor is a guess: the plan's window can start at :10")
    }

    // MARK: - The plan's own window

    func testAKnownResetMakesTheBlockThePlansWindow() {
        // Claude says the window resets at 5:10, so it began at 0:10: the record at 0:05 is the
        // previous window's, though the hour floor would have counted it.
        let block = ClaudeSessionBlocks.currentBlock(
            records: [(minute(5), 1_000), (minute(30), 100), (minute(120), 200), (minute(240), 999)],
            now: minute(180),
            fiveHourResetsAt: minute(310)
        )
        XCTAssertEqual(block?.startedAt, minute(10))
        XCTAssertEqual(block?.resetsAt, minute(310))
        XCTAssertEqual(block?.totalTokens, 300, "inside [reset − 5 h, now]: not before it, not after now")
        XCTAssertEqual(block?.isApproximate, false)
        XCTAssertEqual(block?.burnRatePerMinute ?? 0, 300.0 / 170, accuracy: 0.0001)
    }

    func testAKnownResetGivesABlockEvenWithNoLocalRecordInIt() {
        let block = ClaudeSessionBlocks.currentBlock(records: [(date(-9), 50)], now: date(1), fiveHourResetsAt: date(4))
        XCTAssertEqual(block?.totalTokens, 0, "the window runs (other devices count against it too); nothing local in it")
        XCTAssertEqual(block?.isApproximate, false)
    }

    func testAResetThatCannotDescribeTheCurrentWindowFallsBackToTheApproximation() {
        let records: [(timestamp: Date, tokens: Int)] = [(date(0.5), 100)]
        for reset in [date(1.5), date(2), date(9)] {   // past, now, more than five hours (and the slack) away
            let block = ClaudeSessionBlocks.currentBlock(records: records, now: date(2), fiveHourResetsAt: reset)
            XCTAssertEqual(block?.startedAt, date(0), "\(reset)")
            XCTAssertEqual(block?.isApproximate, true, "\(reset)")
        }
    }

    func testGapBeyondFiveHoursStartsANewBlock() {
        let block = ClaudeSessionBlocks.currentBlock(
            records: [(date(0.2), 1_000), (date(6.5), 50)],
            now: date(7)
        )
        XCTAssertEqual(block?.startedAt, date(6), "old block expired; new one anchors at 6:00")
        XCTAssertEqual(block?.totalTokens, 50, "expired block's tokens must not leak in")
        XCTAssertEqual(block?.resetsAt, date(11))
    }

    func testRecordInsideWindowExtendsTheSameBlock() {
        let block = ClaudeSessionBlocks.currentBlock(
            records: [(date(0.1), 10), (date(4.9), 20)],
            now: date(4.95)
        )
        XCTAssertEqual(block?.startedAt, date(0))
        XCTAssertEqual(block?.totalTokens, 30)
    }

    func testExpiredLatestBlockReturnsNil() {
        let block = ClaudeSessionBlocks.currentBlock(
            records: [(date(0.5), 100)],
            now: date(6)
        )
        XCTAssertNil(block, "no active block once the latest window has fully elapsed")
    }

    func testBurnRateIsTokensPerMinuteOverTheBlock() {
        // 600 tokens, block anchored at hour 0, now = 60 minutes in.
        let block = ClaudeSessionBlocks.currentBlock(
            records: [(date(0.0), 600)],
            now: date(1)
        )
        XCTAssertEqual(block?.burnRatePerMinute ?? 0, 10, accuracy: 0.01)
    }

    func testFutureRecordsAreIgnored() {
        let block = ClaudeSessionBlocks.currentBlock(
            records: [(date(0.5), 100), (date(3), 999)],
            now: date(1)
        )
        XCTAssertEqual(block?.totalTokens, 100, "records after `now` must not count")
    }

    func testEmptyInputReturnsNil() {
        XCTAssertNil(ClaudeSessionBlocks.currentBlock(records: [], now: date(0)))
    }
}
