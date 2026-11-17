import type { ReactNode } from "react";
import { useState } from "react";
import {
  AlertRegular,
  CameraRegular,
  CheckmarkCircleRegular,
  ClockRegular,
  DataBarVerticalRegular,
  EditRegular,
  EyeRegular,
  InfoRegular,
  KeyboardRegular,
  PowerRegular,
  SearchRegular,
  ShieldRegular,
  Speaker2Regular,
} from "@fluentui/react-icons";
import {
  Button,
  Dialog,
  DialogActions,
  DialogBody,
  DialogContent,
  DialogSurface,
  DialogTitle,
  Dropdown,
  Input,
  Option,
  ProgressBar,
  Slider,
  Switch,
} from "@fluentui/react-components";
import { Ring } from "../components/Ring";
import type { DemoSettings, PillVisibility, ReminderStyle, SettingUpdate } from "../demo/useDemoSettings";
import type { DemoTimer } from "../demo/useDemoTimer";

const PAGES = [
  "timer",
  "reminders",
  "stats",
  "camera",
  "hotkeys",
  "games",
  "startup",
  "about",
] as const;

type PageId = (typeof PAGES)[number];

function isPageId(value: string | null): value is PageId {
  return value !== null && (PAGES as readonly string[]).includes(value);
}

function initialPage(): PageId {
  const page = new URLSearchParams(window.location.search).get("page");
  return isPageId(page) ? page : "timer";
}

function formatTime(seconds: number): string {
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}

function NumberInput({
  value,
  unit,
  min,
  max,
  onChange,
}: {
  value: number;
  unit?: string;
  min: number;
  max: number;
  onChange: (value: number) => void;
}) {
  return (
    <span className="num-field">
      <Input
        type="number"
        value={String(value)}
        min={min}
        max={max}
        onChange={(_, data) => {
          const parsed = Number.parseInt(data.value, 10);
          if (!Number.isNaN(parsed)) onChange(Math.min(max, Math.max(min, parsed)));
        }}
      />
      {unit && <span className="num-unit">{unit}</span>}
    </span>
  );
}

function Toggle({
  checked,
  onChange,
  disabled,
}: {
  checked: boolean;
  onChange: (checked: boolean) => void;
  disabled?: boolean;
}) {
  return (
    <Switch
      checked={checked}
      disabled={disabled}
      onChange={(_, data) => onChange(data.checked)}
    />
  );
}

function SettingCard({
  icon,
  title,
  description,
  children,
  hero,
}: {
  icon?: ReactNode;
  title: string;
  description?: string;
  children?: ReactNode;
  hero?: boolean;
}) {
  return (
    <div className={`scard${hero ? " hero" : ""}`}>
      {icon && <span className="scard-icon">{icon}</span>}
      <div className="t">
        <b>{title}</b>
        {description && <small>{description}</small>}
      </div>
      {children && <div className="ctl">{children}</div>}
    </div>
  );
}

function InfoCard({
  tone = "info",
  icon,
  title,
  children,
}: {
  tone?: "info" | "ok" | "warn";
  icon: ReactNode;
  title: string;
  children: ReactNode;
}) {
  return (
    <div className={`info ${tone}`}>
      {icon}
      <div>
        <b>{title}</b>
        {children}
      </div>
    </div>
  );
}

function Page({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="page">
      <h1>{title}</h1>
      <div className="stack">{children}</div>
    </div>
  );
}

function statusWord(timer: DemoTimer): string {
  if (timer.phase === "resting") return "BREAK";
  if (timer.paused) return "PAUSED";
  if (timer.away) return "AWAY";
  return "WORKING";
}

function statusMessage(timer: DemoTimer): string {
  if (timer.phase === "resting") return "Look at something far away.";
  if (timer.paused) return "Paused. I'll wait for you.";
  if (timer.away) return "You stepped away. I'll resume when you're back.";
  const minutes = Math.ceil(timer.remaining / 60);
  return `You've got ${minutes} minute${minutes === 1 ? "" : "s"}. I'll nudge you.`;
}

type PageProps = {
  timer: DemoTimer;
  settings: DemoSettings;
  update: SettingUpdate;
};

