# Safety model

Tobias deletes files, so everything that can delete goes through a small set of rules.

1. **Only catalog actions.** What can be touched comes from `catalog.json` and the user's own `targets.json`. The UI selects targets by id. There is no field anywhere that accepts a free-form path or command.
2. **`PathGuard` before every removal.** It expands `~`, resolves symlinks, and requires the resolved path to sit strictly under an allowed root (the home folder and `/opt/homebrew`).
3. **Protected locations.** These can never be a target themselves: `/`, the home folder, `Library`, `Documents`, `Desktop`, `Downloads`, `Pictures`, `Movies`, `Music`, `Library/Application Support`, `Library/Caches`, `Library/Containers`, `Library/Group Containers`, `Library/Preferences`, `Library/Logs`, `Library/Developer`, Homebrew's `Cellar` and `bin`. These trees are off limits entirely: `.ssh`, `.gnupg`, `Library/Keychains`, `Library/Mail`, `Library/Messages`, `Library/Mobile Documents`.
4. **No wildcards over shared folders.** A pattern such as `~/Library/Caches/*` is rejected, because it would select every app's data.
5. **No symlink surprises.** A target that is itself a symlink is refused. Removal deletes a symlink child as a link and never follows it.
6. **Contents, not the folder.** `removeContents` deletes what is inside the resolved folder and leaves the folder.
7. **Re-validated at delete time.** The guard runs at load, at preview and again right before each removal.
8. **Confirmation.** Cleaning needs a preview and an explicit confirm. Targets marked `redownloads` show an extra warning.
9. **Apps must be closed.** A target with `quitApps` is blocked while any of those apps run.
10. **Elevation only on request.** Only a `rootCommand` from the built-in catalog can run as root; `targets.json` cannot add one. It runs through `sudo` when you press ▶︎ Run, asks for your password every time, and never stores it. Today the only one deletes rotated logs in `/private/var/log`.
11. **Audit.** Every run appends a line to `audit.log` with the target, outcome and bytes freed.
12. **Fixed commands only.** `command` targets run a string from the catalog in the user's login shell. The built-in catalog is reviewed; user-defined commands carry the same trust as the user's shell configuration.

## Discovered targets

Discovery adds targets that are not in `catalog.json`, so it follows stricter rules: it only lists direct child folders of `~/Library/Caches` and `~/Library/Logs`, never `com.apple.*`, hidden folders, symlinks or names containing glob characters. Each result is an exact path (no wildcard) that passes `PathGuard` like any other target, goes through the same preview and confirmation, and is blocked while its app runs. A folder labelled *No matching app* may belong to a command-line tool; its contents are caches and are rebuilt if the tool still needs them. Nothing discovered is selected by default. Application Support, Containers and other places that can hold your data are not scanned.

## What Tobias never touches

Photos, Mail, Messages, iCloud Drive, Documents, Desktop, Downloads, SSH and GPG keys, and the Keychain. It does not read file contents; it only measures sizes.

## Reporting a problem

If a target deleted something it should not have, open an issue with the entry from `audit.log` and the target's `id`.
