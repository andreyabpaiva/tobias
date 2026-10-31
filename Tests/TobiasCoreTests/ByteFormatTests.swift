import Foundation
import Testing
@testable import TobiasCore

@Suite struct ByteFormatTests {
    @Test func wholeDropsDecimals() {
        #expect(ByteFormat.whole(64_040_000_000) == "64 GB")
        #expect(ByteFormat.whole(2_600_000_000) == "3 GB")
    }

    @Test func wholeUsesMegabytesBelowOneGigabyte() {
        #expect(ByteFormat.whole(512_400_000) == "512 MB")
    }
}