function TimerPage({ timer, settings, update }: PageProps) {
  return (
    <Page title="Timer">
      <div className="scard hero">
        <Ring
          size={104}
          progress={timer.progress}
          color={timer.accent}
          label={timer.phase === "resting" ? String(timer.remaining) : formatTime(timer.remaining)}
          fontSize={24}
        />
        <div className="hero-text">
          <small>{statusWord(timer)}</small>
          <div>{statusMessage(timer)}</div>
          <span>
            {timer.breaksToday} of {timer.goal} breaks today.
          </span>
          <div className="btns">
            <Button appearance="primary" onClick={timer.togglePaused}>
              {timer.paused ? "Resume" : "Pause"}
            </Button>
            <Button onClick={timer.breakNow}>Break now</Button>
            <Button onClick={timer.reset}>Reset</Button>
          </div>
        </div>
      </div>

      <h3>Cycle</h3>
      <SettingCard
        icon={<ClockRegular />}
        title="Work length"
        description="Time between breaks"
      >
        <NumberInput
          value={settings.workMinutes}
          unit="min"
          min={1}
          max={180}
          onChange={(value) => update("workMinutes", value)}
        />
      </SettingCard>
      <SettingCard
        icon={<EyeRegular />}
        title="Break length"
        description="How long you look away"
      >
        <NumberInput
          value={settings.breakSeconds}
          unit="sec"
          min={5}
          max={300}
          onChange={(value) => update("breakSeconds", value)}
        />
      </SettingCard>
      <SettingCard
        icon={<DataBarVerticalRegular />}
        title="Daily goal"
        description="Breaks per day"
      >
        <NumberInput
          value={settings.dailyGoal}
          min={1}
          max={100}
          onChange={(value) => update("dailyGoal", value)}
        />
      </SettingCard>
    </Page>
  );
}

function RemindersPage({ settings, update }: PageProps) {
  const playPreview = () => {
    const context = new AudioContext();
    const oscillator = context.createOscillator();
    const gain = context.createGain();
    oscillator.frequency.value = 880;
    gain.gain.setValueAtTime(0.08, context.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, context.currentTime + 0.18);
    oscillator.connect(gain).connect(context.destination);
    oscillator.start();
    oscillator.stop(context.currentTime + 0.2);
    oscillator.onended = () => context.close();
  };

  return (
    <Page title="Reminders">
      <SettingCard
        icon={<AlertRegular />}
        title="Reminder style"
        description="How EyeRule tells you it is break time"
      >
        <Dropdown
          className="dd"
          value={
            settings.reminderStyle === "both"
              ? "Pill and toast"
              : settings.reminderStyle === "pill"
                ? "Pill only"
                : "Toast only"
          }
          selectedOptions={[settings.reminderStyle]}
          onOptionSelect={(_, data) =>
            data.optionValue &&
            update("reminderStyle", data.optionValue as ReminderStyle)
          }
        >
          <Option value="both">Pill and toast</Option>
          <Option value="pill">Pill only</Option>
          <Option value="toast">Toast only</Option>
        </Dropdown>
      </SettingCard>

      <SettingCard
        icon={<EyeRegular />}
        title="Pill visibility"
        description="Breaks always show the card, except in anti-cheat safe mode"
      >
        <Dropdown
          className="dd wide"
          value={
            settings.pillVisibility === "always"
              ? "Always"
              : settings.pillVisibility === "lastMinute"
                ? "Only in the last minute"
                : "Never (tray only)"
          }
          selectedOptions={[settings.pillVisibility]}
          onOptionSelect={(_, data) =>
            data.optionValue &&
            update("pillVisibility", data.optionValue as PillVisibility)
          }
        >
          <Option value="always">Always</Option>
          <Option value="lastMinute">Only in the last minute</Option>
          <Option value="never">Never (tray only)</Option>
        </Dropdown>
      </SettingCard>

      <SettingCard
        icon={<ClockRegular />}
        title="Show the pill when this much time is left"
        description='Used by "Only in the last minute"'
      >
        <NumberInput
          value={settings.pillThreshold}
          unit="sec"
          min={10}
          max={600}
          onChange={(value) => update("pillThreshold", value)}
        />
      </SettingCard>

      <InfoCard tone="info" icon={<InfoRegular />} title="Other choices">
        Always show the pill, only in the last minute (and during breaks), or
        never. The tray flyout always works.
      </InfoCard>

      <h3>Sound</h3>
      <SettingCard
        icon={<Speaker2Regular />}
        title="Sound theme"
        description="Plays at the start and end of a break"
      >
        <Button onClick={playPreview}>Preview</Button>
        <Dropdown
          className="dd"
          value={settings.soundTheme}
          selectedOptions={[settings.soundTheme]}
          onOptionSelect={(_, data) =>
            data.optionValue && update("soundTheme", data.optionValue)
          }
        >
          <Option value="Chime">Chime</Option>
          <Option value="Water drop">Water drop</Option>
          <Option value="Soft">Soft</Option>
          <Option value="Silent">Silent</Option>
        </Dropdown>
      </SettingCard>
      <SettingCard icon={<Speaker2Regular />} title="Volume">
        <Slider
          className="volume"
          min={0}
          max={100}
          value={settings.volume}
          onChange={(_, data) => update("volume", data.value)}
        />
        <span className="value">{settings.volume}</span>
      </SettingCard>
    </Page>
  );
}

