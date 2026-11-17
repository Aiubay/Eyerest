import { Button } from "@fluentui/react-components";
import { invoke } from "@tauri-apps/api/core";
import type { DemoTimer } from "../demo/useDemoTimer";
import { isTauri } from "../state/useAppState";
import { Ring } from "./Ring";

function formatTime(seconds: number): string {
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}

export function TrayFlyout({ timer }: { timer: DemoTimer }) {
  const status =
    timer.phase === "resting"
      ? "Break"
      : timer.paused
        ? "Paused"
        : timer.away
          ? "Away"
          : "Working";

  return (
    <div className="tray-flyout">
      <div className="tf-head">
        <Ring
          size={64}
          progress={timer.progress}
          color="#60cdff"
          label={formatTime(timer.remaining)}
          fontSize={17}
        />
        <div>
          <b>{status}</b>
          <span>
            {timer.breaksToday} of {timer.goal} breaks today · {timer.streak}-day
            streak
          </span>
        </div>
      </div>
      <div className="tf-btns">
        <Button appearance="primary" onClick={timer.togglePaused}>
          {timer.paused ? "Resume" : "Pause"}
        </Button>
        <Button onClick={timer.breakNow}>Break now</Button>
      </div>
      <div className="tf-foot">
        <button
          onClick={() => {
            if (isTauri) invoke("open_settings").catch(() => {});
          }}
        >
          Open settings
        </button>
        <button
          onClick={() => {
            if (isTauri) invoke("quit_app").catch(() => {});
          }}
        >
          Quit
        </button>
      </div>
    </div>
  );
}
