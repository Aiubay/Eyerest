import { useEffect, useState } from "react";

export type Phase = "working" | "resting" | "done";

export const WORK_SECONDS = 20 * 60;
export const BREAK_SECONDS = 20;

const PROMPTS = [
  "Blink slowly 10 times.",
  "Look at the farthest thing you can see.",
  "Roll your shoulders back.",
  "Look out a window if you can.",
  "Close your eyes and breathe out.",
];

export interface DemoTimer {
  phase: Phase;
  remaining: number;
  paused: boolean;
  away: boolean;
  blinks: number;
  breaksToday: number;
  goal: number;
  streak: number;
  prompt: string;
  urgent: boolean;
  progress: number;
  accent: string;
  togglePaused: () => void;
  toggleAway: () => void;
  breakNow: () => void;
  skip: () => void;
  snooze: () => void;
  blink: () => void;
  finishNow: () => void;
  jumpLastMinute: () => void;
  reset: () => void;
}

function accentFor(phase: Phase, remaining: number): string {
  if (phase !== "working") return "#4ade80";
  if (remaining <= 60) return "#fb923c";
  if (remaining <= 300) return "#facc15";
  const hour = new Date().getHours();
  if (hour >= 5 && hour < 17) return "#22d3ee";
  if (hour >= 17 && hour < 21) return "#c7a0ff";
  return "#8c99ff";
}

export interface DemoStart {
  phase?: Phase;
  remaining?: number;
  away?: boolean;
  paused?: boolean;
}

export function useDemoTimer(start: DemoStart = {}): DemoTimer {
  const [phase, setPhase] = useState<Phase>(start.phase ?? "working");
  const [remaining, setRemaining] = useState(start.remaining ?? WORK_SECONDS);
  const [paused, setPaused] = useState(start.paused ?? false);
  const [away, setAway] = useState(start.away ?? false);
  const [blinks, setBlinks] = useState(0);
  const [breaksToday, setBreaksToday] = useState(7);
  const [promptIndex, setPromptIndex] = useState(0);

  useEffect(() => {
    const id = window.setInterval(() => {
      if (paused || away || phase === "done") return;
      setRemaining((value) => (value > 0 ? value - 1 : value));
    }, 1000);
    return () => window.clearInterval(id);
  }, [paused, away, phase]);

  useEffect(() => {
    if (remaining > 0) return;
    if (phase === "working") {
      setPhase("resting");
      setRemaining(BREAK_SECONDS);
      setBlinks(0);
      setPromptIndex((index) => index + 1);
    } else if (phase === "resting") {
      setPhase("done");
      setBreaksToday((count) => count + 1);
    }
  }, [remaining, phase]);

  useEffect(() => {
    if (phase !== "done") return;
    const id = window.setTimeout(() => {
      setPhase("working");
      setRemaining(WORK_SECONDS);
    }, 3000);
    return () => window.clearTimeout(id);
  }, [phase]);

  const total = phase === "resting" ? BREAK_SECONDS : WORK_SECONDS;
  const progress =
    phase === "done" ? 1 : Math.min(1, Math.max(0, 1 - remaining / total));

  return {
    phase,
    remaining,
    paused,
    away,
    blinks,
    breaksToday,
    goal: 15,
    streak: 3,
    prompt: PROMPTS[promptIndex % PROMPTS.length],
    urgent: phase === "working" && !paused && !away && remaining <= 60,
    progress,
    accent: accentFor(phase, remaining),
    togglePaused: () => setPaused((value) => !value),
    toggleAway: () => setAway((value) => !value),
    breakNow: () => {
      setPhase("resting");
      setRemaining(BREAK_SECONDS);
      setBlinks(0);
      setAway(false);
      setPromptIndex((index) => index + 1);
    },
    skip: () => {
      setPhase("working");
      setRemaining(WORK_SECONDS);
      setBlinks(0);
      setAway(false);
    },
    snooze: () => {
      setPhase("working");
      setRemaining(300);
      setBlinks(0);
    },
    blink: () => {
      if (phase === "resting") setBlinks((count) => count + 1);
    },
    finishNow: () => {
      if (phase === "resting") setRemaining(0);
    },
    jumpLastMinute: () => {
      setPhase("working");
      setRemaining(45);
      setPaused(false);
      setAway(false);
    },
    reset: () => {
      setPhase("working");
      setRemaining(WORK_SECONDS);
      setPaused(false);
      setAway(false);
      setBlinks(0);
    },
  };
}
