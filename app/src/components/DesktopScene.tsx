import type { DemoTimer } from "../demo/useDemoTimer";
import { Pill } from "./Pill";

export function DesktopScene({
  platform,
  timer,
}: {
  platform: "windows" | "mac";
  timer: DemoTimer;
}) {
  return (
    <div className={`desktop-scene ${platform}`}>
      {platform === "mac" && (
        <div className="mac-menubar">
          <svg viewBox="0 0 24 24" width="12" height="12" fill="currentColor">
            <path d="M16.7 12.9c0-2.1 1.7-3.1 1.8-3.2-1-1.4-2.5-1.6-3-1.6-1.3-.1-2.5.8-3.1.8-.6 0-1.6-.8-2.7-.8-1.4 0-2.7.8-3.4 2-1.5 2.5-.4 6.2 1 8.2.7 1 1.5 2.1 2.6 2.1 1 0 1.4-.7 2.7-.7s1.6.7 2.7.7c1.1 0 1.9-1 2.6-2 .8-1.1 1.1-2.2 1.1-2.3-.1 0-2.3-.9-2.3-3.2z" />
            <path d="M14.6 6.6c.6-.7 1-1.7.9-2.7-.9 0-2 .6-2.6 1.3-.6.6-1.1 1.7-.9 2.7 1 .1 2-.5 2.6-1.3z" />
          </svg>
          <b>EyeRule</b>
          <span>File</span>
          <span>Edit</span>
          <span>View</span>
          <span>Help</span>
          <div className="mac-status">
            <span>◔</span>
            <span>Wi-Fi</span>
            <span>100%</span>
            <span>Tue 9:41</span>
          </div>
        </div>
      )}

      <Pill timer={timer} />

      {platform === "windows" && (
        <div className="win-taskbar">
          <div className="win-apps">
            <i />
            <i />
            <i />
            <i />
            <i />
          </div>
          <div className="win-tray">
            <span className="tray-eye">◉</span>
            <span>ENG</span>
            <span className="win-clock">
              21:43
              <br />
              17/11/2026
            </span>
          </div>
        </div>
      )}
    </div>
  );
}
