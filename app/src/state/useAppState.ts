import { useCallback, useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import {
  type DemoSettings,
  type SettingUpdate,
  useDemoSettings,
} from "../demo/useDemoSettings";
import { type DemoTimer, useDemoTimer } from "../demo/useDemoTimer";

export const isTauri =
  typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

interface Snapshot {
  phase: "working" | "resting";
  remaining: number;
  running: boolean;
  autoPaused: boolean;
  deferred: boolean;
  blinks: number;
  prompt: string;
  breaksToday: number;
  goal: number;
  streak: number;
  progress: number;
  accent: string;
  cameraActive: boolean;
  safeActive: boolean;
  settings: Partial<DemoSettings>;
}

export interface AppState {
  timer: DemoTimer;
  settings: DemoSettings;
  update: SettingUpdate;
}

function useBrowserState(): AppState {
  const timer = useDemoTimer();
  const { settings, update } = useDemoSettings();
  return { timer, settings, update };
}

function useTauriState(): AppState {
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
  const [done, setDone] = useState(false);
  const { settings: base } = useDemoSettings();
  const [settings, setSettings] = useState<DemoSettings>(base);
  const doneTimer = useRef<number | null>(null);

  const apply = useCallback((next: Snapshot) => {
    setSnapshot(next);
    setSettings((current) => ({ ...current, ...next.settings }));
  }, []);

  useEffect(() => {
    invoke<Snapshot>("get_state").then(apply).catch(() => {});
    const unState = listen<Snapshot>("state", (event) => apply(event.payload));
    const unDone = listen("break-finished", () => {
      setDone(true);
      if (doneTimer.current) window.clearTimeout(doneTimer.current);
      doneTimer.current = window.setTimeout(() => setDone(false), 3000);
    });
    return () => {
      unState.then((fn) => fn());
      unDone.then((fn) => fn());
      if (doneTimer.current) window.clearTimeout(doneTimer.current);
    };
  }, [apply]);

  const act = useCallback(
    (command: string) => () => {
      invoke<Snapshot>(command).then(apply).catch(() => {});
    },
    [apply],
  );

  const update: SettingUpdate = useCallback(
    (key, value) => {
      setSettings((current) => {
        const next = { ...current, [key]: value };
        invoke<Snapshot>("set_settings", { settings: next })
          .then(apply)
          .catch(() => {});
        return next;
      });
    },
    [apply],
  );

  const phase = done ? "done" : (snapshot?.phase ?? "working");
  const remaining = snapshot?.remaining ?? 1200;
  const paused = snapshot ? !snapshot.running : false;
  const away = snapshot?.autoPaused ?? false;

  const timer: DemoTimer = {
    phase,
    remaining,
    paused,
    away,
    blinks: snapshot?.blinks ?? 0,
    breaksToday: snapshot?.breaksToday ?? 0,
    goal: snapshot?.goal ?? settings.dailyGoal,
    streak: snapshot?.streak ?? 0,
    prompt: snapshot?.prompt ?? "",
    urgent: phase === "working" && !paused && !away && remaining <= 60,
    progress: snapshot?.progress ?? 0,
    accent: snapshot?.accent ?? "#22d3ee",
    togglePaused: act("pause"),
    toggleAway: () => {},
    breakNow: act("break_now"),
    skip: act("skip"),
    snooze: act("snooze"),
    blink: act("blink"),
    finishNow: () => {},
    jumpLastMinute: () => {},
    reset: act("reset"),
  };

  return { timer, settings, update };
}

export function useAppState(): AppState {
  return isTauri ? useTauriState() : useBrowserState();
}
