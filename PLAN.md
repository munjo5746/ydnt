# You Don't Need That — MVP plan

Personal-use macOS disk cleaner. Free, no payment wall, one screen that answers
"where did my space go?" and lets you trash it. This file replaces HANDOFF.md and
design-reference.html once the project is scaffolded, so the spec lives here.

## MVP definition

Done when, running on this Mac:

1. App launches, scans the 8 categories below, and fills the donut progressively.
2. Hover/click a slice or legend row → drill into the category.
3. Select an item in a category → **Show in Finder** / **Yeet to Trash** (trash only, never unlink) → category rescans.
4. Categories that need Full Disk Access show "Needs Full Disk Access" with a link to System Settings instead of a bogus 0 B.
5. Installable on any of my Macs from a zip attached to a **private GitHub release**. Developer ID signed + notarized, so install is unzip → drag to /Applications → open. No Gatekeeper dialog (see Phase 5).

## Toolchain (checked 2026-10-18)

- Xcode 26.2 / Swift 6.2, macOS 26.2. Deployment target macOS 14.
- No xcodegen installed. Decision: `brew install xcodegen`, keep a `project.yml`, never hand-edit the .xcodeproj. Alternative is creating the project in the Xcode GUI once; xcodegen keeps the repo diff-friendly.
- Signing: paid Apple Developer account available. Only an "Apple Development" cert (team V3CD35TG78) is in this keychain today; no **Developer ID Application** cert yet. One-time setup in Phase 5. Confirm BWVJK738Z7 is the paid team, not a free personal team, before putting it in `project.yml`.
- A stable signing identity matters beyond Gatekeeper: macOS ties the Full Disk Access grant to the code signature. Developer ID gives that for free.
- `gh` is logged in as munjo5746. Releases go to a private repo.
- App Sandbox **off** (must read ~/Library/Caches, other containers). Hardened runtime on.
- Swift 6 language mode, strict concurrency. Data types are `Sendable` structs; scanner is an `actor`. No fights expected.

## Phases

### 0. Scaffold (~30 min)
- `project.yml` → `YouDontNeedThat.xcodeproj`, one macOS app target, bundle id `com.edwardchung.ydnt`, `Info.plist` minimal, entitlements file with sandbox disabled.
- Empty `YouDontNeedThatApp` + `RootView` showing "hello". Build, run. Commit, `git init`.

### 1. Models + fake data (~30 min)
- `Category` enum: 8 cases, each with `name`, `roots: [URL]`, `color`, `needsFullDiskAccess`, `rule` (how to pick items, see table). One place to add categories.
- `ScanItem { name, url, bytes }`, `CategoryResult { category, items, status: .scanned | .needsAccess | .scanning }`.
- `Fixtures.fake`: the exact data from the HTML mockup (Windows11_ARM.vmdk 24.5 GB etc.). Used by the app in Phase 2 and by SwiftUI previews forever.

### 2. UI on fake data (~half day) ← first visible checkpoint
- `RootView`: `@State var open: Category?`, `@State var hovered`, `@State var picked`. Overview when nil, drill-down when set. No NavigationStack; cross-fade via `.transition(.opacity)`.
- `DonutChartView`: Swift Charts `SectorMark(angle:, innerRadius: .ratio(0.6), angularInset: 1)`.
  - Hover: `.chartAngleSelection(value:)` → map angle to item by cumulative bytes.
  - Pop-out: `outerRadius: .ratio(active ? 1.0 : 0.94)`, others `.opacity(0.45)`.
  - Click: `onTapGesture` on the chart acts on the currently hovered item (hover always precedes click on macOS). Avoids hand-computing tap angles.
  - Drill-down slice colors: category color at opacities `[1, .8, .64, .5, .4, .32, .25]` cycling.
- Center label overlay (ZStack, not chart annotation): kicker / size in accent / name / path. Switches to hovered item.
- `LegendRow`: swatch · name + mono path · size + percent. Hover and click shared with chart via the same `hovered`/`picked` state.
- Title bar: breadcrumb "All places / <Category>", Back button in drill-down. `⌘[` and `Esc` go back.
- `FooterBar`: note text; in drill-down two buttons, disabled until something is picked.
- `Theme`: the color tokens below. Fonts: SF Pro + SF Mono (`.monospaced()`). Skip bundling Space Grotesk/JetBrains Mono; add if the look bothers you.
- Sizes via `ByteCountFormatter` `.file`.

### 3. Real scanner (~half day)
- `actor DiskScanner`, `func scan(_ c: Category) async -> CategoryResult`.
- Items per category (the "rule" column). Size each item with `FileManager.enumerator(at:includingPropertiesForKeys:[.totalFileAllocatedSizeKey,.isDirectoryKey,.contentModificationDateKey], options:[.skipsHiddenFiles? no — keep hidden], ...)` summing allocated size, not following symlinks.
- Unreadable entries: skip, count. If the root itself fails with EPERM/EACCES and the category `needsFullDiskAccess` → `.needsAccess`.
- `RootView` kicks off a `TaskGroup` over `Category.allCases` on appear and on Rescan; each result lands in `results[category]` as it finishes so the chart grows. Scanning state: spinner + "Judging your files…".
- Large Files is the slow one (walks all of ~ minus ~/Library). Acceptable for MVP; note progress isn't shown per file. ponytail: upgrade to a cached index if it takes > ~30 s on this machine.

