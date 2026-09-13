# Research, Mac cleaners and disk maps

Date: 2026-09-13 · Author: dunebru

## What the paid apps actually do

### CleanMyMac (MacPaw), from $3.33/mo subscription, macOS 11+
Modules: Smart Care, System Junk, Space Lens, Large & Old Files, Uninstaller (with leftovers), Malware, Privacy, Maintenance, Optimization (login items, launch agents), Shredder, Updater, Extensions, Mail attachments, Trash bins.

System Junk categories (official KB): Broken Login Items · Broken Preferences · Deleted Users · Document Versions (keeps first+last) · Downloads (broken Safari downloads, Slack files > 1 month) · iOS Device Backups (keeps newest) · Language Files · Old Updates · System Cache Files · System Log Files · Universal Binaries (lipo) · Unused Disk Images · User Cache Files (Spotify + Gradle excluded by default) · User Log Files · Xcode Junk (DerivedData + indices; excludes Module Cache, Archives, Device Support, simulators by default).

Space Lens: bubbles sized by folder size, click to drill down, sidebar tree, drag items to remove. Scans internal, external or a chosen folder.

### DaisyDisk, $9.99 once, macOS 10.13+
Sunburst ("flower"): rings = folder depth, petal width = size, colored petals = folders, grey = files, purple = restricted (needs admin scan), semi-transparent = merged tiny items, virtual segments for purgeable space, other volumes and "still hidden". Hover shows size + path in sidebar; click drills in; click center goes up; breadcrumbs. Collector at bottom: drag items in, delete the pile once. ⌘-click reveals in Finder; Space previews. Scans 1 TB in ~37 s.

### Pearcleaner, free, MIT, on hold
Swift/SwiftUI, macOS 13+. Uninstaller with leftover search (Application Support, Caches, Preferences, Containers, Group Containers, Saved State, Logs, HTTPStorages, WebKit, LaunchAgents), development-environment caches, lipo, Homebrew, Finder extension. Needs Full Disk Access; privileged helper for system folders.

### OpenDisk, free, MIT, macOS 26 only
Sunburst analyzer. `getattrlistbulk(2)` + `searchfs(2)`, 4–8 workers, 1 TB cold scan 17 s. Handles APFS volume groups, firmlinks, purgeable. Stops at mount points and snapshot volumes.

## Criticism to design against
"Running CleanMyMac's System Junk scanner is a bad idea" (studioncreations): it deletes all system + user logs and every crash report, which Apple support needs for diagnosis, for ~1 GB on a 10-year-old machine; caches regenerate anyway. → Broom leaves system logs and crash reports alone by default and explains each category.

## Where the space really goes (macOS "System Data")
`~/Library/Caches` · `~/Library/Logs` · `~/Library/Developer/Xcode/DerivedData`, `Archives`, `iOS DeviceSupport`, CoreSimulator caches · `~/Library/Application Support/MobileSync/Backup` (iOS backups) · `~/Library/Containers/com.apple.mail/.../Mail Downloads` · Time Machine local snapshots (`tmutil listlocalsnapshots /`) · `/Library/Application Support/com.apple.idleassetsd/Customer` (aerial screensavers, GBs) · package caches: `~/.npm`, `~/.cache` (pip, yarn, pnpm, uv), `~/.cargo/registry`, `~/.gradle/caches`, `~/Library/Caches/Homebrew`, `~/Library/Caches/CocoaPods`, `~/.docker` · Downloads: `.dmg`, `.pkg`, `.zip` installers · orphaned app folders.

On this machine today: Caches 2.2 GB, DerivedData 1.5 GB, ~/.cache 2.6 GB, ~/.npm 439 MB, Homebrew 117 MB.

## Fast scanning on macOS
- `getattrlistbulk(2)`: one syscall returns dozens–hundreds of entries with attributes. Request `ATTR_CMN_RETURNED_ATTRS | ATTR_CMN_ERROR | ATTR_CMN_NAME | ATTR_CMN_OBJTYPE | ATTR_CMN_MODTIME | ATTR_CMN_FILEID` + `ATTR_FILE_LINKCOUNT | ATTR_FILE_ALLOCSIZE`. 128 KB buffer. Fields are 4-byte aligned in bit order; check RETURNED_ATTRS before reading each.
- `fts` is fast for names only; `getattrlistbulk` wins when attributes are needed (Tsai/Tempel benchmarks).
- Use **allocated** size (matches `du`, respects compression). APFS clones are over-counted per file; accepted (DaisyDisk does the same).
- Hardlinks: dedupe by (device, fileID) only when link count > 1.
- APFS serializes directory reads: 4–8 workers is the sweet spot. dumac (Rust) scans 409k files in 0.5 s.
- Don't follow symlinks. Skip `/Volumes`, `/System/Volumes` (firmlinks already expose Data at `/`), `/dev`, `/Network`, `/.vol`.

## Space accounting
- `URL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey])` → used, purgeable ≈ importantUsage − available.
- Local snapshots: `tmutil listlocalsnapshots /`; delete: `tmutil deletelocalsnapshots <date>` (admin); thin: `tmutil thinlocalsnapshots / <bytes> 4`. APFS takes ~1–2 min to update free space after.
- Full Disk Access: needed for `~/Library/Mail`, Safari, Messages, Time Machine metadata. Detect by attempting to list `~/Library/Safari`; guide to System Settings → Privacy & Security → Full Disk Access. Requires a stable code signature (ad-hoc is enough) so TCC remembers the app.

## Sunburst rendering
Swift Charts `SectorMark` can build rings (innerRadius/outerRadius ratios per level, angularInset) but hit-testing and per-segment hover are awkward; a SwiftUI `Canvas` with precomputed arcs (node, depth, start/end angle) gives full control: polar hit-test on hover, click-to-zoom, merged "small items" segment, animation via a single interpolated state.

## Sources
- https://macpaw.com/support/cleanmymac-x/knowledgebase/system-junk
- https://macpaw.com/support/cleanmymac/knowledgebase/space-lens
- https://daisydiskapp.com/manual/4/en/Topics/UnderstandingSunburst.html
- https://github.com/alienator88/Pearcleaner
- https://github.com/137137137/OpenDisk
- https://healeycodes.com/maybe-the-fastest-disk-usage-program-on-macos
- https://mjtsai.com/blog/2019/04/22/performance-considerations-when-reading-directories-on-macos/
- https://studioncreations.com/blog/running-cleanmymac-system-junk-scanner-is-a-bad-idea/
- https://cleanmymac.com/blog/clear-system-data-storage-mac
- https://eclecticlight.co/2026/08/24/arent-snapshots-purgeable/
- https://nilcoalescing.com/blog/BuildingASunburstDiagramInSwiftCharts/
