# Sweepkey brand

**Name.** Sweepkey: it sweeps away what can be rebuilt (build output, dependency folders, tool caches) and keeps the keys (secrets and signing files) safe in the vault.
**Tagline.** Sweep the rebuildable. Keep the keys.

## Icon
`App/AppIcon.icon` is an Icon Composer document (macOS 26 Liquid Glass): a keyhole (the vault) with a mint sweep and two sparkles crossing it, on a night-indigo gradient. Its layers are plain SVGs in `App/AppIcon.icon/Assets/`; open the `.icon` in Icon Composer to adjust glass, shadows or the dark/tinted looks. The menu bar uses `MenuBarIcon` (a one-colour template version) from `App/Assets.xcassets`.

## Colours
| Role | Light | Dark |
|---|---|---|
| Accent (`AccentColor`) | Indigo `#3F49B4` | Mint `#5DE3B8` |
| Icon background | `#3F49B4` → `#141739` | `#333B99` → `#0D0F29` |
| Sweep | Mint `#3EE6B5` → `#D2FFF2` | same |
| Ink (wordmark, text) | `#161A3A` / muted `#5B6290` | n/a |

## Wordmark
"Sweep" in ink and "key" in indigo, set in SF Pro Display Bold with slightly tight tracking (see `dmg-background.svg`).

## Installer
`dmg-background.svg` is the source for the DMG window (660×400 pt); `dmg-background.tiff` is the rendered 1x+2x image that `scripts/make-dmg.sh` uses. After editing the SVG, run `scripts/render-brand.sh`.
