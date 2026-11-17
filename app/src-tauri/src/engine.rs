use std::collections::BTreeMap;

use crate::settings::Settings;

/// Days since the Unix epoch, in the user's local timezone.
pub type DateKey = i32;

pub const IDLE_THRESHOLD: f64 = 60.0;
pub const AWAY_RESET_THRESHOLD: f64 = 300.0;
pub const SNOOZE_SECONDS: u32 = 300;

pub const PROMPTS: [&str; 7] = [
    "Look at the farthest thing you can see.",
    "Blink slowly 10 times.",
    "Roll your shoulders back.",
    "Look out a window if you can.",
    "Close your eyes and breathe out.",
    "Relax your jaw and unclench your teeth.",
    "Look left, then right, slowly.",
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Phase {
    Working,
    Resting,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Presence {
    Unknown,
    Present,
    Absent,
}

#[derive(Debug, Clone, Copy)]
pub struct TickInput {
    pub idle_seconds: f64,
    pub locked: bool,
    pub in_call: bool,
    pub face_present: Presence,
    pub today: DateKey,
}

impl Default for TickInput {
    fn default() -> Self {
        Self {
            idle_seconds: 0.0,
            locked: false,
            in_call: false,
            face_present: Presence::Unknown,
            today: 0,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Effect {
    BreakStarted,
    BreakFinished,
    BlinkGoalReached,
    CallDeferred,
}

pub struct Engine {
    pub settings: Settings,
    pub phase: Phase,
    pub remaining: u32,
    pub running: bool,
    pub auto_paused: bool,
    pub deferred: bool,
    pub blinks: u32,
    pub prompt: &'static str,
    pub prompt_index: usize,
    pub history: BTreeMap<DateKey, u32>,
    snoozed: bool,
}

impl Engine {
    pub fn new(settings: Settings, history: BTreeMap<DateKey, u32>) -> Self {
        let settings = settings.sanitized();
        Self {
            remaining: settings.work_minutes * 60,
            prompt: PROMPTS[0],
            settings,
            phase: Phase::Working,
            running: true,
            auto_paused: false,
            deferred: false,
            blinks: 0,
            prompt_index: 0,
            history,
            snoozed: false,
        }
    }

    pub fn work_seconds(&self) -> u32 {
        self.settings.work_minutes * 60
    }

    pub fn is_active(&self) -> bool {
        self.running && !self.auto_paused
    }

    pub fn label(&self) -> String {
        format!("{}:{:02}", self.remaining / 60, self.remaining % 60)
    }

    pub fn progress(&self) -> f32 {
        let total = match self.phase {
            Phase::Working => self.work_seconds(),
            Phase::Resting => self.settings.break_seconds,
        };
        1.0 - self.remaining as f32 / total.max(1) as f32
    }

    /// Advances the clock by one second.
    pub fn tick(&mut self, input: TickInput) -> Vec<Effect> {
        let mut effects = Vec::new();
        if !self.running {
            return effects;
        }

        if self.phase == Phase::Working {
            self.update_auto_pause(&input);

            if self.deferred {
                if !input.in_call {
                    self.deferred = false;
                    self.start_rest(&mut effects);
                }
                return effects;
            }

            if self.auto_paused {
                return effects;
            }
        }

        self.remaining = self.remaining.saturating_sub(1);
        if self.remaining > 0 {
            return effects;
        }

        match self.phase {
            Phase::Working => {
                if self.settings.wait_in_calls && input.in_call {
                    self.deferred = true;
                    effects.push(Effect::CallDeferred);
                } else {
                    self.start_rest(&mut effects);
                }
            }
            Phase::Resting => self.finish_rest(&input, &mut effects),
        }

        effects
    }

    fn update_auto_pause(&mut self, input: &TickInput) {
        if !self.settings.smart_pause {
            self.auto_paused = false;
            return;
        }

        let away = input.locked || input.idle_seconds >= IDLE_THRESHOLD;
        if !away {
            self.auto_paused = false;
            return;
        }

        if !input.locked && self.settings.camera_enabled && self.settings.camera_presence_pause {
            if input.face_present == Presence::Present {
                self.auto_paused = false;
                return;
            }
        }

        self.auto_paused = true;
        if input.idle_seconds >= AWAY_RESET_THRESHOLD {
            self.remaining = self.work_seconds();
        }
    }

    fn start_rest(&mut self, effects: &mut Vec<Effect>) {
        self.phase = Phase::Resting;
        self.remaining = self.settings.break_seconds;
        self.running = true;
        self.deferred = false;
        self.snoozed = false;
        self.auto_paused = false;
        self.blinks = 0;
        self.prompt = PROMPTS[self.prompt_index % PROMPTS.len()];
        self.prompt_index = self.prompt_index.wrapping_add(1);
        effects.push(Effect::BreakStarted);
    }

    fn finish_rest(&mut self, input: &TickInput, effects: &mut Vec<Effect>) {
        *self.history.entry(input.today).or_insert(0) += 1;
        self.phase = Phase::Working;
        self.remaining = self.work_seconds();
        effects.push(Effect::BreakFinished);
    }

    pub fn toggle_running(&mut self) {
        self.running = !self.running;
    }

    pub fn break_now(&mut self) -> Vec<Effect> {
        let mut effects = Vec::new();
        self.start_rest(&mut effects);
        effects
    }

    pub fn skip(&mut self) {
        self.phase = Phase::Working;
        self.remaining = self.work_seconds();
        self.deferred = false;
        self.snoozed = false;
        self.blinks = 0;
    }

    pub fn snooze(&mut self) {
        self.phase = Phase::Working;
        self.remaining = SNOOZE_SECONDS;
        self.deferred = false;
        self.snoozed = true;
        self.blinks = 0;
    }

    pub fn reset(&mut self) {
        self.phase = Phase::Working;
        self.remaining = self.work_seconds();
        self.running = true;
        self.auto_paused = false;
        self.deferred = false;
        self.snoozed = false;
        self.blinks = 0;
    }

    pub fn blink(&mut self) -> Vec<Effect> {
        if self.phase != Phase::Resting {
            return Vec::new();
        }
        self.blinks += 1;
        if self.blinks == 10 {
            return vec![Effect::BlinkGoalReached];
        }
        Vec::new()
    }

    pub fn set_work_minutes(&mut self, minutes: u32) {
        self.settings.work_minutes = minutes.clamp(1, 180);
        if self.phase == Phase::Working && !self.snoozed && !self.deferred {
            self.remaining = self.work_seconds();
        }
    }

    pub fn set_break_seconds(&mut self, seconds: u32) {
        self.settings.break_seconds = seconds.clamp(5, 900);
    }

    pub fn breaks_today(&self, today: DateKey) -> u32 {
        self.history.get(&today).copied().unwrap_or(0)
    }

    pub fn streak(&self, today: DateKey) -> u32 {
        let mut day = today;
        if self.breaks_today(day) == 0 {
            day -= 1;
        }
        let mut count = 0;
        while self.breaks_today(day) > 0 {
            count += 1;
            day -= 1;
        }
        count
    }

    pub fn last_seven_days(&self, today: DateKey) -> Vec<(DateKey, u32)> {
        (0..7)
            .rev()
            .map(|offset| {
                let day = today - offset;
                (day, self.breaks_today(day))
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn settings(work_minutes: u32, break_seconds: u32) -> Settings {
        Settings {
            work_minutes,
            break_seconds,
            ..Settings::default()
        }
    }

    fn active() -> TickInput {
        TickInput::default()
    }

    fn idle(seconds: f64) -> TickInput {
        TickInput {
            idle_seconds: seconds,
            ..TickInput::default()
        }
    }

    fn ticks(engine: &mut Engine, input: TickInput, n: usize) -> Vec<Effect> {
        let mut effects = Vec::new();
        for _ in 0..n {
            effects.extend(engine.tick(input));
        }
        effects
    }

    #[test]
    fn counts_down_one_second_per_tick() {
        let mut engine = Engine::new(settings(1, 5), BTreeMap::new());
        assert_eq!(engine.remaining, 60);
        ticks(&mut engine, active(), 59);
        assert_eq!(engine.remaining, 1);
        assert_eq!(engine.phase, Phase::Working);
    }

    #[test]
    fn break_starts_after_work_time() {
        let mut engine = Engine::new(settings(1, 5), BTreeMap::new());
        let effects = ticks(&mut engine, active(), 60);
        assert!(effects.contains(&Effect::BreakStarted));
        assert_eq!(engine.phase, Phase::Resting);
        assert_eq!(engine.remaining, 5);
        assert_eq!(engine.blinks, 0);
        assert_eq!(engine.prompt, PROMPTS[0]);
    }

    #[test]
    fn break_finishes_and_records_history() {
        let mut engine = Engine::new(settings(1, 5), BTreeMap::new());
        ticks(&mut engine, active(), 60);
        let effects = ticks(&mut engine, active(), 5);
        assert!(effects.contains(&Effect::BreakFinished));
        assert_eq!(engine.phase, Phase::Working);
        assert_eq!(engine.remaining, 60);
        assert_eq!(engine.breaks_today(0), 1);
    }

    #[test]
    fn prompts_rotate_between_breaks() {
        let mut engine = Engine::new(settings(1, 5), BTreeMap::new());
        ticks(&mut engine, active(), 65);
        ticks(&mut engine, active(), 60);
        assert_eq!(engine.phase, Phase::Resting);
        assert_eq!(engine.prompt, PROMPTS[1]);
    }

    #[test]
    fn snooze_sets_five_minutes() {
        let mut engine = Engine::new(settings(1, 5), BTreeMap::new());
        ticks(&mut engine, active(), 60);
        engine.snooze();
        assert_eq!(engine.phase, Phase::Working);
        assert_eq!(engine.remaining, SNOOZE_SECONDS);
    }

    #[test]
    fn skip_returns_to_work() {
        let mut engine = Engine::new(settings(1, 5), BTreeMap::new());
        ticks(&mut engine, active(), 60);
        engine.skip();
        assert_eq!(engine.phase, Phase::Working);
        assert_eq!(engine.remaining, 60);
    }

    #[test]
    fn smart_pause_holds_then_resumes() {
        let mut engine = Engine::new(settings(2, 5), BTreeMap::new());
        ticks(&mut engine, active(), 10);
        ticks(&mut engine, idle(61.0), 30);
        assert!(engine.auto_paused);
        assert_eq!(engine.remaining, 110);
        ticks(&mut engine, active(), 1);
        assert!(!engine.auto_paused);
        assert_eq!(engine.remaining, 109);
    }

    #[test]
    fn away_for_five_minutes_resets_work_timer() {
        let mut engine = Engine::new(settings(2, 5), BTreeMap::new());
        ticks(&mut engine, active(), 10);
        ticks(&mut engine, idle(301.0), 1);
        assert_eq!(engine.remaining, 120);
    }

    #[test]
    fn camera_presence_keeps_timer_running_while_idle() {
        let mut config = settings(2, 5);
        config.camera_enabled = true;
        let mut engine = Engine::new(config, BTreeMap::new());
        ticks(&mut engine, active(), 10);
        let presence = TickInput {
            idle_seconds: 90.0,
            face_present: Presence::Present,
            ..TickInput::default()
        };
        ticks(&mut engine, presence, 5);
        assert!(!engine.auto_paused);
        assert_eq!(engine.remaining, 105);
    }

    #[test]
    fn camera_absence_pauses() {
        let mut config = settings(2, 5);
        config.camera_enabled = true;
        let mut engine = Engine::new(config, BTreeMap::new());
        ticks(&mut engine, active(), 10);
        let presence = TickInput {
            idle_seconds: 90.0,
            face_present: Presence::Absent,
            ..TickInput::default()
        };
        ticks(&mut engine, presence, 5);
        assert!(engine.auto_paused);
        assert_eq!(engine.remaining, 110);
    }

    #[test]
    fn call_defers_break_until_it_ends() {
        let mut engine = Engine::new(settings(1, 5), BTreeMap::new());
        let in_call = TickInput {
            in_call: true,
            ..TickInput::default()
        };
        let effects = ticks(&mut engine, in_call, 60);
        assert!(effects.contains(&Effect::CallDeferred));
        assert!(engine.deferred);
        assert_eq!(engine.phase, Phase::Working);

        ticks(&mut engine, in_call, 5);
        assert!(engine.deferred);
        assert_eq!(engine.phase, Phase::Working);

        let effects = ticks(&mut engine, active(), 1);
        assert!(effects.contains(&Effect::BreakStarted));
        assert_eq!(engine.phase, Phase::Resting);
    }

    #[test]
    fn call_is_ignored_when_wait_in_calls_is_off() {
        let mut config = settings(1, 5);
        config.wait_in_calls = false;
        let mut engine = Engine::new(config, BTreeMap::new());
        let in_call = TickInput {
            in_call: true,
            ..TickInput::default()
        };
        let effects = ticks(&mut engine, in_call, 60);
        assert!(effects.contains(&Effect::BreakStarted));
        assert!(!engine.deferred);
    }

    #[test]
    fn blink_goal_reached_at_ten() {
        let mut engine = Engine::new(settings(1, 5), BTreeMap::new());
        ticks(&mut engine, active(), 60);
        for _ in 0..9 {
            assert!(engine.blink().is_empty());
        }
        assert_eq!(engine.blink(), vec![Effect::BlinkGoalReached]);
        assert_eq!(engine.blinks, 10);
    }

    #[test]
    fn blink_ignored_while_working() {
        let mut engine = Engine::new(settings(1, 5), BTreeMap::new());
        assert!(engine.blink().is_empty());
        assert_eq!(engine.blinks, 0);
    }

    #[test]
    fn streak_counts_consecutive_days() {
        let mut history = BTreeMap::new();
        history.insert(98, 1);
        history.insert(99, 2);
        history.insert(100, 1);
        let engine = Engine::new(settings(20, 20), history);
        assert_eq!(engine.streak(100), 3);
        assert_eq!(engine.streak(101), 3);
        assert_eq!(engine.streak(103), 0);
    }

    #[test]
    fn last_seven_days_are_ordered_oldest_first() {
        let mut history = BTreeMap::new();
        history.insert(99, 2);
        let engine = Engine::new(settings(20, 20), history);
        let days = engine.last_seven_days(100);
        assert_eq!(days.len(), 7);
        assert_eq!(days[0].0, 94);
        assert_eq!(days[5], (99, 2));
        assert_eq!(days[6], (100, 0));
    }

    #[test]
    fn constructor_clamps_out_of_range_settings() {
        let config = Settings {
            work_minutes: 0,
            break_seconds: 1,
            ..Settings::default()
        };
        let engine = Engine::new(config, BTreeMap::new());
        assert_eq!(engine.settings.work_minutes, 1);
        assert_eq!(engine.settings.break_seconds, 5);
    }

    #[test]
    fn changing_work_length_updates_remaining() {
        let mut engine = Engine::new(settings(1, 5), BTreeMap::new());
        engine.set_work_minutes(30);
        assert_eq!(engine.remaining, 1800);
    }

    #[test]
    fn paused_timer_does_not_count_down() {
        let mut engine = Engine::new(settings(1, 5), BTreeMap::new());
        engine.toggle_running();
        ticks(&mut engine, active(), 5);
        assert_eq!(engine.remaining, 60);
        engine.toggle_running();
        ticks(&mut engine, active(), 1);
        assert_eq!(engine.remaining, 59);
    }
}
