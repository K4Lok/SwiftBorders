# SwiftBorders

A lightweight macOS menu-bar tool that draws a colored border around the **active window** — a durable, public-API alternative to [JankyBorders](https://github.com/FelixKratz/JankyBorders) that keeps working across macOS upgrades.

Built for macOS 26 (Tahoe) and designed to play well with tiling window managers like **yabai**.

## Why

JankyBorders is great but relies on the private `SkyLight` framework, so it tends to break on macOS upgrades. SwiftBorders uses the **public Accessibility API** + transparent overlay windows for everything load-bearing (focus tracking, geometry, drawing). The trade-off: a touch more latency on fast window drags, in exchange for not breaking every OS update.

The one exception is reading a window's exact corner radius — the public API doesn't expose it, so (like JankyBorders) we ask `SkyLight` via a private call. It's resolved with `dlsym` and fully guarded: if that symbol ever disappears on a future macOS, the border falls back to a configured radius and the app keeps working — it just loses pixel-perfect corners.

## Features

- Border around the currently focused window, tracked via the system-wide Accessibility API (works under yabai)
- Optional dimmer borders on inactive windows
- Multi-monitor aware (one overlay per display — correct behavior with "Displays have separate Spaces")
- Live-reloading JSON config — edit and see changes instantly
- Menu-bar settings GUI (color wells + sliders)
- Pixel-accurate corners: exact per-window radius read from the WindowServer, drawn as a continuous (squircle) curve to match macOS
- Style options: width, corner smoothing, opacity, dashed, glow, outward bias
- Launch at login

## Requirements

- macOS 14+ (developed/tested on macOS 26 Tahoe)
- Swift 6 toolchain (Xcode 16+ / Swift command-line tools)

## Build & run

```bash
git clone https://github.com/K4Lok/SwiftBorders.git
cd SwiftBorders
swift run
```

On first launch macOS will ask for **Accessibility** permission: System Settings ▸ Privacy & Security ▸ Accessibility → enable **SwiftBorder**. It starts automatically once granted.

A dashed-rectangle icon appears in the menu bar — click it for settings.

## Packaging & distribution

SwiftBorder reads other apps' windows via the Accessibility API and a private
`SkyLight` call, so it **cannot ship on the Mac App Store** (which requires the
sandbox). It's distributed directly, signed with a **Developer ID** certificate
and **notarized** — the same path JankyBorders, Rectangle, and BetterDisplay use.

```bash
./build-app.sh     # compiles release, assembles dist/SwiftBorder.app, code-signs
./notarize.sh      # notarizes + staples the app, then builds + notarizes the DMG
```

This produces `dist/SwiftBorder.dmg` (drag-to-Applications installer) and
`dist/SwiftBorder.zip`. See [RELEASE.md](RELEASE.md) for the full checklist.

`build-app.sh` auto-detects your *Developer ID Application* certificate. One-time
setup before notarizing — store credentials in the keychain (see the header of
`notarize.sh` for details):

```bash
xcrun notarytool store-credentials "SwiftBorder-Notary" \
    --apple-id "you@example.com" --team-id "YOURTEAMID" \
    --password "app-specific-password"
```

The icon is generated from `Packaging/make-icon.swift` → `Packaging/AppIcon.icns`.

## Configuration

Settings live at `~/Library/Application Support/SwiftBorder/config.json` and reload live. Colors use JankyBorders-style `0xAARRGGBB` hex.

| Key | Meaning |
|---|---|
| `width` | Border thickness (pt) |
| `cornerRadius` | Fallback radius for toolbar windows (only used if the WindowServer lookup is unavailable) |
| `plainCornerRadius` | Fallback radius for plain windows (only used if the WindowServer lookup is unavailable) |
| `cornerSmoothing` | Continuous-corner smoothing 0–1 (0 = circular, ~1.0 = macOS Tahoe) |
| `activeColor` | Focused-window border color |
| `drawInactive` / `inactiveColor` | Borders on non-focused windows |
| `opacity` | Border opacity (0–1) |
| `style` | `solid` or `dashed` |
| `glow` / `glowRadius` | Soft glow around the border |
| `outwardBias` | How far the stroke sits outside the window (0–1) |
| `launchAtLogin` | Auto-start on login |

## Known limitations

- The exact corner radius comes from a guarded private `SkyLight` call. For native windows this is pixel-perfect; some custom-drawn apps (e.g. Telegram) render a slightly larger *visible* corner than the OS reports, so the border can sit a few points tight on those — the same limitation JankyBorders has. Fullscreen windows are squared automatically.
- Borders track focus with a few frames of latency on fast drags (inherent to the Accessibility API).

## Troubleshooting

**No border appears, and the Accessibility toggle already looks ON.**
macOS ties an Accessibility grant to the app's *code signature*. If a build with a
different signature (e.g. a local unsigned build, or a re-signed release) was
granted earlier, the toggle stays on but the grant no longer matches — so the app
is silently denied. Click the menu-bar icon and press **Reset & re-grant** (shown
in the warning banner when access is missing), then grant again. The equivalent
from the terminal is:

```bash
tccutil reset Accessibility com.swiftborder.app
```

Then relaunch and grant once. Borders appear immediately — no restart needed.

## Debugging

Run with `SWIFTBORDER_DEBUG=1 swift run` to print focus/render/display diagnostics to stderr.
