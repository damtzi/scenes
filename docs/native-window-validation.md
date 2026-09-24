# Native window validation

Machine: Apple silicon Mac, macOS 27.2 (build 26B5091g), Swift 6.4.

Validated on 2026-09-24 with two disposable TextEdit windows (`a.txt` and
`b.txt`) after granting Accessibility to `.build/debug/Scenes`:

- [x] Permission state changed from denied to trusted only after user approval.
  The denied code path returns an error and disables window controls.
- [x] Both same-app windows appeared separately by retained `AXUIElement`.
- [x] Moving and resizing `a.txt` left `b.txt` geometry unchanged.
- [x] Raising focused `a.txt`; focus-change notifications were received.
- [x] Minimize and restore changed native state and emitted both notifications.
- [x] Closing `a.txt` emitted the destruction notification.
- [x] `b.txt` remained open, usable, and geometrically unchanged.

Commands and result:

```text
$ .build/debug/Scenes --diagnose
Accessibility trusted: true
Eligible windows: 6
…
TextEdit  a.txt  minimized=false
TextEdit  b.txt  minimized=false

$ .build/debug/Scenes --smoke TextEdit
PASS move selected window; sibling unchanged
PASS resize selected window; sibling unchanged
PASS raise and focus selected window
PASS minimize and restore selected window
PASS observed focus/minimize/restore/closure events
PASS same-app sibling remained usable and unchanged
```

Native-fullscreen windows are excluded by their Accessibility fullscreen state.
Non-minimized other-Space windows are excluded because the Core Graphics
on-screen list contains only the current Space; the proof never switches Spaces
to retrieve one. Enumeration used these real APIs, but this smoke run did not
create an excluded second-Space window or enter native fullscreen; those cases
remain manual checks before depending on broader compatibility.

## API findings

- `AXUIElement` is sufficient runtime identity for independent same-app control;
  title uniqueness is unnecessary. It is not a durable identity across closure
  or relaunch.
- Accessibility exposes movement, size, minimized state, raise, main/frontmost,
  fullscreen state, and notifications, subject to each app/window supporting
  the attribute or action.
- Core Graphics can enumerate on-screen windows in the current Space. Public
  APIs provide no Space identifier for minimized windows, so their current-Space
  membership cannot be established reliably. The proof labels this limitation
  and does not claim otherwise.
- PID plus rounded bounds is used only to establish current-Space visibility;
  the retained Accessibility element performs control. Identically positioned
  same-process windows are therefore ambiguous only at the visibility-filter
  boundary, not after selection.
