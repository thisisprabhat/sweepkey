# Automation, workflows and insights

← [Index](README.md)

## Combined workflows (one-click recipes)
- **Archive project**: snapshot its secrets, clean its artifacts, optionally zip the whole project and move it to an archive location.
- **Free up X GB**: enter a target; the app proposes the safest set of items that reaches it (stale projects and safe caches first) for review.
- **New-Mac migration**: export the vault plus a list of repos (remote URLs and branches) as a bundle. On the new Mac, clone the repos and restore their secrets.
- **Pre-clean safety pass**: report repos with unpushed commits or stashes before they are archived.

## Monitoring and automation
- **Menu bar extra** with a glass popover: free-space gauge, reclaimable total, "Quick clean safe items", last clean.
- **Low-space alert**: when free space drops below the threshold (`volumeAvailableCapacityForImportantUsage`, default 20 GB), send a notification with a one-tap action to clean safe items.
- **Scheduled jobs** via `NSBackgroundActivityScheduler` and a login item (`SMAppService`): nightly scan, weekly auto-clean of stale projects limited to safe rules, periodic vault snapshots. Each run ends with a summary notification. Settings: `ScheduleSettings`.
- **WidgetKit** desktop and Notification Center widgets for free and reclaimable space.
- **App Intents / Shortcuts / Spotlight**: "Scan Projects", "Clean stale node_modules", "Snapshot secrets", "Free up 20 GB".
- **CLI `cleaner`** on the same core: `scan`, `clean --dry-run`, `vault collect`, `vault restore`, `caches`, `--json` output. Installable via the Homebrew formula.
- **Finder integration**: drop a folder on the Dock icon or window, the Services entry "Scan with Cleaner", and `cleaner://scan?path=` URLs.

## Insights
- **Dashboard**: volume broken into "dev junk vs everything else", top-10 offenders, reclaimable-over-time trend (Swift Charts).
- **Treemap / sunburst** of reclaimable space by project, ecosystem or category.
- **Suggestions**, for example "42 copies of `node_modules` (18 GB): switching to pnpm or Bun would deduplicate them", "uv instead of pip venvs", "12 simulators for unavailable runtimes".
