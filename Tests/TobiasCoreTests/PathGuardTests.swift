import Foundation
import Testing
@testable import TobiasCore

@Suite struct PathGuardTests {
    @Test func acceptsAppCacheFolder() throws {
        let sb = try Sandbox()
        let dir = try sb.makeDir("Library/Caches/SomeApp")
        let resolved = try sb.pathGuard.validateForRemoval(dir)
        #expect(resolved == dir)
    }

    @Test func rejectsHomeAndTopLevelFolders() throws {
        let sb = try Sandbox()
        for rel in ["", "Library", "Documents", "Desktop", "Library/Application Support", "Library/Caches"] {
            let dir = rel.isEmpty ? sb.home.path : try sb.makeDir(rel)
            #expect(throws: GuardError.self) { try sb.pathGuard.validateForRemoval(dir) }
        }
    }

    @Test func rejectsRootAndOutsidePaths() throws {
        let sb = try Sandbox()
        #expect(throws: GuardError.self) { try sb.pathGuard.validateForRemoval("/") }
        #expect(throws: GuardError.self) { try sb.pathGuard.validateForRemoval("/etc") }
        #expect(throws: GuardError.self) { try sb.pathGuard.validateForRemoval("/Users") }
    }

    @Test func rejectsParentTraversal() throws {
        let sb = try Sandbox()
        try sb.makeDir("Library/Caches/App")
        #expect(throws: GuardError.traversal(sb.path("Library/Caches/App/../../.."))) {
            try sb.pathGuard.validateForRemoval(sb.path("Library/Caches/App/../../.."))
        }
    }

    @Test func rejectsSymlinkTarget() throws {
        let sb = try Sandbox()
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("tobias-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try sb.makeDir("Library/Caches")
        let link = sb.path("Library/Caches/Evil")
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: outside.path)
        #expect(throws: GuardError.symlinkTarget(link)) { try sb.pathGuard.validateForRemoval(link) }
    }

    @Test func rejectsSecretsTrees() throws {
        let sb = try Sandbox()
        try sb.makeFile(".ssh/id_ed25519")
        #expect(throws: GuardError.self) { try sb.pathGuard.validateForRemoval(sb.path(".ssh/id_ed25519")) }
        try sb.makeDir("Library/Mail/V10")
        #expect(throws: GuardError.self) { try sb.pathGuard.validateForRemoval(sb.path("Library/Mail/V10")) }
    }

    @Test func expandsTilde() throws {
        let sb = try Sandbox()
        #expect(sb.pathGuard.expand("~/.npm") == sb.home.path + "/.npm")
        #expect(sb.pathGuard.expand("~") == sb.home.path)
    }

    @Test func patternAllowsSpecificBraces() throws {
        let sb = try Sandbox()
        try sb.pathGuard.validatePattern("~/Library/Application Support/Code/{CachedData,GPUCache}")
        try sb.pathGuard.validatePattern("~/.npm")
    }

    @Test func patternRejectsBroadWildcards() throws {
        let sb = try Sandbox()
        #expect(throws: GuardError.self) { try sb.pathGuard.validatePattern("~/Library/Caches/*") }
        #expect(throws: GuardError.self) { try sb.pathGuard.validatePattern("~/*") }
        #expect(throws: GuardError.self) { try sb.pathGuard.validatePattern("~/Library") }
        #expect(throws: GuardError.self) { try sb.pathGuard.validatePattern("/etc/*") }
        #expect(throws: GuardError.self) { try sb.pathGuard.validatePattern("relative/path") }
    }
}
