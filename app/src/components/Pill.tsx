import type { CSSProperties } from "react";
import { invoke } from "@tauri-apps/api/core";
import type { DemoTimer } from "../demo/useDemoTimer";
import { isTauri } from "../state/useAppState";
import { CheckIcon, EyeIcon, MoonIcon, PauseIcon } from "./icons";
import { Ring } from "./Ring";

function formatTime(seconds: number): string {
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}

export function Pill({ timer }: { timer: DemoTimer }) {
  const expanded = timer.phase !== "working";
  const urgent = timer.urgent;
  const dim = timer.away || timer.paused;
  const compactLabel = timer.away
    ? formatTime(timer.remaining)
    : urgent
      ? `Break in ${timer.remaining}s`
      : formatTime(timer.remaining);

  return (
    <div
      className={`pill${expanded ? " expanded" : ""}${urgent ? " urgent" : ""}`}
      style={{ "--accent": timer.accent } as CSSProperties}
    >
      {expanded ? (
        <div className="card">
          {timer.phase === "done" ? (
            <div className="row">
              <Ring size={62} progress={1} color="#4ade80" label="✓" />
              <div className="txt">
                <h4>
                  <CheckIcon className="green" />
                  Nice, eyes rested.
                </h4>
                <p>
                  {timer.breaksToday} of {timer.goal} today · {timer.streak}-day
                  streak
                </p>
              </div>
            </div>
          ) : (
            <>
              <div className="row">
                <div className="breathe">
                  <Ring
                    size={62}
                    progress={timer.progress}
                    color="#4ade80"
                    label={String(timer.remaining)}
                  />
                </div>
                <div className="txt">
                  <h4>
                    <EyeIcon className="green breathe-icon" />
                    Look 20 feet away
                  </h4>
                  <p>{timer.prompt}</p>
                </div>
              </div>
              <div className="btns">
                <button
                  className={`pbtn${timer.blinks < 10 ? " pri" : ""}`}
                  onClick={timer.blink}
                >
                  {timer.blinks >= 10 ? "Blinked ✓" : `Blink ${timer.blinks}/10`}
                </button>
                <button className="pbtn" onClick={timer.skip}>
                  Skip
                </button>
                <button className="pbtn" onClick={timer.snooze}>
                  5 more min
                </button>
              </div>
            </>
          )}
        </div>
      ) : (
        <div
          className={`compact${dim ? " dim" : ""}`}
          onClick={() => {
            if (isTauri) invoke("open_settings").catch(() => {});
          }}
        >
          <span className="eye">
            {timer.away ? (
              <MoonIcon />
            ) : timer.paused ? (
              <PauseIcon />
            ) : (
              <EyeIcon />
            )}
          </span>
          <span className="time">{compactLabel}</span>
          <div className="line">
            <i style={{ width: `${timer.progress * 100}%` }} />
          </div>
        </div>
      )}
    </div>
  );
}
