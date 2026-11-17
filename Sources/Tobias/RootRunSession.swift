import Foundation
import Observation
import TobiasCore

/// One run of a target's `rootCommand` in the in-app terminal: transcript, password prompt, result.
@MainActor
@Observable
final class RootRunSession {
    enum Phase: Equatable {
        case ready, running, needsPassword, succeeded, failed(Int32), stopped

        var isActive: Bool { self == .running || self == .needsPassword }
        var isFinished: Bool {
            switch self {
            case .succeeded, .failed, .stopped: return true
            default: return false
            }
        }
    }

    let target: Target
    var phase: Phase = .ready
    /// Everything shown in the terminal, as it arrived. Never contains the password.
    var transcript = ""
    var freedBytes: Int64?

    private var run: PrivilegedRun?
    private var stopping = false
    private let onExit: (RootRunSession, Int32, Bool) async -> Void

    init(target: Target, onExit: @escaping (RootRunSession, Int32, Bool) async -> Void) {
        self.target = target
        self.onExit = onExit
    }

    /// What the terminal shows as the command, and what Copy copies.
    var commandLine: String { target.manualCommand ?? "sudo sh -c \"\(target.rootCommand ?? "")\"" }

    func start() {
        guard let command = target.rootCommand, !phase.isActive else { return }
        let run = PrivilegedRun(command: command)
        self.run = run
        stopping = false
        freedBytes = nil
        transcript = "$ \(commandLine)\n"
        phase = .running
        do { try run.start() } catch { /* `start` already reported the failure as events */ }
        Task {
            for await event in run.events { await handle(event) }
        }
    }

    func submit(password: String) {
        guard phase == .needsPassword else { return }
        run?.sendPassword(password)
        transcript += "\(Strings.passwordPrompt) ••••••\n"
        phase = .running
    }

    func stop() {
        guard phase.isActive else { return }
        stopping = true
        run?.stop()
    }

    private func handle(_ event: PrivilegedRun.Event) async {
        switch event {
        case .output(let text):
            transcript += text
        case .passwordPrompt:
            phase = .needsPassword
        case .exited(let code):
            run = nil
            if stopping {
                phase = .stopped
            } else {
                phase = code == 0 ? .succeeded : .failed(code)
            }
            await onExit(self, code, stopping)
        }
    }
}
