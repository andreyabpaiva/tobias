import Foundation
import Testing
@testable import TobiasCore

@Suite struct DiskScannerTests {
    @Test func sumsFilesRecursively() throws {
        let sb = try Sandbox()
        try sb.makeFile("data/a.bin", kilobytes: 256)
        try sb.makeFile("data/nested/b.bin", kilobytes: 256)
        let m = DiskScanner().measure(paths: [sb.path("data")])
        #expect(m.exists)
        #expect(m.files == 2)
        #expect(m.bytes >= 512 * 1024)
        #expect(m.bytes < 512 * 1024 + 128 * 1024)
    }

    @Test func missingPathDoesNotExist() throws {
        let sb = try Sandbox()
        let m = DiskScanner().measure(paths: [sb.path("nope")])
        #expect(!m.exists)
        #expect(m.bytes == 0)
    }

    @Test func ignoresSymlinks() throws {
        let sb = try Sandbox()
        let big = try sb.makeFile("outside/big.bin", kilobytes: 1024)
        try sb.makeDir("data")
        try FileManager.default.createSymbolicLink(atPath: sb.path("data/link"), withDestinationPath: big)
        let m = DiskScanner().measure(paths: [sb.path("data")])
        #expect(m.files == 0)
        #expect(m.bytes == 0)
    }

    @Test func countsHardLinksOnce() throws {
        let sb = try Sandbox()
        let original = try sb.makeFile("data/a.bin", kilobytes: 256)
        try FileManager.default.linkItem(atPath: original, toPath: sb.path("data/b.bin"))
        let m = DiskScanner().measure(paths: [sb.path("data")])
        #expect(m.files == 1)
    }

    @Test func scanKeepsTargetOrder() async throws {
        let sb = try Sandbox()
        try sb.makeFile("one/a.bin", kilobytes: 64)
        try sb.makeFile("two/a.bin", kilobytes: 512)
        let targets = [
            Target(id: "one", label: "One", paths: [sb.path("one")], action: .removeContents),
            Target(id: "two", label: "Two", paths: [sb.path("two")], action: .removeContents),
            Target(id: "gone", label: "Gone", paths: [sb.path("gone")], action: .removeContents),
        ]
        let sizes = await DiskScanner(concurrency: 2).scan(targets, pathGuard: sb.pathGuard)
        #expect(sizes.map(\.id) == ["one", "two", "gone"])
        #expect(sizes[1].bytes > sizes[0].bytes)
        #expect(!sizes[2].exists)
    }
}
