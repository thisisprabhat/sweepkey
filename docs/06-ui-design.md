# UI design

← [Index](README.md)

Liquid Glass and macOS HIG guidelines.

## Structure
- `NavigationSplitView` sidebar (automatically glass on 26): Dashboard, Projects, Global Caches, Vault, History, Rules, plus Settings.
- Content uses a sortable, multi-select `Table` with a reclaimable-size column and an `.inspector` panel for details: paths, rule, regenerate command, git info.
- `.searchable` filtering, plus filters for ecosystem, risk, age and size.

## Liquid Glass rules
- Glass only on controls and navigation, never on content rows or cards: toolbar `.buttonStyle(.glass)`; the primary Clean action uses `.glassProminent`.
- A floating selection bar inside a `GlassEffectContainer` shows "12 items · 23.4 GB · Clean". Morphing transitions use `glassEffectID`.
- No hand-rolled blur imitations; SF Symbols for all icons.

## Scan and clean flow
Animated progress ring with SF Symbols 7 symbol effects; a confirmation sheet summarizing the run; a short success animation showing space freed.

## Onboarding
1. Welcome
2. Pick scan roots
3. Guided Full Disk Access setup (deep link to System Settings, with re-check)
4. First scan

## Accessibility and polish
Keyboard shortcuts (Cmd-R rescan, Cmd-Delete clean; Space for Quick Look is planned for v1.1), Reveal in Finder, Open in Terminal or editor, VoiceOver labels, Dynamic Type, system accent color, localizable String Catalog.

## Privacy
Everything stays local; no telemetry; secrets leave the machine only when exported.
