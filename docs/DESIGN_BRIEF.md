# Design brief: Tobias

Paste this into Claude Design. It describes every screen, component and state of Tobias, with realistic data and the exact copy, so the visual design can be done without reading the code.

## What Tobias is

A native macOS app (SwiftUI) that finds caches, logs and build output that waste disk space and lets the user delete them. It has a main window, a menu bar item, a settings window and one modal sheet. The user is a developer or power user who wants space back without risking their files. The tone is calm, plain and trustworthy: this app deletes files, so clarity beats decoration.

## Design constraints

- Native macOS feel: system font (SF Pro), standard window chrome, light and dark appearance, respects the user's accent color.
- Compact density. A list of 10 to 15 rows should fit in the main window without scrolling at 680 × 620.
- One accent color. Destructive styling (red) is reserved for the final Delete button and for errors. Orange is for warnings (re-download, blocked, restart).
- Never rely on color alone: icons and text carry state.
- Sizes use tabular (monospaced) digits so columns line up.
- Window sizes: main 680 × 620 (min 560 × 480), sheet 560 × 520, settings 420 wide, menu bar menu is a standard macOS menu.

## Screens

### 1. Main window

Top to bottom:

1. **Header**: two figures and a bar.
   - Left: label "Free space", figure "31.4 GB".
   - Right: label "Reclaimable", figure "28.2 GB".
   - A full-width progress bar showing disk used (e.g. 87%).
   - Below it, a row: "Scanned 2 minutes ago" on the left, the **Scan now** button on the right (shows a small spinner and "Scanning…" while running).
2. **Restart banner** (conditional, see component): shown after a clean until dismissed.
3. **Target list**: three sections, each sorted by size, largest first: *Known targets*, *Other app caches* (found automatically, app installed) and *Leftovers* (app removed or no matching app). The *Leftovers* header has a **Select all** text button. Empty sections are hidden.
4. **Footer**: left "3 selected · 18.4 GB" (or "Select what to clean"), right the primary button **Clean selected…**.

### 2. Clean sheet (modal), three phases

- **Confirming**: title "Delete these files?", subtitle "Files are deleted permanently, not moved to the Trash.", a scrolling list of preview cards, buttons **Cancel** and **Delete 18.4 GB** (destructive, default).
- **Running**: centered spinner and "Cleaning…".
- **Done**: title "Done", a large figure "Freed 17.9 GB", a list of results (icon, name, detail, freed size), the restart banner, and a **Close** button.

### 3. Manual-target popover

Opens from the terminal icon on a manual row. Shows the target name, its note, the command in a monospaced box and a **Copy** button that turns into "Copied".

### 4. Menu bar item

Menu bar shows a drive icon and the free space ("31 GB"). Its menu: "Free space: 31.4 GB", "Reclaimable: 28.2 GB", separator, "Scan now" (or "Scanning…"), "Open Tobias", separator, "Quit Tobias".

### 5. Settings window

Grouped form: "Scan every" (1, 3, 6, 12, 24 hours), toggle "Open Tobias at login", toggle "Notify me when free space is low", optional red error line, button "Show data folder".

### 6. First-run / empty states

- Before the first scan finishes: rows appear with no size yet and the header reads "Not scanned yet".
- Nothing to clean: footer says "Select what to clean" and the button is disabled; every row reads "Nothing to clean".

## Components and states

### Target row

Leading control, then a block with title line, size bar and a detail line.

- **Leading control**: checkbox (selectable) · lock icon (blocked) · terminal icon button (manual) · disabled checkbox (nothing to clean or not found).
- **Title line**: label (medium weight), optional badge "Downloads again" (orange) for `redownloads` targets, optional neutral grey badge "App removed" or "No matching app" on leftovers, size on the right in monospaced digits.
- **Size bar**: thin capsule, filled in proportion to the largest row.
- **Detail line**: the target's note, or a state message (see copy deck).
- **States**: default, selected, hover, disabled/dimmed (nothing to clean, not found), blocked, manual.

### Free-space header, scan button, footer bar

States: idle, scanning (spinner, button disabled), never scanned.

### Restart banner

Orange tint, an icon, title "Restart your Mac", body text, and a **Dismiss** button. Persists across launches until dismissed.

