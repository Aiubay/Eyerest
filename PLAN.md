# EyeRule: Swift on Mac, Rust + Tauri on Windows

Status: plan only. No code written yet for the Windows app or the camera tracker.

This document replaces the earlier "one Tauri codebase for both OSes" version. The Windows detail in `WINDOWS_PLAN.md` and the research in `RND.md` still apply.

## Decision

- **Mac:** the existing Swift app (`Sources/EyeRule/`) stays the one Mac app. It gains the camera eye tracker natively: AVFoundation for capture, Vision for face landmarks. No Tauri, no web view, no rewrite.
- **Windows 11 x64:** a new app in Rust + Tauri v2, TypeScript/React UI with Fluent UI v9. Built here with `cargo-xwin` for `x86_64-pc-windows-msvc`, then the `.exe` is copied to the PC. No Windows VM.
- **Shared:** the spec, not the source. Same surfaces, same settings pages, same stats semantics, same camera privacy rules. Each platform implements it in its own language.
- **Camera:** Vision on Mac, MediaPipe Face Landmarker on Windows.

## Trade-off

| | One Tauri codebase (dropped) | Swift + Windows Tauri (chosen) |
|---|---|---|
| Mac work | Rewrite the whole working app | Add one feature |
| Mac risk | Panel/notch focus tricks, web-view camera, more memory | Almost none |
| Shared code | Engine, UI, settings, camera | None, spec only |
| Drift | None | Two small engines, two camera paths to keep in step |
| Windows work | Same | Same |

Reason: the rewrite was the largest item with the least visible gain, since the Mac app already works and only needs the camera feature. The cost is two implementations of a small timer engine and two camera paths. Keep the engines small and mirror the same behavior tests on both sides.

## Build and test loop (Mac to PC)

| Step | Where | What |
|---|---|---|
| Unit tests | Mac, native | Rust engine tests; UI previewed in a browser |
| Compile check | Mac | `cargo check --target x86_64-pc-windows-msvc` for Windows-only modules |
| Build | Mac | `cargo-xwin` cross-link of a raw `.exe` (no installer bundle) |
| Run and test | PC | Copy the exe, run it, read the log file |

- One-time Mac setup: `rustup target add x86_64-pc-windows-msvc`, install `cargo-xwin` (it downloads the Windows SDK and CRT once).
- The app logs to `%LOCALAPPDATA%\EyeRule\logs\eye-rule.log`, because no console is attached when you launch the exe.
- Round trips take minutes, so anything platform-independent must be testable on the Mac. Only these need the PC: window styles, hotkeys, idle detection, tray, game and anti-cheat detection, camera, memory numbers.
- The first spike must answer: does a hello-world Tauri exe run on the PC when copied alone? Open points are the WebView2 loader link mode and embedded frontend resources.
- Installers are not needed at first. If one is wanted later, try Tauri's NSIS bundle on the PC built from a copy of the source folder, since cross-bundling from macOS is not supported.
- A `cargo check` only proves the code compiles; it is not a runtime test.
- If round trips get annoying, the same source can be built natively on the PC. That needs the Rust toolchain and Node installed there.

## Windows app

### Stack

| Part | Choice |
|---|---|
| Shell and backend | Rust + Tauri v2 |
| Frontend | TypeScript, React, Vite, Fluent UI React v9 |
| Look | Fluent 2 / WinUI 3 (PowerToys style) with a Mica backdrop |
| Timer engine | Rust, runs with every window closed |
| Windows APIs | The `windows` crate |

Crates and plugins: `tauri` v2, `tauri-plugin-global-shortcut`, `tauri-plugin-notification`, `tauri-plugin-autostart`, `window-vibrancy`, `windows`, `rodio`, `serde` and `serde_json`.

Modules under `src-tauri/src/`:
- `engine.rs`: work and break phases, snooze, stats, streak, prompts. Plain Rust, unit tested on the Mac.
- `settings.rs`: settings and stats storage as JSON in the app data folder.
- `platform/`: window styles, idle, game and anti-cheat detection, sound, each behind a small trait so the engine is tested without Windows.
- `main.rs`: windows, tray, hotkeys, events to the frontend.

Frontend folders: `pill/` (pill and break card, custom black UI, CSS animations), `settings/` (PowerToys-style window), `flyout/` (tray flyout).

Assets: three short generated sounds (Chime, Water drop, Soft, plus Silent), tray icon and `.ico`.

### Surfaces

