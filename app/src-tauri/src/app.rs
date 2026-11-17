use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::Mutex;
use std::time::Duration;

use chrono::Timelike;
use rodio::Source;
use serde::Serialize;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, State, WebviewUrl, WebviewWindowBuilder};
use tauri_plugin_autostart::ManagerExt;
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};

use crate::engine::{Effect, Engine, TickInput};
use crate::platform::{self, Platform};
use crate::settings::{PillVisibility, Settings};
use crate::store::Store;

pub struct AppState {
    pub engine: Mutex<Engine>,
    pub platform: Box<dyn Platform>,
    pub store_path: PathBuf,
    pub camera_on: AtomicBool,
    /// 0 unknown, 1 present, 2 absent (from the MediaPipe web view).
    pub camera_face: AtomicU8,
}

impl AppState {
    fn face_presence(&self) -> crate::engine::Presence {
        if !self.camera_on.load(Ordering::Relaxed) {
            return self.platform.face_present();
        }
        match self.camera_face.load(Ordering::Relaxed) {
            1 => crate::engine::Presence::Present,
            2 => crate::engine::Presence::Absent,
            _ => crate::engine::Presence::Unknown,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub phase: String,
    pub remaining: u32,
    pub running: bool,
    pub auto_paused: bool,
    pub deferred: bool,
    pub blinks: u32,
    pub prompt: String,
    pub breaks_today: u32,
    pub goal: u32,
    pub streak: u32,
    pub progress: f32,
    pub accent: String,
    pub camera_active: bool,
    pub safe_active: bool,
    pub settings: Settings,
    pub last_seven: Vec<(i32, u32)>,
}

fn today_key() -> i32 {
    let epoch = chrono::NaiveDate::from_ymd_opt(1970, 1, 1).unwrap();
    (chrono::Local::now().date_naive() - epoch).num_days() as i32
}

fn accent_for(phase: &str, remaining: u32) -> String {
    if phase != "working" {
        return "#4ade80".into();
    }
    if remaining <= 60 {
        return "#fb923c".into();
    }
    if remaining <= 300 {
        return "#facc15".into();
    }
    let hour = chrono::Local::now().hour();
    match hour {
        5..=16 => "#22d3ee".into(),
        17..=20 => "#c7a0ff".into(),
        _ => "#8c99ff".into(),
    }
}

fn build_snapshot(engine: &Engine, safe_active: bool, camera_active: bool) -> Snapshot {
    let phase = match engine.phase {
        crate::engine::Phase::Working => "working",
        crate::engine::Phase::Resting => "resting",
    };
    let today = today_key();
    Snapshot {
        phase: phase.into(),
        remaining: engine.remaining,
        running: engine.running,
        auto_paused: engine.auto_paused,
        deferred: engine.deferred,
        blinks: engine.blinks,
        prompt: engine.prompt.into(),
        breaks_today: engine.breaks_today(today),
        goal: engine.settings.daily_goal,
        streak: engine.streak(today),
        progress: engine.progress(),
        accent: accent_for(phase, engine.remaining),
        camera_active,
        safe_active,
        settings: engine.settings.clone(),
        last_seven: engine.last_seven_days(today),
    }
}

fn save_store(state: &AppState) {
    let engine = state.engine.lock().unwrap();
    let store = Store {
        settings: engine.settings.clone(),
        history: engine.history.clone(),
    };
    let _ = store.save(&state.store_path);
}

fn snapshot_of(state: &AppState) -> Snapshot {
    let safe_active = state.platform.anti_cheat_running() && {
        let engine = state.engine.lock().unwrap();
        engine.settings.safe_mode
    };
    let engine = state.engine.lock().unwrap();
    build_snapshot(&engine, safe_active, state.camera_on.load(Ordering::Relaxed))
}

#[tauri::command]
pub fn get_state(state: State<AppState>) -> Snapshot {
    snapshot_of(&state)
}

#[tauri::command]
pub fn camera_running(state: State<AppState>) -> bool {
    state.camera_on.load(Ordering::Relaxed)
}

#[tauri::command]
pub fn camera_sample(state: State<AppState>, blinks: u32, face_present: bool) {
    state
        .camera_face
        .store(if face_present { 1 } else { 2 }, Ordering::Relaxed);
    if state.camera_on.load(Ordering::Relaxed) {
        let mut engine = state.engine.lock().unwrap();
        if engine.phase == crate::engine::Phase::Resting {
            for _ in 0..blinks {
                engine.blink();
            }
        }
    }
}

#[tauri::command]
pub fn camera_start(state: State<AppState>, app: AppHandle) {
    let enabled = state.engine.lock().unwrap().settings.camera_enabled;
    let safe = state.engine.lock().unwrap().settings.safe_mode && state.platform.anti_cheat_running();
    if !enabled || safe {
        return;
    }
    state.camera_on.store(true, Ordering::Relaxed);
    if let Some(window) = app.get_webview_window("camera") {
        let _ = window.set_position(tauri::PhysicalPosition::new(-3000, -3000));
        let _ = window.show();
        let _ = window.emit("camera-run", true);
    }
}

#[tauri::command]
pub fn camera_stop(state: State<AppState>, app: AppHandle) {
    state.camera_on.store(false, Ordering::Relaxed);
    state.camera_face.store(0, Ordering::Relaxed);
    if let Some(window) = app.get_webview_window("camera") {
        let _ = window.emit("camera-run", false);
        let _ = window.hide();
    }
}

#[tauri::command]
pub fn pause(state: State<AppState>) -> Snapshot {
    state.engine.lock().unwrap().toggle_running();
    save_store(&state);
    snapshot_of(&state)
}

#[tauri::command]
pub fn break_now(state: State<AppState>) -> Snapshot {
    state.engine.lock().unwrap().break_now();
    snapshot_of(&state)
}

#[tauri::command]
pub fn skip(state: State<AppState>) -> Snapshot {
    state.engine.lock().unwrap().skip();
    snapshot_of(&state)
}

#[tauri::command]
pub fn snooze(state: State<AppState>) -> Snapshot {
    state.engine.lock().unwrap().snooze();
    snapshot_of(&state)
}

#[tauri::command]
pub fn reset(state: State<AppState>) -> Snapshot {
    state.engine.lock().unwrap().reset();
    snapshot_of(&state)
}

#[tauri::command]
pub fn blink(state: State<AppState>) -> Snapshot {
    state.engine.lock().unwrap().blink();
    snapshot_of(&state)
}

#[tauri::command]
pub fn set_settings(state: State<AppState>, app: AppHandle, settings: Settings) -> Snapshot {
    let launch;
    {
        let mut engine = state.engine.lock().unwrap();
        let settings = settings.sanitized();
        engine.set_work_minutes(settings.work_minutes);
        engine.set_break_seconds(settings.break_seconds);
        engine.settings = settings;
        launch = engine.settings.launch_at_login;
    }
    save_store(&state);
    apply_autostart(&app, launch);
    if state.engine.lock().unwrap().settings.camera_enabled {
        camera_start(state.clone(), app.clone());
    } else {
        camera_stop(state.clone(), app.clone());
    }
    snapshot_of(&state)
}

#[tauri::command]
pub fn open_settings(app: AppHandle) {
    show_settings(&app);
}

#[tauri::command]
pub fn quit_app(app: AppHandle) {
    app.exit(0);
}

fn show_settings(app: &AppHandle) {
    if let Some(flyout) = app.get_webview_window("flyout") {
        let _ = flyout.hide();
    }
    if let Some(window) = app.get_webview_window("settings") {
        let _ = window.unminimize();
        let _ = window.show();
        let _ = window.set_focus();
    }
}

fn toggle_flyout(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("flyout") {
        if window.is_visible().unwrap_or(false) {
            let _ = window.hide();
        } else {
            position_bottom_right(&window, 340.0, 230.0);
            let _ = window.show();
        }
    }
}

fn apply_autostart(app: &AppHandle, enable: bool) {
    let manager = app.autolaunch();
    let _ = if enable { manager.enable() } else { manager.disable() };
}

fn register_hotkeys(app: &tauri::App) {
    let mods = Modifiers::CONTROL | Modifiers::ALT;
    let shortcuts = app.global_shortcut();

    let _ = shortcuts.on_shortcut(Shortcut::new(Some(mods), Code::KeyS), |app, _, event| {
        if event.state == ShortcutState::Pressed {
            app.state::<AppState>().engine.lock().unwrap().skip();
        }
    });
    let _ = shortcuts.on_shortcut(Shortcut::new(Some(mods), Code::KeyM), |app, _, event| {
        if event.state == ShortcutState::Pressed {
            app.state::<AppState>().engine.lock().unwrap().snooze();
        }
    });
    let _ = shortcuts.on_shortcut(Shortcut::new(Some(mods), Code::KeyB), |app, _, event| {
        if event.state == ShortcutState::Pressed {
            app.state::<AppState>().engine.lock().unwrap().blink();
        }
    });
    let _ = shortcuts.on_shortcut(Shortcut::new(Some(mods), Code::KeyE), |app, _, event| {
        if event.state == ShortcutState::Pressed {
            show_settings(app);
        }
    });
}

fn position_top_center(window: &tauri::WebviewWindow, width: f64) {
    if let Ok(Some(monitor)) = window.primary_monitor() {
        let scale = monitor.scale_factor();
        let size = monitor.size();
        let x = ((size.width as f64 - width * scale) / 2.0) as i32;
        let _ = window.set_position(tauri::PhysicalPosition::new(x, 0));
    }
}

fn position_bottom_right(window: &tauri::WebviewWindow, width: f64, height: f64) {
    if let Ok(Some(monitor)) = window.primary_monitor() {
        let scale = monitor.scale_factor();
        let size = monitor.size();
        let x = (size.width as f64 - (width + 14.0) * scale) as i32;
        let y = (size.height as f64 - (height + 58.0) * scale) as i32;
        let _ = window.set_position(tauri::PhysicalPosition::new(x, y));
    }
}

fn sync_pill(app: &AppHandle, snapshot: &Snapshot, last: &mut Option<(bool, bool)>) {
    let Some(window) = app.get_webview_window("pill") else {
        return;
    };
    let resting = snapshot.phase == "resting";
    let show = if snapshot.safe_active {
        false
    } else {
        match snapshot.settings.pill_visibility {
            PillVisibility::Always => true,
            PillVisibility::LastMinute => {
                resting || snapshot.remaining <= snapshot.settings.pill_threshold
            }
            PillVisibility::Never => resting,
        }
    };
    // Only touch the window when something changed; calling show() every
    // second can swallow the click that should open settings.
    if *last == Some((show, resting)) {
        return;
    }
    *last = Some((show, resting));
    if show {
        let _ = window.show();
    } else {
        let _ = window.hide();
    }
    let (width, height) = if resting { (360.0, 240.0) } else { (240.0, 34.0) };
    let _ = window.set_size(tauri::LogicalSize::new(width, height));
    position_top_center(&window, width);
}

fn play_tone(frequency: f32, seconds: f32) {
    std::thread::spawn(move || {
        if let Ok((_stream, handle)) = rodio::OutputStream::try_default() {
            if let Ok(sink) = rodio::Sink::try_new(&handle) {
                let source = rodio::source::SineWave::new(frequency)
                    .take_duration(Duration::from_secs_f32(seconds))
                    .amplify(0.15);
                sink.append(source);
                sink.sleep_until_end();
            }
        }
    });
}

fn play_chime() {
    play_tone(880.0, 0.12);
    std::thread::spawn(|| {
        std::thread::sleep(Duration::from_millis(140));
        play_tone(1320.0, 0.16);
    });
}

fn play_end() {
    play_tone(660.0, 0.18);
}

fn spawn_tick(app: &AppHandle) {
    let handle = app.clone();
    let mut pill_state: Option<(bool, bool)> = None;
    std::thread::spawn(move || loop {
        std::thread::sleep(Duration::from_secs(1));
        let state = handle.state::<AppState>();
        let (snapshot, effects) = {
            let mut engine = state.engine.lock().unwrap();
            let input = TickInput {
                idle_seconds: state.platform.idle_seconds(),
                locked: state.platform.locked(),
                in_call: state.platform.in_call(),
                face_present: state.face_presence(),
                today: today_key(),
            };
            let effects = engine.tick(input);
            let safe_active =
                engine.settings.safe_mode && state.platform.anti_cheat_running();
            (
                build_snapshot(&engine, safe_active, state.camera_on.load(Ordering::Relaxed)),
                effects,
            )
        };

        sync_pill(&handle, &snapshot, &mut pill_state);
        let _ = handle.emit("state", snapshot.clone());

        if snapshot.safe_active && state.camera_on.load(Ordering::Relaxed) {
            state.camera_on.store(false, Ordering::Relaxed);
            state.camera_face.store(0, Ordering::Relaxed);
            if let Some(window) = handle.get_webview_window("camera") {
                let _ = window.emit("camera-run", false);
                let _ = window.hide();
            }
        }

        for effect in effects {
            match effect {
                Effect::BreakStarted => {
                    let _ = handle.emit("break-started", ());
                    if !snapshot.safe_active {
                        play_chime();
                    }
                    #[cfg(target_os = "windows")]
                    if let Some(window) = handle.get_webview_window("pill") {
                        if let Ok(hwnd) = window.hwnd() {
                            handle
                                .state::<AppState>()
                                .platform
                                .keep_topmost(hwnd.0 as isize);
                        }
                    }
                }
                Effect::BreakFinished => {
                    let _ = handle.emit("break-finished", ());
                    play_end();
                    save_store(&state);
                }
                Effect::BlinkGoalReached => {
                    let _ = handle.emit("blink-goal", ());
                }
                Effect::CallDeferred => {
                    let _ = handle.emit("call-deferred", ());
                }
            }
        }
    });
}

fn build_tray(app: &tauri::App) -> tauri::Result<()> {
    let open = MenuItem::with_id(app, "open", "Open settings", true, None::<&str>)?;
    let pause = MenuItem::with_id(app, "pause", "Pause / Resume", true, None::<&str>)?;
    let break_now = MenuItem::with_id(app, "break", "Break now", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(
        app,
        &[
            &open,
            &pause,
            &break_now,
            &PredefinedMenuItem::separator(app)?,
            &quit,
        ],
    )?;

    let icon = app
        .default_window_icon()
        .cloned()
        .expect("app icon configured in tauri.conf.json");

    TrayIconBuilder::new()
        .icon(icon)
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "open" => show_settings(app),
            "pause" => {
                let state = app.state::<AppState>();
                state.engine.lock().unwrap().toggle_running();
            }
            "break" => {
                let state = app.state::<AppState>();
                state.engine.lock().unwrap().break_now();
            }
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                toggle_flyout(tray.app_handle());
            }
        })
        .build(app)?;
    Ok(())
}

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .setup(|app| {
            let store_path = app
                .path()
                .app_data_dir()
                .unwrap_or_else(|_| std::env::temp_dir())
                .join("store.json");
            let store = Store::load(&store_path);
            app.manage(AppState {
                engine: Mutex::new(Engine::new(store.settings, store.history)),
                platform: platform::current(),
                store_path,
                camera_on: AtomicBool::new(false),
                camera_face: AtomicU8::new(0),
            });

            let pill = WebviewWindowBuilder::new(
                app,
                "pill",
                WebviewUrl::App("index.html?window=pill".into()),
            )
            .title("EyeRule")
            .inner_size(240.0, 34.0)
            .transparent(true)
            .decorations(false)
            .always_on_top(true)
            .skip_taskbar(true)
            .resizable(false)
            .focused(false)
            .visible(true)
            .build()?;
            position_top_center(&pill, 240.0);

            let settings = WebviewWindowBuilder::new(
                app,
                "settings",
                WebviewUrl::App("index.html?window=settings".into()),
            )
            .title("EyeRule")
            .inner_size(1080.0, 640.0)
            .visible(false)
            .build()?;
            let settings_window = settings.clone();
            settings.on_window_event(move |event| {
                if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                    api.prevent_close();
                    let _ = settings_window.hide();
                }
            });

            let flyout = WebviewWindowBuilder::new(
                app,
                "flyout",
                WebviewUrl::App("index.html?window=tray".into()),
            )
            .inner_size(340.0, 230.0)
            .decorations(false)
            .always_on_top(true)
            .skip_taskbar(true)
            .resizable(false)
            .visible(false)
            .build()?;
            position_bottom_right(&flyout, 340.0, 230.0);

            WebviewWindowBuilder::new(
                app,
                "camera",
                WebviewUrl::App("index.html?window=camera".into()),
            )
            .inner_size(320.0, 240.0)
            .decorations(false)
            .skip_taskbar(true)
            .resizable(false)
            .visible(false)
            .build()?;

            build_tray(app)?;
            register_hotkeys(app);

            if app
                .state::<AppState>()
                .engine
                .lock()
                .unwrap()
                .settings
                .camera_enabled
            {
                camera_start(app.state::<AppState>(), app.handle().clone());
            }

            let launch = app
                .state::<AppState>()
                .engine
                .lock()
                .unwrap()
                .settings
                .launch_at_login;
            apply_autostart(app.handle(), launch);

            #[cfg(target_os = "windows")]
            if let Ok(hwnd) = pill.hwnd() {
                app.state::<AppState>().platform.style_overlay(hwnd.0 as isize);
            }

            spawn_tick(&app.handle());
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_state,
            pause,
            break_now,
            skip,
            snooze,
            reset,
            blink,
            set_settings,
            open_settings,
            quit_app,
            camera_running,
            camera_sample,
            camera_start,
            camera_stop
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
