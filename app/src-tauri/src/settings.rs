use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Settings {
    pub work_minutes: u32,
    pub break_seconds: u32,
    pub daily_goal: u32,
    pub smart_pause: bool,
    pub wait_in_calls: bool,
    pub camera_enabled: bool,
    pub camera_presence_pause: bool,
    pub blink_reminder: bool,
    pub blink_rate_threshold: u32,
    pub sound_theme: String,
    pub sound_volume: f32,
    pub pill_visibility: PillVisibility,
    pub pill_threshold: u32,
    pub launch_at_login: bool,
    pub safe_mode: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum PillVisibility {
    Always,
    LastMinute,
    Never,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            work_minutes: 20,
            break_seconds: 20,
            daily_goal: 15,
            smart_pause: true,
            wait_in_calls: true,
            camera_enabled: false,
            camera_presence_pause: true,
            blink_reminder: false,
            blink_rate_threshold: 10,
            sound_theme: "chime".to_string(),
            sound_volume: 0.6,
            pill_visibility: PillVisibility::Always,
            pill_threshold: 60,
            launch_at_login: false,
            safe_mode: true,
        }
    }
}

impl Settings {
    pub fn sanitized(mut self) -> Self {
        self.work_minutes = self.work_minutes.clamp(1, 180);
        self.break_seconds = self.break_seconds.clamp(5, 900);
        self.daily_goal = self.daily_goal.clamp(1, 100);
        self.blink_rate_threshold = self.blink_rate_threshold.clamp(1, 60);
        self.sound_volume = self.sound_volume.clamp(0.0, 1.0);
        self
    }
}