### Preview card (in the sheet)

Title and total size, optional orange warning line for re-download targets, the command in monospace for tool-based targets, up to 8 largest items (shortened path with the middle truncated, size on the right), and conditional lines:
- Orange: "Quit first: com.spotify.client" with a **Quit app** button.
- Red: "Not allowed: …" when the guard rejects a path.

### Result row

Icon by status: cleaned (green check), nothing to do (grey minus), blocked (orange hand), manual (terminal), failed (red triangle). Name, detail text, freed size on the right.

## Example data (use these in the mockups)

| Label | Size | Risk | Note |
|---|---|---|---|
| Claude Desktop VM | 11.9 GB | Downloads again | Sandbox image for code execution. Downloads again if you use the feature. Quit Claude first. |
| Spotify cache | 4.8 GB | | Cached songs and artwork. Quit Spotify first. |
| pnpm store | 3.9 GB | | Removes only packages no project uses. Runs pnpm store prune. |
| Yarn cache | 2.1 GB | | Downloaded packages. Rebuilt as you install. |
| Arc browser cache | 2.0 GB | | Web cache only. Bookmarks and history are not touched. Quit Arc first. |
| Notion cache | 1.7 GB | | Page content already synced to the cloud. Quit Notion first. |
| Homebrew cache | 506 MB | | Old downloads and outdated versions. Runs brew cleanup. |
| VS Code caches | 443 MB | | Extension packages and compiled caches. Quit VS Code first. |
| npm cache | 340 MB | | Downloaded packages. Rebuilt as you install. |
| System logs | 175 MB | Manual | Root-owned. Find the biggest file, then truncate it yourself in Terminal. Tobias never runs sudo. |
| Go build cache | 45 KB | | The first build afterwards is slower. |
| zen cache | 661 MB | No matching app | No installed app matches this name. It may be left from a removed app or belong to a command-line tool; it is rebuilt if still used. (section: Leftovers) |
| Dia cache | 1.9 GB | | Cache of Dia. Rebuilt by the app. Quit it first. (section: Other app caches) |
| Xcode DerivedData | not found | | Not found on this Mac |

A blocked example: "Mail attachments" with the lock icon and "Grant Full Disk Access to Tobias in System Settings → Privacy & Security."

## Copy deck (exact strings)

Buttons and labels: Scan now · Scanning… · Clean selected… · Cancel · Close · Copy · Copied · Quit app · Dismiss · Delete · Show data folder · Open Tobias · Quit Tobias.

Header and list: Known targets · Other app caches · Leftovers · Select all · App removed · No matching app · Free space · Reclaimable · Not scanned yet · "Scanned {relative time}" · Select what to clean · "{n} selected" · Blocked · Manual · Nothing to clean · Not found on this Mac · Downloads again · Rebuilt automatically.

Hints: "Grant Full Disk Access to Tobias in System Settings → Privacy & Security." · "Needs administrator rights. Tobias never runs sudo; run this yourself in Terminal."

Sheet: Delete these files? · Files are deleted permanently, not moved to the Trash. · "This will have to be downloaded again if you use it." · Cleaning… · Done · "Freed {size}" · Not allowed · "Quit first: {apps}".

Restart banner: **Restart your Mac** · "The System Data figure in System Settings only updates after a restart. Free space shown here is the reliable number."

Settings: Settings · Scan every · "{n} hours" · Open Tobias at login · Notify me when free space is low.

All strings live in `Sources/Tobias/Strings.swift`.

## Tokens to return

Return values for light and dark appearance so they can be dropped into `Sources/Tobias/Theme.swift`:

- **Palette**: accent, bar fill, bar track, secondary text, warning (orange), destructive (red), success (green), surface (card background).
- **Spacing**: xs, s, m, l, xl (currently 4, 8, 12, 16, 24).
- **Radius**: small, medium (currently 4, 8).
- **Typography**: title, row title, caption, monospaced caption, large figure.

## Deliverables wanted from the design

1. Main window with the example data, light and dark.
2. The three phases of the clean sheet.
3. Row states: default, selected, blocked, manual, disabled.
4. Restart banner.
5. Menu bar menu and settings window.
6. The token table above, filled in.
7. An app icon (1024 × 1024) that fits a utility app.