function StatsPage({ timer, settings }: PageProps) {
  const week = [6, 9, 4, 12, 8, 3, timer.breaksToday];
  const labels = ["M", "T", "W", "T", "F", "S", "S"];
  const max = Math.max(...week, settings.dailyGoal, 1);

  return (
    <Page title="Stats">
      <SettingCard
        icon={<DataBarVerticalRegular />}
        title={`${timer.breaksToday} of ${settings.dailyGoal} breaks today`}
        description="Daily goal"
      >
        <ProgressBar
          className="goal-bar"
          value={Math.min(1, timer.breaksToday / Math.max(settings.dailyGoal, 1))}
        />
      </SettingCard>
      <SettingCard
        icon={<ClockRegular />}
        title={`${timer.streak}-day streak`}
        description="At least one break each day"
      />
      <div className="scard column">
        <b className="card-title">Last 7 days</b>
        <div className="bars">
          {week.map((value, index) => (
            <div key={index} className={index === week.length - 1 ? "today" : ""}>
              <i style={{ height: `${Math.max(6, (value / max) * 100)}%` }} />
              {labels[index]}
            </div>
          ))}
        </div>
      </div>
      <SettingCard
        icon={<EyeRegular />}
        title="Blinks per minute"
        description="Needs the camera tracker. Healthy range is about 15 to 20."
      >
        <span className="stat-number">14</span>
        <span className="stat-note">avg this week</span>
      </SettingCard>
    </Page>
  );
}

function CameraPage({ settings, update }: PageProps) {
  return (
    <Page title="Camera">
      <InfoCard tone="info" icon={<InfoRegular />} title="Optional and off by default">
        Analysis runs on this PC. No video is saved or sent. Only numbers like
        blinks per minute are kept. The camera light is on while it is active.
      </InfoCard>

      <SettingCard
        icon={<CameraRegular />}
        title="Enable camera eye tracker"
        description="Counts blinks and checks that you are at the screen"
      >
        <Toggle
          checked={settings.cameraEnabled}
          onChange={(value) => update("cameraEnabled", value)}
        />
      </SettingCard>

      <h3>Features</h3>
      <SettingCard
        icon={<EyeRegular />}
        title="Count blinks automatically"
        description="Replaces the Blink button during breaks"
      >
        <Toggle
          checked={settings.cameraAutoBlinks}
          disabled={!settings.cameraEnabled}
          onChange={(value) => update("cameraAutoBlinks", value)}
        />
      </SettingCard>
      <SettingCard
        icon={<AlertRegular />}
        title="Blink-rate reminder"
        description='Show "Blink more" when blinks per minute fall below'
      >
        <NumberInput
          value={settings.blinkThreshold}
          unit="/min"
          min={1}
          max={60}
          onChange={(value) => update("blinkThreshold", value)}
        />
        <Toggle
          checked={settings.blinkReminder}
          disabled={!settings.cameraEnabled}
          onChange={(value) => update("blinkReminder", value)}
        />
      </SettingCard>
      <SettingCard
        icon={<ClockRegular />}
        title="Face presence for smart pause"
        description="Pause the timer when no face is in front of the screen"
      >
        <Toggle
          checked={settings.cameraPresence}
          disabled={!settings.cameraEnabled}
          onChange={(value) => update("cameraPresence", value)}
        />
      </SettingCard>

      <h3>Status</h3>
      <SettingCard
        icon={<CameraRegular />}
        title={settings.cameraEnabled ? "Camera: waiting for the Windows build" : "Camera: off"}
        description={
          settings.cameraEnabled
            ? "The tracker starts with the first break. Status will show the device and blink rate here."
            : "Turn the tracker on to count blinks during breaks."
        }
      />
    </Page>
  );
}

