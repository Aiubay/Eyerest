import { useState } from "react";

export type ReminderStyle = "both" | "pill" | "toast";
export type PillVisibility = "always" | "lastMinute" | "never";

export interface DemoSettings {
  workMinutes: number;
  breakSeconds: number;
  dailyGoal: number;
  reminderStyle: ReminderStyle;
  pillVisibility: PillVisibility;
  pillThreshold: number;
  soundTheme: string;
  volume: number;
  cameraEnabled: boolean;
  cameraAutoBlinks: boolean;
  blinkReminder: boolean;
  blinkThreshold: number;
  cameraPresence: boolean;
  safeMode: boolean;
  noInterrupt: boolean;
  noInterruptMax: number;
  fullscreenFallback: boolean;
  launchAtLogin: boolean;
  startMinimized: boolean;
  smartPause: boolean;
  idleSeconds: number;
  resetAwayMinutes: number;
}

const defaults: DemoSettings = {
  workMinutes: 20,
  breakSeconds: 20,
  dailyGoal: 15,
  reminderStyle: "both",
  pillVisibility: "lastMinute",
  pillThreshold: 60,
  soundTheme: "Chime",
  volume: 70,
  cameraEnabled: false,
  cameraAutoBlinks: true,
  blinkReminder: false,
  blinkThreshold: 10,
  cameraPresence: true,
  safeMode: true,
  noInterrupt: false,
  noInterruptMax: 5,
  fullscreenFallback: true,
  launchAtLogin: true,
  startMinimized: true,
  smartPause: true,
  idleSeconds: 60,
  resetAwayMinutes: 5,
};

export type SettingUpdate = <K extends keyof DemoSettings>(
  key: K,
  value: DemoSettings[K],
) => void;

export function useDemoSettings() {
  const [settings, setSettings] = useState<DemoSettings>(defaults);
  const update: SettingUpdate = (key, value) =>
    setSettings((current) => ({ ...current, [key]: value }));
  return { settings, update };
}
