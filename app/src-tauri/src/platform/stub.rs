use super::Platform;
use crate::engine::Presence;

#[derive(Default)]
pub struct StubPlatform;

impl Platform for StubPlatform {
    fn idle_seconds(&self) -> f64 {
        0.0
    }
    fn locked(&self) -> bool {
        false
    }
    fn in_call(&self) -> bool {
        false
    }
    fn face_present(&self) -> Presence {
        Presence::Unknown
    }
    fn fullscreen_active(&self) -> bool {
        false
    }
    fn anti_cheat_running(&self) -> bool {
        false
    }
}