const HOTKEYS: Array<[string, string, string[]]> = [
  ["Skip break", "Skip the current break", ["Ctrl", "Alt", "S"]],
  ["5 more minutes", "Postpone the break", ["Ctrl", "Alt", "M"]],
  ["Count a blink", "Blink counter +1 (when the camera is off)", ["Ctrl", "Alt", "B"]],
  ["Open settings", "Show or hide this window", ["Ctrl", "Alt", "E"]],
];

function HotkeysPage({ onEdit }: { onEdit: (name: string) => void }) {
  return (
    <Page title="Hotkeys">
      <InfoCard tone="info" icon={<InfoRegular />} title="For games where the mouse is captured">
        These work even when EyeRule is not in front. A shortcut needs at least
        one modifier key.
      </InfoCard>
      {HOTKEYS.map(([name, description, keys]) => (
        <SettingCard key={name} icon={<KeyboardRegular />} title={name} description={description}>
          <span className="keycaps">
            {keys.map((key) => (
              <span key={key} className="keycap">
                {key}
              </span>
            ))}
          </span>
          <Button
            appearance="subtle"
            icon={<EditRegular />}
            aria-label={`Edit ${name}`}
            onClick={() => onEdit(name)}
          />
        </SettingCard>
      ))}
    </Page>
  );
}

function GamesPage({ settings, update }: PageProps) {
  return (
    <Page title="Games and safety">
      <InfoCard tone="ok" icon={<CheckmarkCircleRegular />} title="Anti-cheat safe mode is on">
        When an anti-cheat is running, the overlay, hotkeys and camera turn off.
        You get a sound and a tray notification instead.
      </InfoCard>

      <SettingCard
        icon={<ShieldRegular />}
        title="Anti-cheat safe mode"
        description="Recommended for CS2, Dead by Daylight and Black Desert"
      >
        <Toggle
          checked={settings.safeMode}
          onChange={(value) => update("safeMode", value)}
        />
      </SettingCard>
      <SettingCard
        icon={<ShieldRegular />}
        title="Currently detected"
        description="Checked every few seconds"
      >
        <span className="chip">none</span>
      </SettingCard>

      <h3>Never show the overlay for these games</h3>
      <div className="scard column">
        <div className="chips">
          <span className="chip">cs2.exe</span>
          <span className="chip">DeadByDaylight-Win64-Shipping.exe</span>
          <span className="chip">BlackDesert64.exe</span>
        </div>
        <small className="note">
          File names to confirm in Task Manager while each game runs. CS2 uses
          Valve's VAC, which has no separate process to detect.
        </small>
      </div>

      <h3>Other</h3>
      <SettingCard
        icon={<ShieldRegular />}
        title="Don't interrupt while I play"
        description="Delay the break while a fullscreen game is active"
      >
        <NumberInput
          value={settings.noInterruptMax}
          unit="min max"
          min={0}
          max={5}
          onChange={(value) => update("noInterruptMax", value)}
        />
        <Toggle
          checked={settings.noInterrupt}
          onChange={(value) => update("noInterrupt", value)}
        />
      </SettingCard>
      <SettingCard
        icon={<AlertRegular />}
        title="Exclusive fullscreen fallback"
        description="No overlay can show. Play a sound and flash the taskbar"
      >
        <Toggle
          checked={settings.fullscreenFallback}
          onChange={(value) => update("fullscreenFallback", value)}
        />
      </SettingCard>
    </Page>
  );
}

function StartupPage({ settings, update }: PageProps) {
  return (
    <Page title="Startup and behavior">
      <SettingCard icon={<PowerRegular />} title="Launch at login" description="Start EyeRule when you sign in to Windows">
        <Toggle
          checked={settings.launchAtLogin}
          onChange={(value) => update("launchAtLogin", value)}
        />
      </SettingCard>
      <SettingCard icon={<EyeRegular />} title="Start minimized to the tray">
        <Toggle
          checked={settings.startMinimized}
          onChange={(value) => update("startMinimized", value)}
        />
      </SettingCard>

      <h3>Smart pause</h3>
      <SettingCard
        icon={<ClockRegular />}
        title="Pause when I am away"
        description="Hold the timer while the PC is idle or locked"
      >
        <Toggle
          checked={settings.smartPause}
          onChange={(value) => update("smartPause", value)}
        />
      </SettingCard>
      <SettingCard icon={<ClockRegular />} title="Idle time before pausing">
        <NumberInput
          value={settings.idleSeconds}
          unit="sec"
          min={10}
          max={600}
          onChange={(value) => update("idleSeconds", value)}
        />
      </SettingCard>
      <SettingCard
        icon={<ClockRegular />}
        title="Reset the timer after being away"
        description="Time away that counts as a rest"
      >
        <NumberInput
          value={settings.resetAwayMinutes}
          unit="min"
          min={1}
          max={60}
          onChange={(value) => update("resetAwayMinutes", value)}
        />
      </SettingCard>
    </Page>
  );
}

