> **Kept for its Windows details.** The current plan is in `PLAN.md`: Swift stays on the Mac, and the Windows app is Rust + Tauri, cross-built from the Mac. Everything here about the Windows side still applies.

# EyeRule for Windows 11: Implementation Plan

20-20-20 eye-rest reminder for Windows 11. Built with Rust and Tauri v2. The settings window is styled like PowerToys (WinUI 3 / Fluent). The Mac app (Swift, in `Sources/EyeRule/`) stays as it is.

Status: plan only. No Windows code has been written yet.

## Stack decision

| Part | Choice |
|---|---|
| Shell and backend | Rust + Tauri v2 |
| Frontend | TypeScript, React, Vite, Fluent UI React v9 |
| Look | Fluent 2 / WinUI 3 (PowerToys style) with a Mica backdrop |
| Timer engine | Rust (runs even when every window is closed) |
| Windows APIs | The `windows` crate |

Why Tauri: transparent, always-on-top, no-focus windows, tray, toasts and global hotkeys are built in or have official plugins. Node and Rust are installed on the Mac, so the UI can be previewed in a browser here.

Why Fluent UI React v9: it is Microsoft's own component library, so switches, number boxes, dropdowns, cards, dialogs and navigation match WinUI 3 closely.

## Limits

- The Windows app can't be run on a Mac. Rust unit tests and the UI preview run here. I will also try `cargo check` for the Windows target on the Mac. The real build, run and test happen on your Windows 11 PC.
- Mica and window transparency don't show in the Mac browser preview. The preview approximates the look. The true result is seen on Windows.
- Transparent, no-focus windows need Win32 calls that can only be verified on Windows. If rounded corners fail on the pill, it is a cosmetic fix after testing.

## What you see: four surfaces

| Surface | Style | Purpose |
|---|---|---|
| Pill | Black, custom (not Fluent) | Always visible at the top center of the screen |
| Break card | Black, custom | Expands from the pill at break time |
| Settings window | PowerToys / WinUI 3 | All controls, stats, settings, hotkeys |
| Tray flyout | Fluent flyout | Quick controls from the tray icon |

The pill and break card stay black on purpose. They must be readable over any game or desktop, and they match the Mac app.

### 1. Compact pill

- About 220 x 34 px, black, rounded bottom corners. Always on top, never takes focus, not in the taskbar or Alt+Tab.
- Left: eye icon. It blinks every few seconds, becomes a pause icon when paused and a moon icon when you are away.
- Right: countdown (for example `19:31`). In the last minute it becomes "Break in 45s", and the eye and outline pulse.
- A thin progress line runs along the bottom with a shimmer.
- A thin outline uses the accent color: cyan while working (lavender in the evening, periwinkle at night), yellow in the last 5 minutes, orange in the last minute, green during a break.
- Click: opens the settings window. Right-click: quick menu.

### 2. Break card

- Expands from the pill to about 340 x 165 px with an ease-out animation.
- Contents: a green countdown ring that breathes, a breathing eye icon, "Look 20 feet away", and a rotating prompt such as "Blink slowly 10 times."
- Buttons: `Blink 0/10`, `Skip`, `5 more min`. A sound plays when it opens.
- When the break ends it shows "Nice, eyes rested" and "N of 15 today", then collapses after 3 seconds.
- It never takes keyboard focus.

### 3. Settings window (PowerToys style)

A standard Windows 11 window with a Mica backdrop and a custom title bar. It follows the system light or dark theme and the system accent color.

Layout: a left navigation pane (collapsible) and a content area with Settings cards, like PowerToys.

Navigation pages:

| Page | Contents |
|---|---|
| Timer | Hero card with the ring, status, Pause/Resume, Break now, Reset. Cards for work length, break length, daily goal (number boxes). |
| Reminders | Reminder style (Pill / Toast / Both), sound theme with preview, volume, pill on or off, and pill position. |
| Stats | Progress toward the daily goal, streak, 7-day bar chart. |
| Hotkeys | One card per action with a PowerToys-style shortcut control. A pencil button opens a "Press a shortcut" dialog with Save and Cancel. |
| Games and safety | Anti-cheat safe mode, "Don't interrupt in games" with a maximum delay, detected game or anti-cheat status, and fullscreen fallback options. |
| Startup and behavior | Launch at login, smart pause with an idle time box, and start minimized to the tray. |
| About | Version and links. |

