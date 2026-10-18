# You Don't Need That: build brief

A macOS disk-cleaner app with a sense of humor. This brief describes the first screen to build: a **donut-chart drill-down** of where disk space went. The visual reference is `design-reference.html` (an HTML mockup; read it for layout, colors and copy, but build natively, not as a web view).

## Tech choices

- **SwiftUI**, macOS 14+ (needed for Swift Charts `SectorMark` and `chartAngleSelection`).
- **Swift Charts** for the donut: `SectorMark(angle:, innerRadius: .ratio(0.6), angularInset: 1)`.
- Swift concurrency (`async`/`await`, a background actor) for scanning so the UI never blocks.
- **Distribute outside the Mac App Store** (Developer ID + notarization). An App Sandboxed build can't read `~/Library/Caches`, other apps' containers, etc. Some locations (Mail, iOS backups) also need **Full Disk Access**; detect that and show a friendly "grant access" screen linking to System Settings › Privacy & Security › Full Disk Access.

## Screen behaviour

### Overview (default)
- Heading: "Where your space went", subheading "Your home folder, scanned for clutter".
- Left: donut chart, one slice per category, colored per category. Center label: "RECLAIMABLE", total size, "N places".
- Right: legend list, one row per category, sorted largest first: color swatch, name, path (monospace, truncated), size, percent of total.
- Hovering a slice or row: that slice pops out (larger outer radius), others dim to ~45% opacity, center label shows that item's percent, size, name and path.
- Clicking a slice or row → drill into that category.
- Footer note: "Nothing is deleted until you say so. Everything goes to the Trash first."

### Drill-down (one category)
- Title bar shows a **Back** button and breadcrumb "All places / <Category>". Back returns to the overview (also support ⌘[ and Esc).
- Heading "<Category>: <size>", subheading the category's path.
- Donut redraws with one slice per item inside the category (top-level files/folders), in descending shades of the category color. Legend shows each item's name, full path, size, percent.
- Clicking a slice/row toggles selection of that item. Footer shows "<name> · <size> selected" and enables **Show in Finder** (`NSWorkspace.shared.activateFileViewerSelecting`) and **Yeet to Trash** (`FileManager.default.trashItem`, never permanent delete). After trashing, rescan that category.
- Animate the transition between levels (slices growing from the selected slice is ideal; a simple cross-fade is fine for v1).

## Categories (v1)

| Category | Location(s) | Color |
|---|---|---|
| Large Files | Files > 1 GB anywhere under `~` (skip `~/Library`) | #F87171 |
| Xcode Junk | `~/Library/Developer/Xcode/DerivedData`, `iOS DeviceSupport`, `Archives` | #38BDF8 |
| Caches | `~/Library/Caches/*` | #818CF8 |
| iOS Backups | `~/Library/Application Support/MobileSync/Backup/*` (needs FDA) | #F472B6 |
| Old Downloads | `~/Downloads`, items not modified in 6+ months | #C084FC |
| Trash | `~/.Trash` | #A1A1AA |
| Mail Attachments | `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads` (needs FDA) | #4ADE80 |
| Logs | `~/Library/Logs/*` | #FBBF24 |

Keep this list in one place (e.g. a `Category` enum or config) so categories are easy to add.

## Scanning

- Size = allocated size on disk: enumerate with `FileManager.enumerator(at:includingPropertiesForKeys:[.totalFileAllocatedSizeKey, .isDirectoryKey, .contentModificationDateKey])` and sum. Don't follow symlinks; skip packages' internals only when it makes sense.
- Scan categories concurrently with a `TaskGroup`; publish results as each finishes so the chart fills in progressively.
- Show a scanning state (spinner + "Judging your files…") and a Rescan button.
- Skip unreadable paths silently but count them; if a category is fully blocked, show it as "Needs Full Disk Access" instead of a size.

## Visual style (from the mockup)

- Dark: window background #141518, title bar #101114, dividers #26282D, primary text #ECEDEF, secondary text #9A9CA3.
- Accent lime #C6F24E (dark text #141518 on it) for the center size and the Trash button.
- Fonts: Space Grotesk for text, JetBrains Mono for sizes and paths (bundle them, or fall back to SF Pro / SF Mono).
- Sizes formatted with `ByteCountFormatter` (`.file` style).

## Suggested structure

```
YouDontNeedThat/
  App/YouDontNeedThatApp.swift
  Models/Category.swift, ScanItem.swift
  Scanning/DiskScanner.swift        (actor)
  Views/RootView.swift              (NavigationStack, overview ⇄ drill-down)
  Views/DonutChartView.swift        (Swift Charts, hover + selection)
  Views/LegendRow.swift
  Views/FooterBar.swift
  Theme/Theme.swift                 (colors, fonts)
```

## Out of scope for v1
Verdicts per file, scheduled scans, menu-bar extra, uninstalling apps.
