// PrepTimingTests — guards the Duration→milliseconds conversion used by the
// prep-stage timing instrumentation. A wrong divisor would silently make every
// "TIMING:" number off by orders of magnitude — exactly the failure that defeats
// the measurement increment, so it gets the one check.

import XCTest
@testable import Session

final class PrepTimingTests: XCTestCase {

    func testDurationMsConvertsKnownDurations() {
        XCTAssertEqual(durationMs(.seconds(2)), 2_000, accuracy: 1e-6)
        XCTAssertEqual(durationMs(.milliseconds(1_500)), 1_500, accuracy: 1e-6)
        XCTAssertEqual(durationMs(.microseconds(500)), 0.5, accuracy: 1e-6)
        XCTAssertEqual(durationMs(.zero), 0, accuracy: 1e-6)
    }
}