Sketch:

```
 +----------------------------------------------------------------------+
 | (eye) EyeRule                                          _   [ ]   X   |
 +----------------+-----------------------------------------------------+
 |  Timer      <  |  Timer                                              |
 |  Reminders     |                                                     |
 |  Stats         |  +-----------------------------------------------+  |
 |  Hotkeys       |  |   .-------.   WORKING                         |  |
 |  Games & safety|  |  /  19:31  \  You've got 20 minutes.          |  |
 |  Startup       |  |  \         /  No breaks yet today.            |  |
 |                |  |   `-------'   [Pause] [Break now] [Reset]     |  |
 |                |  +-----------------------------------------------+  |
 |                |  | Work length                       [ 20 ] min  |  |
 |                |  | Break length                      [ 20 ] sec  |  |
 |                |  | Daily goal                        [ 15 ]      |  |
 |  About         |  +-----------------------------------------------+  |
 +----------------+-----------------------------------------------------+
```

Hotkeys page sketch:

```
 |  Hotkeys                                                            |
 |  +----------------------------------------------------------------+ |
 |  | Skip break              Skip the current break      [Ctrl][Alt][S] (pencil) |
 |  | 5 more minutes          Postpone by 5 minutes       [Ctrl][Alt][M] (pencil) |
 |  | Count a blink           Blink counter +1            [Ctrl][Alt][B] (pencil) |
 |  | Open settings           Show the window             [Ctrl][Alt][E] (pencil) |
 |  +----------------------------------------------------------------+ |
```

### 4. Tray icon and flyout

- Tray icon is the eye, with the time left in the tooltip.
- Left-click opens a small Fluent flyout near the taskbar: ring with time, Pause/Resume, Break now, and "Open settings". It closes when you click elsewhere.
- Right-click menu: Open settings, Pause/Resume, Break now, Quit.
- This is the fallback if the pill is hidden, for example behind an exclusive fullscreen game.

```
        +------------------------------+
        |  (  19:31 )  Working         |
        |              7 of 15 today   |
        |  [ Pause ]  [ Break now ]    |
        |------------------------------|
        |  Open settings               |
        +------------------------------+
