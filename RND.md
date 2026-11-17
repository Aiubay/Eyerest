# EyeRule R&D notes: WinUI 3 option and camera eye tracker

Status: research and planning only. No code written for either topic.

Scope of this document:
1. Can the Windows app use C# or C++ with WinUI 3 instead of Tauri?
2. Can both apps (Mac and Windows) add a camera-based eye tracker?

---

## 1. WinUI 3 instead of Tauri

### What WinUI 3 is good for here

- It is the native Windows 11 UI framework, so controls, Mica and theming match PowerToys exactly. No imitation needed.
- The settings window, tray flyout and hotkey dialog are a natural fit.

### Where it is weak: the overlay pill

The pill must be transparent, rounded, always on top, never take focus, and stay out of the taskbar. WinUI 3 does not offer this directly.

Findings from community threads and Microsoft Q&A:
- WinUI 3 has no real "allow transparency" switch like WPF. Developers work around it by removing the title bar and border, subclassing the window procedure (for example handling `WM_NCCALCSIZE`), and painting the backdrop with a fully transparent composition brush. See [this Stack Overflow answer on a borderless transparent WinUI 3 overlay](https://stackoverflow.com/questions/77627514/can-i-create-borderless-transparent-overlay-window-in-winui-3) and [a related question on transparent WinUI 3 windows](https://stackoverflow.com/questions/75601823/how-can-i-make-the-window-transparent-in-winui3).
- Click-through and no-focus behavior come from Win32 extended window styles (topmost, no-activate, transparent), which are applied to the window handle from WinUI 3 code. See [this Stack Overflow answer on the extended styles](https://stackoverflow.com/revisions/65737311/1) and [a note on partial click-through with hit testing](https://stackoverflow.com/questions/17050235/how-to-stop-event-propagation-despite-ws-ex-noactivate).
- A known Windows quirk: a no-activate window can fail to drag smoothly until the mouse is released. The fix is a `SetWindowPos` call while moving. See [this report](https://stackoverflow.com/questions/25051552/create-a-window-using-the-ws-ex-noactivate-flag-but-it-cant-be-dragged-until-i). The pill does not need dragging, so this is low risk.

Conclusion: a transparent no-focus pill in WinUI 3 is possible, but it relies on workarounds, and I can't verify them without a Windows machine.

### Language: C# or C++

| | C# (.NET) | C++ (C++/WinRT) |
|---|---|---|
| Speed of development | Fast | Slow |
| Samples and answers online | Many | Fewer |
| Memory and startup | Higher | Lower |
| Win32 calls (hotkeys, idle, process list) | Easy through the CsWin32 library | Direct |
| Risk when I can't run the code | Lower | Higher |

Recommendation if WinUI 3 is chosen: C#. PowerToys itself mixes C++ for system modules and C# for UI, but this app has no need for C++ speed.

### Biggest practical difference: what I can test from this Mac

| | Tauri | WinUI 3 (C#) |
|---|---|---|
| Build on this Mac | Rust unit tests and a Windows `cargo check` are possible | No. WinUI 3 needs the Windows SDK and Windows App SDK tooling. |
| Preview the UI on this Mac | Yes, in a browser or in Tauri's macOS build | No |
| Screenshots before you test | Yes | No |
| Authentic PowerToys look | Imitated with Fluent UI React | Exact |
| Transparent no-focus pill | Built in to Tauri windows, plus Win32 calls | Workarounds (see above) |

With WinUI 3 every change would pass through your Windows PC with no earlier check, so iteration is slower.

### Options for the Windows app

| Option | Stack | Best for | Main risk |
|---|---|---|---|
| A | Tauri + React + Fluent UI | Fastest, preview here, safer pill | The PowerToys look is close, not identical |
| B | WinUI 3 (C#) for everything | Exact native look | Blind development, hacky pill |
| C | WinUI 3 (C#) settings and tray, plus a separate small Win32 layered window for the pill | Exact settings look, reliable pill | Two UI systems in one app, more code |

My recommendation is A. If the exact PowerToys look matters more than speed, choose C, because it keeps the fragile overlay out of WinUI 3.

---

## 2. Camera eye tracker (Mac and Windows)

### What a webcam can and can't do

Webcams give a face and eye landmarks. That supports:

| Feature | How it works | Reliability |
|---|---|---|
| Blink counting | Measure how open the eyelids are, using eye landmarks or the "eye blink" blendshape scores from a face model. | Good |
| Blink rate warning | Compare your blinks per minute to a healthy range and prompt "blink more". | Good, with a few seconds of smoothing |
| Face presence | Detect whether a face is in front of the screen. Better "smart pause" than keyboard idle time, for example while watching video. | Good |
| Screen distance | Estimate from face size in the image. Needs a short calibration. | Rough, useful for a "too close" hint |
| Break check | During a break, check the face turned away or left. | Partial. See below. |
| Fatigue hint | Long eye closures or a falling blink rate suggest tiredness. | Rough |

What it can't do:
- It can't tell that you are focusing on something 20 feet away. A webcam above the screen can tell you are clearly looking away from the screen, or that you left. It can't measure focus distance.
- True gaze tracking (where on the screen you look) needs calibration and is only coarse on a normal webcam. It isn't needed for this app.

### Camera behavior and privacy rules (the same on both platforms)

- Off by default. Opt-in with a clear explanation.
- All analysis runs on the device. Frames are never saved or sent. Only numbers are kept (for example blinks per minute).
- Low frame rate (about 5 frames per second) and sampling in short bursts, not continuous, to keep CPU low and reduce the time the camera light is on.
- The camera light turns on whenever the camera is active. That is a hardware feature and can't be hidden.
- The pill shows a small camera indicator while the camera is in use.
- If another app (for example a video call) already uses the camera, skip sampling. This also works as call detection.
- Anti-cheat safe mode (Windows) turns the camera feature off, to avoid anything unusual while a protected game runs.
- Gaming: the camera feature is off by default while a fullscreen app runs, to protect frame rate.

### Mac implementation (native Swift app)

- Capture: `AVCaptureSession` for camera frames.
- Analysis: Apple's Vision framework, `VNDetectFaceLandmarksRequest`, which returns eye contours and pupils. Apple says Vision uses Apple Silicon acceleration on supported Macs ([WWDC22: What's new in Vision](https://developer.apple.com/videos/play/wwdc2022/10024)). One developer reported slow landmark requests on an iPad ([forum thread](https://stackoverflow.com/questions/47093538/tracking-eyes-with-vision-framework)), so low-rate sampling and a speed test on this Mac are part of the R&D.
- Permission: add `NSCameraUsageDescription` to `Info.plist`. The first use shows the system camera permission prompt. [Walkthrough](https://medium.com/@saqibomer.cs/apple-vision-framework-and-facial-features-detection-1bc3f9f24ed8).
- Blink detection: compute the eye aspect ratio from the eye contour points. A blink is a brief drop below a threshold.
- No extra packages needed.

### Windows implementation (depends on the chosen stack)

Camera permission on Windows: access is controlled in Settings under Privacy and security, Camera. For desktop apps, Windows offers one switch for all desktop apps, not a per-app setting ([Microsoft: camera privacy setting](https://learn.microsoft.com/en-us/windows/apps/develop/camera/camera-privacy-setting), [Microsoft support: app permissions for a camera](https://support.microsoft.com/en-us/windows/manage-app-permissions-for-a-camera-in-windows-87ebc757-1f87-7bbf-84b5-0686afb6ca6b)). The app should detect when access is blocked and link the user to that Settings page.

Analysis options:

| Option | How | Fits |
|---|---|---|
| MediaPipe Face Landmarker in a hidden web view | The web view opens the camera and runs Google's Face Landmarker, which returns 478 landmarks and blendshape scores, including eye blink ([Google docs](https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker)). Blink detection from these landmarks is a well-trodden technique ([example project](https://github.com/Pushtogithub23/Eye-Blink-Detection-using-MediaPipe-and-OpenCV)). | Tauri (option A). Also possible in WinUI 3 through its WebView2 control. |
| ONNX Runtime with a face landmark model | Native code reads camera frames through Windows media APIs and runs a model with ONNX Runtime. Needs a model converted to ONNX. | WinUI 3 (options B and C). More work. |

Recommendation: the hidden web view approach. It is the least code and gives blink scores directly. Tauri fits it best, which counts toward option A.

### Parity between Mac and Windows

| Feature | Mac | Windows |
|---|---|---|
| Blink counting | Vision landmarks | MediaPipe blendshapes or landmarks |
| Face presence | Vision face detection | MediaPipe |
| Distance hint | Face size | Face size |
| Privacy rules | Same | Same |
| UI in settings | New "Camera" section | New "Camera" page |

The Camera section would hold:
- Enable camera tracking (off by default)
- Use face presence for smart pause
- Auto-count blinks during breaks (replaces the manual Blink button)
- Blink rate reminder and its threshold
- Too-close distance hint
- A live preview of the numbers (not the video)
- A camera status line and a link to the system privacy settings

---

## 3. R&D spikes (small experiments to run before building)

Each spike is a throwaway test that answers one question.

| # | Spike | Question answered | Where it runs |
|---|---|---|---|
| 1 | Mac camera test: `AVCaptureSession` plus Vision at 5 fps, log blink count and face presence | How accurate and light is blink detection on this Mac? | This Mac. Needs your OK to use the camera. |
| 2 | Browser test: MediaPipe Face Landmarker in a page, log blink scores | How accurate is MediaPipe, and how heavy is it in a web view? | This Mac (browser) |
| 3 | Windows pill test: smallest possible transparent, no-focus, topmost pill, first in Tauri, optionally in WinUI 3 | Does the pill stay on top of your borderless games without taking focus? | Your Windows PC |
| 4 | Windows anti-cheat check: run spike 3 next to your games with anti-cheat | Does any game complain about the overlay? | Your Windows PC |
| 5 | Windows camera test: run spike 2 in the Tauri web view | Does the camera work, and what is the CPU use? | Your Windows PC |

---

## 4. Decisions needed

1. Windows stack: A (Tauri), B (WinUI 3 everything) or C (WinUI 3 plus a separate Win32 pill)?
2. If WinUI 3: C# (recommended) or C++?
3. Camera eye tracker: which features first? A suggested starting set is blink counting, blink-rate reminder and face-presence smart pause. Distance hints and fatigue hints come later.
4. May I run spike 1 on this Mac? It uses the camera for short tests. Nothing is saved.

---

## 5. Answers received

- Windows stack: Rust with Tauri for Windows x64, cross-built on the Mac and copied to the PC (see `PLAN.md`). The Mac app stays Swift.
- Camera eye tracker: yes, on both platforms; native Vision on Mac, MediaPipe on Windows.
- Camera tests on this Mac during development: approved.