function AboutPage() {
  return (
    <Page title="About">
      <SettingCard
        icon={<EyeRegular />}
        title="EyeRule"
        description="Version 0.1 preview. 20-20-20 eye rest reminder."
      />
      <SettingCard
        icon={<InfoRegular />}
        title="Privacy"
        description="Everything stays on this PC. No account, no cloud."
      />
    </Page>
  );
}

export function SettingsWindow({
  timer,
  settings,
  update,
}: {
  timer: DemoTimer;
  settings: DemoSettings;
  update: SettingUpdate;
}) {
  const [page, setPage] = useState<PageId>(initialPage);
  const [shortcut, setShortcut] = useState<string | null>(null);

  const props: PageProps = { timer, settings, update };

  const nav: Array<{ id: PageId; label: string; icon: ReactNode }> = [
    { id: "timer", label: "Timer", icon: <ClockRegular /> },
    { id: "reminders", label: "Reminders", icon: <AlertRegular /> },
    { id: "stats", label: "Stats", icon: <DataBarVerticalRegular /> },
    { id: "camera", label: "Camera", icon: <CameraRegular /> },
    { id: "hotkeys", label: "Hotkeys", icon: <KeyboardRegular /> },
    { id: "games", label: "Games and safety", icon: <ShieldRegular /> },
    { id: "startup", label: "Startup and behavior", icon: <PowerRegular /> },
  ];

  return (
    <>
      <div className="win">
        <div className="win-titlebar">
          <EyeRegular className="win-logo" />
          <span>EyeRule</span>
          <div className="win-controls">
            <span>—</span>
            <span>▢</span>
            <span className="close">✕</span>
          </div>
        </div>
        <div className="win-body">
          <nav className="win-nav">
            <div className="win-search">
              <SearchRegular />
              <span>Search settings</span>
            </div>
            {nav.map((item) => (
              <button
                key={item.id}
                className={`navi${page === item.id ? " sel" : ""}`}
                onClick={() => setPage(item.id)}
              >
                {item.icon}
                <span>{item.label}</span>
              </button>
            ))}
            <div className="nav-spacer" />
            <button
              className={`navi${page === "about" ? " sel" : ""}`}
              onClick={() => setPage("about")}
            >
              <InfoRegular />
              <span>About</span>
            </button>
          </nav>
          <main className="win-content">
            {page === "timer" && <TimerPage {...props} />}
            {page === "reminders" && <RemindersPage {...props} />}
            {page === "stats" && <StatsPage {...props} />}
            {page === "camera" && <CameraPage {...props} />}
            {page === "hotkeys" && <HotkeysPage onEdit={setShortcut} />}
            {page === "games" && <GamesPage {...props} />}
            {page === "startup" && <StartupPage {...props} />}
            {page === "about" && <AboutPage />}
          </main>
        </div>
      </div>

      <Dialog
        open={shortcut !== null}
        onOpenChange={(_, data) => {
          if (!data.open) setShortcut(null);
        }}
      >
        <DialogSurface>
          <DialogBody>
            <DialogTitle>Press a shortcut</DialogTitle>
            <DialogContent>
              <p className="dialog-text">
                Hold the modifier keys, then press a key.
                {shortcut ? ` Setting: ${shortcut}.` : ""}
              </p>
              <div className="keybox">
                {["Ctrl", "Alt", "S"].map((key) => (
                  <span key={key} className="keycap">
                    {key}
                  </span>
                ))}
              </div>
              <small className="dialog-note">Ctrl + Alt + S is free.</small>
            </DialogContent>
            <DialogActions>
              <Button appearance="primary" onClick={() => setShortcut(null)}>
                Save
              </Button>
              <Button onClick={() => setShortcut(null)}>Cancel</Button>
            </DialogActions>
          </DialogBody>
        </DialogSurface>
      </Dialog>
    </>
  );
}