**Pill.** About 220 x 34 px, black, hanging from the top center of the primary screen. Always on top, never takes focus, hidden from the taskbar and Alt+Tab.
- Left: eye icon (blinks, becomes pause when paused and moon when away). Right: countdown.
- Thin progress line with shimmer. Outline color: cyan (lavender in the evening, periwinkle at night), yellow in the last 5 minutes, orange and pulsing in the last minute ("Break in 45s"), green during a break.
- Click opens settings. Right-click opens a quick menu.
- Pill visibility setting: **Always**, **Only in the last minute** (threshold editable, 60 s by default), or **Never**. Breaks always show the break card unless anti-cheat safe mode is on. The tray flyout always works.

**Break card.** Expands from the pill to about 340 x 165 px: breathing green ring with the countdown, breathing eye, "Look 20 feet away", a rotating prompt. Buttons: Blink 0/10, Skip, 5 more min. With the camera on, blinks count automatically. Sound on open. At the end: "Nice, eyes rested", "N of 15 today", then it collapses after 3 seconds. Never takes keyboard focus.

**Settings window.** A normal window, Mica backdrop, custom title bar, left navigation and Settings cards. Pages: Timer (ring, status, Pause/Resume, Break now, Reset, work length, break length, daily goal), Reminders (style, sound theme with preview, volume, pill settings), Stats (goal progress, streak, 7-day chart), Camera, Hotkeys, Games and safety, Startup, About.

**Tray.** Eye icon with time left in the tooltip. Left-click opens a small Fluent flyout (ring, Pause/Resume, Break now, Open settings). Right-click: Open settings, Pause/Resume, Break now, Quit. This is the fallback when the pill is hidden, for example behind an exclusive fullscreen game.

### Behaviors

