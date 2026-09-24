# Scenes

Scenes is an early macOS menu-bar workspace manager. The current slice is a
native-window control proof: it lists eligible windows and exposes minimal
move, resize, raise/focus, restore, and event-observation controls.

## Requirements

- macOS 13 or newer
- Xcode command-line tools with Swift 6
- Accessibility permission for the built `Scenes` executable

## Build and run

```sh
swift build
swift run Scenes
```

Open the rectangle-group icon in the macOS menu bar. Choose **Request
Accessibility Permission**, approve Scenes in **System Settings → Privacy &
Security → Accessibility**, then return to the menu and refresh. Select a window
under its app name before using the control actions.

Run the lightweight automated check with:

```sh
swift test
```

For a reproducible native smoke test, open two disposable windows from one app,
then run `swift run Scenes --smoke <app-name>`. The command moves, resizes,
focuses, minimizes, restores, and closes the first window while asserting that
the second is unchanged. Do not target windows you need to keep open. Use
`swift run Scenes --diagnose` for read-only permission and eligibility output.

The deployment target is macOS 13. This keeps the proof broadly runnable while
using only public AppKit, Core Graphics, and Accessibility APIs.

## Current native boundary

- Live identity is the selected `AXUIElement`, not an app/title pair. Duplicate
  window titles are presented separately and controlled independently.
- Visible eligibility is conservative: an Accessibility window must match a
  current-Space, on-screen Core Graphics window by PID and bounds.
- Native-fullscreen windows are excluded using `AXFullScreen`.
- Public APIs do not expose a minimized window's Space. Minimized windows remain
  listed so restoration can be tested, with that uncertainty shown in the menu.
  Scenes does not switch Spaces itself.
- Failed or unsupported Accessibility operations are reported in the menu and
  are not retried continuously.

See [the native validation record](docs/native-window-validation.md) for the
actual Mac smoke-test results and limitations.
