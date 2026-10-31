# Tobias: sequence diagrams

## 1. Launch and scheduled scan

```mermaid
sequenceDiagram
  actor U as User
  participant App as Tobias app
  participant Sch as ScanScheduler
  participant Cat as Catalog
  participant Disc as CacheDiscovery
  participant Sc as DiskScanner
  participant St as Store
  U->>App: open app / login item starts it
  App->>St: load state.json
  App->>Cat: load bundled + user targets
  Cat-->>App: validated targets
  App->>Disc: discover Library/Caches and Logs folders
  Disc-->>App: extra targets + owner status (installed / removed)
  App->>Sc: scan(catalog + discovered)
  loop each target (4 concurrent)
    Sc->>Sc: walk paths, sum allocated size
  end
  Sc-->>App: sizes, blocked, free space
  App->>App: drop discovered folders under 20 MB
  App->>St: save lastScan + history
  App-->>U: list sorted by size
  Sch->>App: every 6 h, scan again
  App-->>U: notification if low space (optional)
```

## 2. Preview and clean

```mermaid
sequenceDiagram
  actor U as User
  participant UI as SwiftUI views
  participant M as AppModel
  participant G as PathGuard
  participant E as Executor
  participant A as audit.log
  U->>UI: select targets, click Clean
  UI->>M: beginClean()
  M->>E: preview(target)
  E->>G: validate paths
  G-->>E: ok / rejected
  E-->>M: sizes + sample paths
  M-->>UI: preview sheet
  U->>UI: confirm
  UI->>M: confirmClean()
  loop each target
    M->>E: run(target)
    E->>E: running apps present?
    alt app running
      E-->>M: blocked (quit app)
    else ok
      E->>G: re-validate at delete time
      E->>E: remove children or run fixed command
      E->>A: append result
      E-->>M: freed bytes / error
    end
  end
  M->>M: rescan
  M-->>UI: results + restart banner
```

## 3. Manual (root) target

```mermaid
sequenceDiagram
  actor U as User
  participant UI as SwiftUI views
  participant T as Terminal
  U->>UI: open "System logs" target
  UI-->>U: size + explanation + Copy command
  U->>UI: Copy
  U->>T: paste and run the sudo command
  U->>UI: Scan now
  UI-->>U: updated size
```

## 4. First install (no clone)

```mermaid
sequenceDiagram
  actor U as User
  participant Sh as install.sh
  participant GH as GitHub (release tarball)
  participant B as build-app.sh
  participant FS as ~/Applications and ~/.local/bin
  U->>Sh: curl -fsSL .../install.sh | bash
  Sh->>Sh: check macOS version and Command Line Tools
  Sh->>GH: download release tarball + sha256
  Sh->>Sh: verify checksum
  Sh->>B: swift build -c release, assemble .app, ad-hoc codesign
  B-->>Sh: Tobias.app
  Sh->>FS: copy app to ~/Applications
  Sh->>FS: install bin/tobias to ~/.local/bin
  Sh-->>U: installed vX.Y.Z, PATH hint if needed, opens the app
```

## 5. Update and uninstall

```mermaid
sequenceDiagram
  actor U as User
  participant CLI as tobias CLI
  participant GH as GitHub API
  participant FS as ~/Applications
  U->>CLI: tobias update
  CLI->>GH: latest release tag
  GH-->>CLI: tag
  alt tag equals installed version
    CLI-->>U: already up to date
  else newer
    CLI->>GH: fetch install.sh for that tag
    CLI->>CLI: run installer (download, verify, build)
    CLI->>FS: quit app, replace bundle, relaunch
    CLI-->>U: updated old to new
  end
  U->>CLI: tobias uninstall
  CLI->>FS: quit app, unregister login item, remove bundle, remove CLI
  CLI-->>U: removed (data kept; tobias purge deletes it)
```