```

## Playing games

The PC runs Windows 11 and is used for gaming. Most games run Borderless; some force Exclusive fullscreen.

| Game display mode | Pill over the game? |
|---|---|
| Borderless windowed | Yes. An always-on-top window shows over it. |
| Windowed | Yes. |
| Exclusive fullscreen | No. Nothing can draw over it. Fallback: sound, taskbar flash, and a toast when you leave the game. |

Requirements:

1. **Never steal focus.** The pill window is created non-activating (`WS_EX_NOACTIVATE`), topmost, tool window (hidden from taskbar and Alt+Tab).
2. **Stay on top.** The app re-asserts the topmost state at each break, because some games push other windows down.
3. **Mouse-free controls.** In many games the cursor is captured, so global hotkeys do the same jobs as the buttons.
4. **Game-friendly card.** When a fullscreen app is detected (`SHQueryUserNotificationState`), the card is smaller and shows the countdown, the prompt and the hotkey hints. It has no buttons.
5. **Optional "Don't interrupt".** Delay the break while you are actively in a game, for up to 5 minutes. Off by default.

### Editable hotkeys

- Defaults: Skip `Ctrl+Alt+S`, 5 more minutes `Ctrl+Alt+M`, Blink +1 `Ctrl+Alt+B`, Open settings `Ctrl+Alt+E`.
- Every hotkey is editable on the Hotkeys page. A row can be cleared to turn that hotkey off.
- Combinations without a modifier key are refused, because they would block typing and game controls. The app warns when another app already uses a combination.

### Anti-cheat safe mode (default on)

You play games with anti-cheat, so the app avoids anything that could look like interference.

- The app is an ordinary window. It does not hook into games, inject code, or read game memory.
- Hotkeys use the standard Windows hotkey call (`RegisterHotKey`), not a keyboard hook.
- The app checks for running anti-cheat processes (for example Riot Vanguard `vgc.exe`, Easy Anti-Cheat and BattlEye). While one is running:
  - the pill and break card are not shown
  - global hotkeys are turned off
  - reminders come from a sound and the tray icon only
- Safe mode can be turned off on the "Games and safety" page.
- I can't promise that every anti-cheat accepts every overlay. Safe mode is the conservative choice.

## Behaviors

- **Smart pause:** the countdown holds after 60 seconds without keyboard or mouse input, or while the PC is locked. After 5 minutes away, the work timer resets.
- **Launch at login** is a toggle.
- The pill appears on the primary monitor, top center.
- Stats and settings are saved in the app data folder.

## Technical plan

### Backend (Rust)

| Crate or plugin | Purpose |
|---|---|
| `tauri` v2 | App shell, windows, tray |
| `tauri-plugin-global-shortcut` | Global hotkeys |
| `tauri-plugin-notification` | Windows toasts |
| `tauri-plugin-autostart` | Launch at login |
| `window-vibrancy` | Mica backdrop for the settings window |
| `windows` | Non-activating topmost window, idle time (`GetLastInputInfo`), game detection, process list |
| `rodio` | Sound playback in Rust |
| `serde`, `serde_json` | Settings and stats storage |

Modules under `src-tauri/src/`:
- `engine.rs`: work and break phases, snooze, stats, streak, prompts. Plain Rust, unit tested on the Mac.
- `settings.rs`: settings and stats storage.
- `platform/`: window styles, idle, game and anti-cheat detection, sound. Each behind a small trait so the engine is tested without Windows.
- `main.rs`: windows, tray, hotkeys, events to the frontend.

### Frontend (TypeScript, React, Vite, Fluent UI v9)

- `pill/`: pill and break card (custom black UI, animations in CSS).
- `settings/`: the PowerToys-style window and its pages.
- `flyout/`: the tray flyout.
- The frontend receives state from the Rust engine through events and sends commands back.

### Assets

- Three short generated sounds: Chime, Water drop, Soft (plus Silent as an option).
- Tray icon and app icon (`.ico`).

## Phases

1. **Project setup and engine.** Phases, snooze, stats and streak, settings storage, prompts. Rust unit tests that pass on the Mac.
2. **Pill and break card UI.** Built in the browser on the Mac with screenshots, including the animations.
3. **Settings window and flyout.** PowerToys-style pages with Fluent UI. Preview on the Mac with screenshots. Mica won't show in the preview.
4. **Windows integration.** Non-activating topmost window, Mica, tray, toasts, sound, idle detection, launch at login, global hotkeys with the editable shortcut dialog, game detection, game-friendly card, anti-cheat safe mode. Written and `cargo check`ed for Windows from the Mac where possible, but only testable on the PC.
5. **Hand-off.** Build instructions (`npm install`, `npm run tauri build` on Windows), and a checklist of what to test on the PC.

## Left out of the first version

- Detecting calls (mic and camera).
- Multi-monitor support.
- An installer. Tauri can produce one, so this can be added early.
- Light or dark theme override. The window follows the system setting.

## Decisions

- Platform: Windows 11 only.
- Stack: Rust with Tauri v2, React with Fluent UI v9.
- Settings window: PowerToys / WinUI 3 style with Mica. Pill and break card: custom black.
- Game display mode: mostly Borderless (overlay works). Some games force Exclusive fullscreen (sound and tray fallback).
- Anti-cheat: yes. Safe mode is on by default.
- Hotkeys: defaults provided, all editable.
- Pill: on by default. It can be switched to tray-only in the settings.

## Open questions

1. Which anti-cheat systems do your games use, so I can add their process names to the safe-mode list? Examples: Vanguard, Easy Anti-Cheat, BattlEye, Ricochet, FACEIT.
2. In safe mode, should reminders be sound only, or also a small tray notification?
3. Do you want the controls (Pause, Break now, Reset) only in the settings window and tray flyout, or also in a panel opened from the pill like on the Mac?
