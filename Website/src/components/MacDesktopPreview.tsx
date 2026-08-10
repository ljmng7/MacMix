import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import { useReducedMotion } from "motion/react";
import { FaApple } from "react-icons/fa6";
import { Dock, DockIcon } from "./Dock";
import { MacMixPanel } from "./MacMixPanel";
import { MusicPlayerWindow } from "./MusicPlayerWindow";
import { SafariVideoWindow } from "./SafariVideoWindow";
import { SmoothCorner } from "./SmoothCorner";
import { ThemeImage } from "./ThemeImage";
import { publicUrl } from "../lib/sitePaths";

const clamp = (value: number, min: number, max: number) =>
  Math.min(Math.max(value, min), max);

const getDesktopTimeParts = (date: Date) => {
  const parts = new Intl.DateTimeFormat("en-US", {
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(date);
  const readPart = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((part) => part.type === type)?.value ?? "";

  return {
    weekday: readPart("weekday"),
    time: `${readPart("hour")}:${readPart("minute")}`,
  };
};

export function MacDesktopPreview() {
  const previewRef = useRef<HTMLDivElement>(null);
  const prefersReducedMotion = useReducedMotion();
  const [activeApp, setActiveApp] = useState<"music" | "safari">("music");
  const [desktopTime, setDesktopTime] = useState(() => new Date());
  const [systemVolume, setSystemVolume] = useState(72);
  const [musicVolume, setMusicVolume] = useState(160);
  const [safariVolume, setSafariVolume] = useState(70);
  const desktopTimeParts = getDesktopTimeParts(desktopTime);

  const menuVolumeIcon =
    systemVolume === 0
      ? "speaker.slash.fill.svg"
      : systemVolume < 34
        ? "speaker.wave.1.fill.svg"
        : systemVolume < 67
          ? "speaker.wave.2.fill.svg"
          : "speaker.wave.3.fill.svg";
  const menuVolumeIconVariant =
    systemVolume === 0
      ? "slash"
      : systemVolume < 34
        ? "wave-1"
        : systemVolume < 67
          ? "wave-2"
          : "wave-3";

  const handleAppKeyDown = (
    event: KeyboardEvent<HTMLDivElement>,
    app: "music" | "safari",
  ) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      setActiveApp(app);
    }
  };

  useEffect(() => {
    let frameId: number | null = null;

    const updateWallpaperPosition = () => {
      frameId = null;
      const preview = previewRef.current;

      if (!preview) {
        return;
      }

      const previewRect = preview.getBoundingClientRect();
      preview.style.setProperty(
        "--preview-layout-scale",
        clamp(previewRect.width / 1110, 0.5, 1).toFixed(4),
      );
      const headerBottom =
        document.querySelector<HTMLElement>(".site-header")?.getBoundingClientRect()
          .bottom ?? 0;
      const previewCenterOnPage =
        previewRect.top + window.scrollY + previewRect.height / 2;
      const viewportCenterBelowHeader =
        headerBottom + (window.innerHeight - headerBottom) / 2;
      const centerScrollY = Math.max(
        previewCenterOnPage - viewportCenterBelowHeader,
        1,
      );
      const bottomScrollY = Math.max(
        previewCenterOnPage - headerBottom,
        centerScrollY + 1,
      );

      let progress: number;

      if (prefersReducedMotion) {
        progress = 0.5;
      } else if (window.scrollY <= centerScrollY) {
        progress = 0.5 * clamp(window.scrollY / centerScrollY, 0, 1);
      } else {
        progress =
          0.5 +
          0.5 *
            clamp(
              (window.scrollY - centerScrollY) /
                (bottomScrollY - centerScrollY),
              0,
              1,
            );
      }

      preview.style.setProperty(
        "--preview-object-y",
        `${(progress * 100).toFixed(3)}%`,
      );
      preview.style.setProperty(
        "--preview-scroll-progress",
        progress.toFixed(4),
      );
      preview.dataset.scrollProgress = progress.toFixed(4);
    };

    const requestUpdate = () => {
      if (frameId === null) {
        frameId = window.requestAnimationFrame(updateWallpaperPosition);
      }
    };

    updateWallpaperPosition();
    window.addEventListener("scroll", requestUpdate, { passive: true });
    window.addEventListener("resize", requestUpdate, { passive: true });

    return () => {
      window.removeEventListener("scroll", requestUpdate);
      window.removeEventListener("resize", requestUpdate);
      if (frameId !== null) {
        window.cancelAnimationFrame(frameId);
      }
    };
  }, [prefersReducedMotion]);

  useEffect(() => {
    let minuteIntervalId: number | undefined;
    const updateTime = () => setDesktopTime(new Date());
    const minuteTimeoutId = window.setTimeout(() => {
      updateTime();
      minuteIntervalId = window.setInterval(updateTime, 60_000);
    }, 60_000 - (Date.now() % 60_000));

    return () => {
      window.clearTimeout(minuteTimeoutId);
      if (minuteIntervalId !== undefined) {
        window.clearInterval(minuteIntervalId);
      }
    };
  }, []);

  return (
    <SmoothCorner
      ref={previewRef}
      className="preview-card"
      radius={58}
      id="demo"
      data-scroll-progress="0.0000"
    >
      <ThemeImage
        className="preview-card__wallpaper"
        lightSrc="/assets/MacMix/GoldenGate-1600.webp"
        darkSrc="/assets/MacMix/Golden-Dark-1600.webp"
        lightSrcSet="/assets/MacMix/GoldenGate-1600.webp 1600w, /assets/MacMix/GoldenGate-2560.webp 2560w"
        darkSrcSet="/assets/MacMix/Golden-Dark-1600.webp 1600w, /assets/MacMix/Golden-Dark-2560.webp 2560w"
        sizes="(min-width: 1170px) 1110px, calc(100vw - 10vw)"
        width="1600"
        height="1000"
        alt="macOS Golden Gate wallpaper inside the interactive MacMix desktop preview"
        decoding="async"
        draggable="false"
      />
      <div className="mac-desktop-menu-bar" aria-label="macOS menu bar">
        <FaApple className="mac-desktop-menu-bar__apple" aria-hidden="true" />
        <div className="mac-desktop-menu-bar__status">
          <span
            className="mac-desktop-menu-bar__volume"
            aria-label="MacMix volume"
          >
            <img
              className={`speaker-glyph speaker-glyph--${menuVolumeIconVariant}`}
              src={publicUrl(`/assets/MacMix/svgs/${menuVolumeIcon}`)}
              alt=""
              aria-hidden="true"
            />
          </span>
          <img
            className="mac-desktop-menu-bar__wifi"
            src={publicUrl("/assets/MacMix/svgs/wifi.rounded.svg")}
            alt="Wi-Fi"
          />
          <img
            className="mac-desktop-menu-bar__control-center"
            src={publicUrl("/assets/MacMix/svgs/switch.2.svg")}
            alt="Control Center"
          />
          <time dateTime={desktopTime.toISOString()}>
            <span className="mac-desktop-menu-bar__weekday">
              {desktopTimeParts.weekday}
            </span>{" "}
            <span>{desktopTimeParts.time}</span>
          </time>
        </div>
      </div>
      <SafariVideoWindow
        className={`mac-preview-app mac-preview-safari ${
          activeApp === "safari" ? "mac-preview-app--active" : ""
        }`}
        aria-hidden={activeApp !== "safari"}
        volume={(systemVolume / 100) * (safariVolume / 100)}
      />
      <MusicPlayerWindow
        className={`mac-preview-app mac-preview-music ${
          activeApp === "music" ? "mac-preview-app--active" : ""
        }`}
        aria-hidden={activeApp !== "music"}
        volume={(systemVolume / 100) * (musicVolume / 100)}
      />
      <MacMixPanel
        systemVolume={systemVolume}
        musicVolume={musicVolume}
        safariVolume={safariVolume}
        onSystemVolumeChange={setSystemVolume}
        onMusicVolumeChange={setMusicVolume}
        onSafariVolumeChange={setSafariVolume}
      />
      <SmoothCorner
        className="mac-preview-dock"
        radius={27}
        outlineColor="rgba(255, 255, 255, 0.16)"
        outlineWidth={1}
      >
        <Dock direction="middle" aria-label="MacMix app dock">
          <DockIcon>
            <ThemeImage
              className="mac-preview-dock__app-icon"
              lightSrc="/assets/MacMix/MacMix-macOS-Default-web-256.png"
              darkSrc="/assets/MacMix/MacMix-macOS-Dark-web-256.png"
              width="256"
              height="256"
              alt="MacMix"
              draggable="false"
            />
          </DockIcon>
          <DockIcon
            className="mac-preview-dock__switcher"
            role="button"
            tabIndex={0}
            aria-label="Show Music"
            aria-pressed={activeApp === "music"}
            onClick={() => setActiveApp("music")}
            onKeyDown={(event) => handleAppKeyDown(event, "music")}
          >
            <ThemeImage
              className="mac-preview-dock__app-icon"
              lightSrc="/assets/MacMix/Music-iOS-Default-256@1x.png"
              darkSrc="/assets/MacMix/Music-iOS-Dark-256@1x.png"
              width="256"
              height="256"
              alt="Music"
              draggable="false"
            />
          </DockIcon>
          <DockIcon
            className="mac-preview-dock__switcher"
            role="button"
            tabIndex={0}
            aria-label="Show Safari"
            aria-pressed={activeApp === "safari"}
            onClick={() => setActiveApp("safari")}
            onKeyDown={(event) => handleAppKeyDown(event, "safari")}
          >
            <ThemeImage
              className="mac-preview-dock__app-icon"
              lightSrc="/assets/MacMix/Safari-iOS-Default-256@1x.png"
              darkSrc="/assets/MacMix/Safari-iOS-Dark-256@1x.png"
              width="256"
              height="256"
              alt="Safari"
              draggable="false"
            />
          </DockIcon>
        </Dock>
      </SmoothCorner>
    </SmoothCorner>
  );
}