- Smart pause: the countdown holds after 60 seconds without input, or while the PC is locked. After 5 minutes away, the work timer resets.
- Launch at login toggle.
- Stats and settings in `%APPDATA%\EyeRule\` as JSON.

## Gaming and anti-cheat (Windows)

Most games run Borderless (the topmost pill shows over them); exclusive fullscreen cannot be drawn over, so the fallback is a sound, a taskbar flash and a toast when you leave the game.

- The pill window is non-activating (`WS_EX_NOACTIVATE`), topmost and a tool window (`WS_EX_TOOLWINDOW`), applied directly through the `windows` crate because the Tauri options are not reliable on Windows.
- Topmost is re-asserted at each break.
- Game-friendly card: when a fullscreen app is detected (`SHQueryUserNotificationState`), a smaller card shows the countdown, prompt and hotkey hints, with no buttons.
- Optional "Don't interrupt" delay while in a game, up to 5 minutes, off by default.
- Global hotkeys: Skip `Ctrl+Alt+S`, 5 more minutes `Ctrl+Alt+M`, Blink +1 `Ctrl+Alt+B`, Open settings `Ctrl+Alt+E`. All editable or removable; combinations without a modifier are refused.
- **Anti-cheat safe mode, on by default.** The app never hooks into or injects into games. Hotkeys use `RegisterHotKey`, not a keyboard hook. While a watched anti-cheat process runs, the overlay, hotkeys and camera are off and reminders come from a sound plus a small tray notification. Safe mode can be turned off on the Games and safety page.

### Anti-cheat watch list

Editable in the app; names come from memory and must be confirmed on the PC (Task Manager, Details tab, while a game runs).

| System | Likely process or service names |
|---|---|
| Riot Vanguard | `vgc.exe`, `vgtray.exe` |
| Easy Anti-Cheat | `EasyAntiCheat.exe`, `EasyAntiCheat_EOS.exe` |
| BattlEye | `BEService.exe`, `BEDaisy` (driver) |
| FACEIT | `FACEIT.exe`, `faceitservice.exe` |
| nProtect GameGuard | `GameMon.des`, `GameMon64.des` |
| XIGNCODE3 | `xhunter1` |
| Call of Duty Ricochet | Kernel driver, no reliable process name |
| Valve VAC | Runs inside the game, nothing to detect |

Where nothing is detectable (Ricochet, VAC), safe mode can't switch itself on; those games go on the manual "never show the overlay" list instead.

## Camera eye tracker (both platforms, off by default)

Features in order of build:
1. **Blink counting** during breaks, replacing the manual Blink button.
2. **Blink-rate reminder** when blinks per minute fall below a threshold.
3. **Face presence** for a better smart pause, for example while watching a video.
4. **Later:** too-close hint (face size) and fatigue hint (long closures, falling blink rate).

What it can't do: it can't confirm you are focusing 20 feet away. It can tell that you look away or left. It can't do screen-point gaze tracking and doesn't need to.

Privacy rules (identical on both platforms):
- Opt-in with a clear explanation.
- On-device analysis only. Frames are never saved or sent; only numbers are kept.
- About 5 fps, sampled in short bursts. The camera light is on while active and cannot be hidden.
- The pill shows a camera indicator while the camera is in use. Where the pill is hidden between breaks, the tray icon shows it.
- Skipped when another app already uses the camera (this doubles as call detection).
- Off while a fullscreen game runs, and off entirely in anti-cheat safe mode.

**Mac (in the Swift app).** `AVCaptureSession` at burst intervals, `VNDetectFaceLandmarksRequest` for eye contours and face presence, eye aspect ratio for blinks. Needs `NSCameraUsageDescription` added in `build.sh`'s Info.plist. Settings gets a Camera section: enable toggle, use face presence for pause, auto-count blinks, blink-rate threshold, live numbers only (no video), status line and a link to System Settings > Privacy > Camera. Permission is requested on first use.

**Windows.** A hidden web view opens the camera and runs MediaPipe Face Landmarker, which returns blendshape scores including eye blink. Detect a blocked camera (Windows shares one privacy switch for all desktop apps) and link to Settings > Privacy > Camera.

## Memory use (Windows only)

Reference estimate: WebView2 usually costs 100 to 150 MB across several `msedgewebview2.exe` processes. The strategy is to create web views only when needed:

- The Rust engine and tray run all the time and use very little.
- With the pill set to "Only in the last minute", the pill's web view is created about 75 seconds before a break and destroyed after it. The settings window and flyout exist only while open.
- WebView2 starts with flags that limit its processes; the saving is measured before it counts.
- The camera model loads only while sampling.

Decision rule from the spike: if "between breaks" is above about 50 MB, or "pill visible" above about 200 MB, pick a fallback before building the rest.

Fallbacks, in order: a native Direct2D pill in Rust (about 15 to 30 MB, pill UI in two versions), a no-webview Rust UI framework such as Slint (about 25 to 45 MB, larger rewrite), or WPF/WinUI 3 in C# (about 40 to 80 MB, blind development from this Mac).

## R&D findings and risks

| Topic | Finding | Plan |
|---|---|---|
| Cross-building from macOS | Tauri's supported path is build-on-target. A raw exe via `cargo-xwin` usually links, but the WebView2 loader and resource embedding are unverified. | Spike 0a: hello-world exe copied to the PC and run. Installers stay on the PC. |
| Windows focus setting ignored | `focus: false` did not stop startup focus gain. See [issue 11566](https://github.com/tauri-apps/tauri/issues/11566). | Apply the no-activate style directly after window creation. |
| Windows skip taskbar | `skipTaskbar` has had bugs. See [issue 10422](https://github.com/tauri-apps/tauri/issues/10422). | Also set the tool-window style directly. |
| Partial click-through | Tauri can ignore the mouse for a whole window, not only its transparent parts. See [discussion 11507](https://github.com/tauri-apps/tauri/discussions/11507). | Size the window exactly to the pill or card. |
| Windows camera privacy | Desktop apps share one switch under Privacy and security > Camera. See [Microsoft docs](https://learn.microsoft.com/en-us/windows/apps/develop/camera/camera-privacy-setting). | Detect a blocked camera and link there. |
| Blind development | Only compile checks run here. | The PC tests above; log file for diagnosis. |

No longer risks, because Mac stays Swift: the non-activating notch panel, WKWebView camera access, vibrancy, and Mac memory numbers from the earlier plan.

## Phases

0. **Spikes (throwaway)**
   - Windows: cross-build a hello-world Tauri exe, copy it to the PC, run it.
   - Windows: transparent, no-focus, topmost pill over a borderless game, then next to each game with anti-cheat.
   - Windows: memory test on the PC in four states (tray only, pill visible, settings open, camera on).
   - Mac: camera blink test at 5 fps in a small Swift harness, plus a MediaPipe page in Safari for comparison.
   - **Done (Mac camera):** Vision at 10 fps is the working rate. Face presence 100%, open-eye ratio ~0.28 with adaptive thresholds, ~40 ms per frame, 16 blinks/min detected at 10 fps versus 13 at 5 fps. Harness lives in `spikes/camera-mac/`.
1. **Mac camera feature in the Swift app.** Status: feature-complete, pending your blink-reminder check — blink counting during breaks, blink-rate reminder, face-presence smart pause, Camera settings and indicators are in `Sources/EyeRule/CameraTracker.swift` and the settings tab.
2. **Windows engine and tests.** Status: done. Timer phases, snooze, skip, smart pause (idle, lock and camera presence), call deferral, blinks, prompts, stats, streak and settings storage live in `app/src-tauri/` with 21 passing tests; settings and history persist as JSON through the store module.
3. **Windows pill and break card.** Status: done in the real Tauri app — transparent pill window, last-minute state, break card with blink/skip/snooze, done state, game backdrop. Browser preview and screenshots remain in `app/shots/`.
4. **Windows settings window, flyout and tray.** Status: done — Fluent settings window, tray icon with menu and flyout, dark/light preview, hotkey dialog. Screenshots in `app/shots/`.
5. **Windows integration.** Status: done and compile-verified — engine↔UI commands/events, tray + flyout, pill/settings/flyout/camera windows, rodio chimes, default hotkeys (Ctrl+Alt+S/M/B/E), autostart, and Windows-only no-activate/tool-window/topmost styles + re-assert-on-break + session-lock (WTS) + idle + fullscreen + anti-cheat scan behind `cfg(windows)`. Windows x64 exe cross-built in Docker with `cargo-xwin` (~10 MB, PE32+ GUI AMD64). On-PC runtime test still pending.
6. **Windows camera tracker.** Status: implemented — hidden Tauri web view loads MediaPipe Face Landmarker, counts blinks and face presence at ~10 fps, and reports numbers to Rust via the `camera_sample` command; the engine consumes them for blink counting and face-presence pause. Camera window starts/stops with the Camera setting and stops in anti-cheat safe mode. Compile-verified for Windows; needs on-PC test (camera permission, WebView2, model download).
7. **Hand-off.** Status: done. Mac: `./build.sh` (see `build.sh`). Windows: build the UI with `npm run build` in `app/`, then from `app/`
   `docker build -t eyerule-win -f Dockerfile.win .` and
   `docker run --rm -v "$PWD":/work -v "$PWD/.win-target":/win-target -e CARGO_TARGET_DIR=/win-target eyerule-win`,
   copy `app/.win-target/x86_64-pc-windows-msvc/release/eyerule.exe` to the PC. On the PC verify: Windows 11 WebView2 present, pill over a borderless game and stays above it, Ctrl+Alt+S/M/B/E work in-game, anti-cheat safe mode hides overlay/hotkeys/camera (test next to each game), fullscreen fallback sound/toast, tray flyout, launch at login, camera permission + blink counting, and memory in four states (tray only, pill, settings, camera).

Phase 1 and phases 2 to 6 are independent; if you'd rather start with the Windows app, they can swap.

## Left out of the first version

- A Tauri port of the Mac app.
- Call detection on Windows.
- Multi-monitor support.
- Installers and code signing.
- Distance and fatigue hints.

## Decisions made

- Mac: the Swift app stays; the camera tracker is added natively (Vision).
- Windows: Rust + Tauri v2, React and Fluent UI, x86_64 exe cross-built on the Mac and copied to the PC.
- No Windows VM. The PC is the only Windows runtime.
- Two implementations of a small engine, kept aligned by a shared spec and mirrored behavior tests.
- Windows: pill on by default, editable hotkeys, anti-cheat safe mode on by default.
- Safe mode reminders: a sound plus a small tray notification.

## Your games and their anti-cheat

| Game | Anti-cheat | Notes |
|---|---|---|
| Dead by Daylight | Easy Anti-Cheat ([source](https://elocarry.net/de/blog/dead-by-daylight/anti-cheat-and-bans-explained/)). DBD's support site also describes a Denuvo Anti-Cheat test. | Some players report EAC errors fixed by closing overlays; safe mode turns the overlay off. |
| CS2 | Valve VAC (from memory, not re-checked) | No separate process; goes on the manual "never show the overlay" list. |
| Black Desert Online | Not verified | Needs a check on the PC in Task Manager. |

## UI mock

The browser mock of the Windows UI is in `mockups/windows/`. Open `index.html` in a browser. Screenshots are in `mockups/windows/shots/`. The Mac UI needs no mock; the Swift app already defines it.

## Open questions

1. Default pill visibility on Windows: Always (the current decision) or "Only in the last minute"? It changes the memory measurement and the feel.
2. The `.exe` names in the mock need confirming in Task Manager while each game runs.
3. Start with phase 1 (Mac camera, all testable here) or phase 0 (Windows spikes, needs the PC)?
4. Anything to change in the Windows mock?
