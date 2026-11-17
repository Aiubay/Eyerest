import { FluentProvider, webDarkTheme, webLightTheme } from "@fluentui/react-components";
import { useEffect, useState } from "react";
import { CameraRunner } from "./camera/CameraRunner";
import { Pill } from "./components/Pill";
import { TrayFlyout } from "./components/TrayFlyout";
import { type DemoStart, useDemoTimer } from "./demo/useDemoTimer";
import { SettingsWindow } from "./settings/SettingsWindow";
import { isTauri, useAppState } from "./state/useAppState";

type Scene = "pill" | "settings" | "tray";

function query(key: string): string | null {
  return new URLSearchParams(window.location.search).get(key);
}

function initialPreviewState(): DemoStart {
  switch (query("state")) {
    case "lastMinute":
      return { remaining: 45 };
    case "away":
      return { away: true };
    case "break":
      return { phase: "resting", remaining: 14 };
    case "done":
      return { phase: "done" };
    default:
      return {};
  }
}

function initialScene(): Scene {
  const scene = query("scene");
  return scene === "settings" || scene === "tray" ? scene : "pill";
}

function initialTheme(): "dark" | "light" {
  return query("theme") === "light" ? "light" : "dark";
}

export default function App() {
  const windowKind = query("window");
  const { timer, settings, update } = useAppState();
  const demoTimer = useDemoTimer(initialPreviewState());
  const [scene, setScene] = useState<Scene>(initialScene);
  const [backdrop, setBackdrop] = useState<"wallpaper" | "game">("wallpaper");
  const [theme, setTheme] = useState<"dark" | "light">(initialTheme);

  useEffect(() => {
    document.body.classList.toggle("native", windowKind !== null);
    return () => document.body.classList.remove("native");
  }, [windowKind]);

  // The dev preview is browser-only; a packaged window always carries ?window=.
  if (windowKind === null && isTauri) {
    return null;
  }

  if (windowKind === "camera") {
    return <CameraRunner />;
  }

  if (windowKind === "pill") {
    return (
      <div className="native-pill">
        <Pill timer={timer} />
      </div>
    );
  }

  if (windowKind === "settings") {
    return (
      <FluentProvider theme={webDarkTheme} className="fluent-root">
        <div className="native-settings theme-dark">
          <SettingsWindow timer={timer} settings={settings} update={update} />
        </div>
      </FluentProvider>
    );
  }

  if (windowKind === "tray") {
    return (
      <FluentProvider theme={webDarkTheme} className="fluent-root">
        <div className="native-tray theme-dark">
          <TrayFlyout timer={timer} />
        </div>
      </FluentProvider>
    );
  }

  const previewTimer = demoTimer;

  return (
    <FluentProvider
      theme={theme === "dark" ? webDarkTheme : webLightTheme}
      className="fluent-root"
    >
      <header className="devhead">
        <b>EyeRule Windows preview</b>
        <span>phase 5 · engine wired</span>
      </header>

      {scene === "pill" && (
        <div className="stage" data-backdrop={backdrop}>
          {backdrop === "game" && (
            <div className="game-layer" aria-hidden>
              <div className="crosshair" />
              <div className="hud-hp">
                <i />
              </div>
              <span className="hud-tag">game backdrop</span>
            </div>
          )}
          <Pill timer={previewTimer} />
        </div>
      )}

      {scene === "settings" && (
        <div className={`stage settings-stage theme-${theme}`}>
          <SettingsWindow
            timer={previewTimer}
            settings={settings}
            update={update}
          />
        </div>
      )}

      {scene === "tray" && (
        <div className={`stage tray-stage theme-${theme}`}>
          <div className="tray-taskbar">
            <div className="tb-apps">
              <i />
              <i />
              <i />
              <i />
              <i />
            </div>
            <div className="tb-tray">
              <span className="tb-eye">◉</span>
              <span className="tb-clock">21:43</span>
            </div>
          </div>
          <TrayFlyout timer={previewTimer} />
        </div>
      )}

      <div className="devbar">
        <span className="devlabel">Scene</span>
        <button className={scene === "pill" ? "on" : ""} onClick={() => setScene("pill")}>
          Pill
        </button>
        <button className={scene === "settings" ? "on" : ""} onClick={() => setScene("settings")}>
          Settings
        </button>
        <button className={scene === "tray" ? "on" : ""} onClick={() => setScene("tray")}>
          Tray
        </button>

        {scene === "pill" && (
          <>
            <span className="devlabel">State</span>
            <button onClick={previewTimer.jumpLastMinute}>Last minute</button>
            <button onClick={previewTimer.toggleAway} className={previewTimer.away ? "on" : ""}>
              Away
            </button>
            <button onClick={previewTimer.breakNow}>Break</button>
            <button onClick={previewTimer.finishNow} disabled={previewTimer.phase !== "resting"}>
              Done
            </button>
            <button onClick={previewTimer.togglePaused} className={previewTimer.paused ? "on" : ""}>
              {previewTimer.paused ? "Resume" : "Pause"}
            </button>
            <button onClick={previewTimer.reset}>Reset 20:00</button>
            <button
              onClick={() =>
                setBackdrop((value) => (value === "game" ? "wallpaper" : "game"))
              }
            >
              {backdrop === "game" ? "Wallpaper" : "Game backdrop"}
            </button>
          </>
        )}

        <span className="devlabel">Theme</span>
        <button className={theme === "dark" ? "on" : ""} onClick={() => setTheme("dark")}>
          Dark
        </button>
        <button className={theme === "light" ? "on" : ""} onClick={() => setTheme("light")}>
          Light
        </button>
      </div>
    </FluentProvider>
  );
}
