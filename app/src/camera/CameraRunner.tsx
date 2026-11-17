import { useEffect, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { FaceLandmarker, FilesetResolver } from "@mediapipe/tasks-vision";

const WASM = "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/wasm";
const MODEL =
  "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task";

export function CameraRunner() {
  const videoRef = useRef<HTMLVideoElement>(null);
  const runningRef = useRef(false);

  useEffect(() => {
    let landmarker: FaceLandmarker | null = null;
    let stream: MediaStream | null = null;
    let sampleTimer: number | null = null;
    let reportTimer: number | null = null;
    let closed = false;
    let blinks = 0;
    let faceFrames = 0;
    let totalFrames = 0;

    const stop = () => {
      runningRef.current = false;
      if (sampleTimer) window.clearInterval(sampleTimer);
      if (reportTimer) window.clearInterval(reportTimer);
      sampleTimer = null;
      reportTimer = null;
      stream?.getTracks().forEach((t) => t.stop());
      stream = null;
      landmarker?.close();
      landmarker = null;
    };

    const start = async () => {
      if (runningRef.current) return;
      runningRef.current = true;
      try {
        const fileset = await FilesetResolver.forVisionTasks(WASM);
        landmarker = await FaceLandmarker.createFromOptions(fileset, {
          baseOptions: { modelAssetPath: MODEL, delegate: "GPU" },
          runningMode: "VIDEO",
          numFaces: 1,
          outputFaceBlendshapes: true,
        });
        stream = await navigator.mediaDevices.getUserMedia({
          video: { width: 320, height: 240, frameRate: 10 },
          audio: false,
        });
        const video = videoRef.current;
        if (!video) return stop();
        video.srcObject = stream;
        await video.play();

        sampleTimer = window.setInterval(() => {
          if (!landmarker || !video || video.readyState < 2) return;
          const result = landmarker.detectForVideo(video, performance.now());
          totalFrames += 1;
          const shapes = result.faceBlendshapes?.[0]?.categories ?? [];
          const left = shapes.find((c) => c.categoryName === "eyeBlinkLeft")?.score ?? 0;
          const right = shapes.find((c) => c.categoryName === "eyeBlinkRight")?.score ?? 0;
          const avg = (left + right) / 2;
          if (result.faceLandmarks.length > 0) faceFrames += 1;
          if (!closed && avg > 0.5) closed = true;
          else if (closed && avg < 0.3) {
            closed = false;
            blinks += 1;
          }
        }, 100);

        reportTimer = window.setInterval(() => {
          const facePresent = totalFrames > 0 && faceFrames > totalFrames / 2;
          invoke("camera_sample", { blinks, facePresent }).catch(() => {});
          blinks = 0;
          faceFrames = 0;
          totalFrames = 0;
        }, 500);
      } catch {
        stop();
      }
    };

    const un = listen<boolean>("camera-run", (event) => {
      if (event.payload) start();
      else stop();
    });

    // The window may load after Rust already emitted "camera-run" (camera
    // enabled at startup), so ask once on mount as well.
    invoke<boolean>("camera_running")
      .then((on) => {
        if (on) start();
      })
      .catch(() => {});

    return () => {
      un.then((fn) => fn());
      stop();
    };
  }, []);

  return <video ref={videoRef} muted playsInline style={{ display: "none" }} />;
}
