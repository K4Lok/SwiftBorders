# SwiftBorders

A lightweight macOS menu-bar tool that draws a colored border around the **active window** — a durable, public-API alternative to [JankyBorders](https://github.com/FelixKratz/JankyBorders) that keeps working across macOS upgrades.

Built for macOS 26 (Tahoe) and designed to play well with tiling window managers like **yabai**.

## Why

JankyBorders is great but relies on the private `SkyLight` framework, so it tends to break on macOS upgrades. SwiftBorders deliberately uses the **public Accessibility API** + transparent overlay windows. The trade-off: a touch more latency on fast window drags, in exchange for not breaking every OS update.

## Features

- Border around the currently focused window, tracked via the system-wide Accessibility API (works under yabai)
- Optional dimmer borders on inactive windows
- Multi-monitor aware (one overlay per display — correct behavior with "Displays have separate Spaces")
- Live-reloading JSON config — edit and see changes instantly
- Menu-bar settings GUI (color wells + sliders)
- Style options: width, per-window-type corner radius, opacity, dashed, glow, outward bias
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

## Configuration

Settings live at `~/Library/Application Support/SwiftBorder/config.json` and reload live. Colors use JankyBorders-style `0xAARRGGBB` hex.

| Key | Meaning |
|---|---|
| `width` | Border thickness (pt) |
| `cornerRadius` | Radius for windows **with** a toolbar |
| `plainCornerRadius` | Radius for windows **without** a toolbar (Terminal, utilities) |
| `activeColor` | Focused-window border color |
| `drawInactive` / `inactiveColor` | Borders on non-focused windows |
| `opacity` | Border opacity (0–1) |
| `style` | `solid` or `dashed` |
| `glow` / `glowRadius` | Soft glow around the border |
| `outwardBias` | How far the stroke sits outside the window (0–1) |
| `launchAtLogin` | Auto-start on login |

## Known limitations

- macOS Tahoe gives windows non-uniform corner radii and the exact value isn't exposed by the public API, so corners are matched heuristically (toolbar vs plain) rather than pixel-perfectly. Fullscreen windows are squared automatically.
- Borders track focus with a few frames of latency on fast drags (inherent to the Accessibility API).

## Debugging

Run with `SWIFTBORDER_DEBUG=1 swift run` to print focus/render/display diagnostics to stderr.