### 4. Actions (~2 h)
- Show in Finder: `NSWorkspace.shared.activateFileViewerSelecting([url])`.
- Yeet to Trash: `FileManager.default.trashItem(at:resultingItemURL:)`, then rescan that category only. Error → simple alert.
- Trash category: Yeet is meaningless there. Disable the button and change the footer to "Empty the Trash from Finder." No permanent delete in v1.
- FDA screen: button opens `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`. Rescan after the user returns.

### 5. Build + distribute to my other Macs (~1 h incl. one-time setup)

Easiest for the installer = Developer ID + notarization: the app opens like any other download. Mac App Store is ruled out (needs sandbox, which blocks ~/Library/Caches).

One-time setup on this Mac:
1. Xcode › Settings › Accounts › paid team › Manage Certificates › + › **Developer ID Application**. (If one already exists on another Mac, export it as .p12 and import here instead; Apple caps these at 5 per account.)
2. App-specific password at appleid.apple.com, then
   `xcrun notarytool store-credentials ydnt --apple-id <email> --team-id <TEAM> --password <app-specific>`.
3. `project.yml`: `DEVELOPMENT_TEAM: <TEAM>`, `CODE_SIGN_IDENTITY: "Developer ID Application"`, `ENABLE_HARDENED_RUNTIME: YES`, `MARKETING_VERSION`.

`Scripts/release.sh` (one command per release):
1. `xcodebuild archive` (Release).
2. `xcodebuild -exportArchive` with `ExportOptions.plist` `method: developer-id`.
3. `ditto -c -k --keepParent` → `YouDontNeedThat-<version>.zip`.
4. `xcrun notarytool submit <zip> --keychain-profile ydnt --wait` (a few minutes).
5. `xcrun stapler staple YouDontNeedThat.app`, re-zip so the staple ships inside.
6. `gh release create v<version> <zip>` on the **private** repo.

Install on another Mac (README.md): download zip from the release (GitHub login = not public), unzip, drag to /Applications, open. Grant Full Disk Access when asked; it survives updates.

Updates: download the new zip, replace the app. No Sparkle. Add when manual replacing gets annoying.

Requirements on the other Mac: macOS 14+. No Xcode, no Apple ID sign-in.

Not doing: Mac App Store, public download page, auto-update.

## Categories

| Category | Roots | Items (drill-down) | Color | FDA |
|---|---|---|---|---|
| Large Files | `~` minus `~/Library` | files > 1 GB, recursive | #F87171 | no |
| Xcode Junk | `~/Library/Developer/Xcode/{DerivedData, iOS DeviceSupport, Archives}` | the 3 roots | #38BDF8 | no |
| Caches | `~/Library/Caches` | top-level entries | #818CF8 | no |
| iOS Backups | `~/Library/Application Support/MobileSync/Backup` | top-level entries | #F472B6 | yes |
| Old Downloads | `~/Downloads` | top-level entries not modified in 6+ months | #C084FC | no |
| Trash | `~/.Trash` | top-level entries | #A1A1AA | no |
| Mail Attachments | `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads` | top-level entries | #4ADE80 | yes |
| Logs | `~/Library/Logs` | top-level entries | #FBBF24 | no |

## Visual tokens

Window #141518 · title bar #101114 · footer #111215 · dividers #26282D · row hover #1C1E23 · row active #22242A
Text #ECEDEF · secondary #9A9CA3 · tertiary #8A8C93 · accent lime #C6F24E (text on it #141518) · button border #3A3C43

Copy: "Where your space went" / "Your home folder, scanned for clutter" / center kicker "RECLAIMABLE", "N places" /
"Click a slice to look inside." / "Click a slice to select it." / "Nothing selected. Pick a slice you don't need." /
"<name> · <size> selected" / "Nothing is deleted until you say so. Everything goes to the Trash first." / "Judging your files…"

## Deliberately skipped

- Bundled web fonts → SF. Add when the look matters.
- Slice-grow transition between levels → cross-fade.
- Per-file verdicts, scheduled scans, menu-bar extra, app uninstaller, Empty Trash, permanent delete.
- Mac App Store, public download page, Sparkle auto-update.
- Tests: one `assert`-style check for the angle→item mapping and the byte summing; nothing else.

## Layout

```
YouDontNeedThat/
  App/YouDontNeedThatApp.swift
  Models/Category.swift          enum + table above
  Models/ScanItem.swift          ScanItem, CategoryResult, Fixtures.fake
  Scanning/DiskScanner.swift     actor
  Views/RootView.swift           state, overview ⇄ drill-down, keyboard
  Views/DonutChartView.swift
  Views/LegendRow.swift
  Views/FooterBar.swift
  Theme/Theme.swift
Scripts/release.sh                 archive → export → notarize → staple → zip → private GitHub release
ExportOptions.plist                method: developer-id
project.yml
README.md                          install steps for other Macs
```
