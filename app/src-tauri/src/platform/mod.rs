use crate::engine::Presence;

pub trait Platform: Send + Sync {
    fn idle_seconds(&self) -> f64;
    fn locked(&self) -> bool;
    fn in_call(&self) -> bool;
    fn face_present(&self) -> Presence;
    fn fullscreen_active(&self) -> bool;
    fn anti_cheat_running(&self) -> bool;

    /// Apply no-activate / tool-window / topmost styles to the overlay (Windows).
    fn style_overlay(&self, _hwnd: isize) {}
    /// Re-assert topmost so games can't push the pill down (Windows).
    fn keep_topmost(&self, _hwnd: isize) {}
}

#[cfg(not(target_os = "windows"))]
mod stub;
#[cfg(not(target_os = "windows"))]
pub use stub::StubPlatform as CurrentPlatform;

#[cfg(target_os = "windows")]
mod windows;
#[cfg(target_os = "windows")]
pub use windows::WindowsPlatform as CurrentPlatform;

pub fn current() -> Box<dyn Platform> {
    Box::new(CurrentPlatform::default())
}
