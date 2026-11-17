import Foundation
import Testing
@testable import TobiasCore

/// Runs `PrivilegedRun` against a shell script that behaves like `sudo -S -p <marker>`, never real sudo.
@Suite struct PrivilegedRunTests {
    /// Asks for the password up to twice; "secret" runs the command, anything else fails.
    static let fakeSudo = """
    m='\(PrivilegedRun.promptMarker)'
    printf '%s' "$m" >&2; read pw
    if [ "$pw" != secret ]; then echo 'Sorry, try again.' >&2; printf '%s' "$m" >&2; read pw; fi
    if [ "$pw" = secret ]; then echo 'removed system.log.1.gz'; exit 0; fi
    exit 1
    """

    private func run(_ script: String, answering passwords: [String], stopOnPrompt: Bool = false) async throws -> [PrivilegedRun.Event] {
        let run = PrivilegedRun(command: "", executable: "/bin/sh", arguments: ["-c", script])
        try run.start()
        var answers = passwords
        var events: [PrivilegedRun.Event] = []
        for await event in run.events {
            events.append(event)
            if event == .passwordPrompt {
                if stopOnPrompt { run.stop() } else if !answers.isEmpty { run.sendPassword(answers.removeFirst()) }
            }
        }
        return events
    }

    private func text(_ events: [PrivilegedRun.Event]) -> String {
        events.compactMap { if case .output(let s) = $0 { return s } else { return nil } }.joined()
    }

    @Test func correctPasswordRunsTheCommand() async throws {
        let events = try await run(Self.fakeSudo, answering: ["secret"])
        #expect(events.filter { $0 == .passwordPrompt }.count == 1)
        #expect(text(events).contains("removed system.log.1.gz"))
        #expect(events.last == .exited(0))
    }

    @Test func wrongPasswordAsksAgain() async throws {
        let events = try await run(Self.fakeSudo, answering: ["nope", "secret"])
        #expect(events.filter { $0 == .passwordPrompt }.count == 2)
        #expect(text(events).contains("Sorry, try again."))
        #expect(events.last == .exited(0))
    }

    @Test func markerAndPasswordNeverReachTheOutput() async throws {
        let events = try await run(Self.fakeSudo, answering: ["hunter2", "secret"])
        let output = text(events)
        #expect(!output.contains(PrivilegedRun.promptMarker))
        #expect(!output.contains("hunter2"))
        #expect(!output.contains("secret"))
    }

    @Test func stopEndsTheRun() async throws {
        let script = "printf '%s' '\(PrivilegedRun.promptMarker)' >&2; sleep 30"
        let events = try await run(script, answering: [], stopOnPrompt: true)
        guard case .exited(let code) = events.last else { Issue.record("no exit"); return }
        #expect(code != 0)
    }

    @Test func markerSplitAcrossReadsIsHeldBack() {
        #expect(PrivilegedRun.markerPrefixLength(at: "Password check __TOB") == 5)
        #expect(PrivilegedRun.markerPrefixLength(at: "plain output\n") == 0)
    }

    @Test func sudoArgumentsAskEveryTimeAndReadStdin() {
        let args = PrivilegedRun.arguments(for: "true")
        #expect(args.prefix(4) == ["-S", "-k", "-p", PrivilegedRun.promptMarker])
        #expect(args.suffix(3) == ["/bin/sh", "-c", "true"])
    }
}
