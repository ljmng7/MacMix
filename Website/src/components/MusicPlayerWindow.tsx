import {
  useEffect,
  useRef,
  useState,
  type CSSProperties,
  type ChangeEvent,
  type HTMLAttributes,
  type PointerEvent as ReactPointerEvent,
} from "react";
import {
  IoPause,
  IoPlay,
} from "react-icons/io5";
import { SmoothCorner } from "./SmoothCorner";
import { WindowTrafficLights } from "./WindowTrafficLights";
import { publicUrl } from "../lib/sitePaths";

type Track = {
  title: string;
  artist: string;
  songUrl: string;
  audioSrc: string;
  artworkSrc: string;
  duration: number;
  base: string;
  highlight: string;
  secondary: string;
  shadow: string;
  primaryText: string;
  secondaryText: string;
};

type MusicThemeStyle = CSSProperties & {
  "--music-base": string;
  "--music-highlight": string;
  "--music-secondary": string;
  "--music-shadow": string;
  "--music-primary": string;
  "--music-secondary-text": string;
  "--music-progress": string;
};

const TRACKS: Track[] = [
  {
    title: "Canon in D",
    artist: "dylanf - Canon in D (Piano Version) - Single",
    songUrl: "https://music.apple.com/song/canon-in-d-piano-version/1705330980",
    audioSrc: publicUrl(
      "/assets/MacMix/Canon in D (Piano Version) - dylanf/Canon in D (Piano Version) - dylanf.mp3",
    ),
    artworkSrc: publicUrl(
      "/assets/MacMix/Canon in D (Piano Version) - dylanf/Canon in D (Piano Version) - dylanf.webp",
    ),
    duration: 300.751917,
    base: "#d5cbcf",
    highlight: "rgb(175 166 170 / 78%)",
    secondary: "rgb(166 157 161 / 58%)",
    shadow: "rgb(124 118 120 / 52%)",
    primaryText: "#ffffff",
    secondaryText: "#ffffff",
  },
  {
    title: "城南花已开",
    artist: "三亩地 - 城南花已开 - Single",
    songUrl:
      "https://music.apple.com/song/%E5%9F%8E%E5%8D%97%E8%8A%B1%E5%B7%B2%E5%BC%80/1649087712",
    audioSrc: publicUrl(
      "/assets/MacMix/城南花已开 - 三亩地/城南花已开 - 三亩地.mp3",
    ),
    artworkSrc: publicUrl(
      "/assets/MacMix/城南花已开 - 三亩地/城南花已开 - 三亩地.webp",
    ),
    duration: 271.016961,
    base: "#20486e",
    highlight: "rgb(71 107 128 / 78%)",
    secondary: "rgb(77 119 139 / 58%)",
    shadow: "rgb(19 42 64 / 52%)",
    primaryText: "#ffffff",
    secondaryText: "#ffffff",
  },
  {
    title: "Merry Christmas Mr. Lawrence",
    artist: "坂本龍一 - THREE",
    songUrl:
      "https://music.apple.com/song/merry-christmas-mr-lawrence/1581114173",
    audioSrc: publicUrl(
      "/assets/MacMix/Merry Christmas Mr. Lawrence - 坂本龍一/Merry Christmas Mr. Lawrence - 坂本龍一.mp3",
    ),
    artworkSrc: publicUrl(
      "/assets/MacMix/Merry Christmas Mr. Lawrence - 坂本龍一/Merry Christmas Mr. Lawrence - 坂本龍一.webp",
    ),
    duration: 335.106667,
    base: "#0a0809",
    highlight: "rgb(61 59 60 / 78%)",
    secondary: "rgb(76 75 75 / 58%)",
    shadow: "rgb(6 5 5 / 52%)",
    primaryText: "#ffffff",
    secondaryText: "#ffffff",
  },
];

const formatTime = (seconds: number) => {
  if (!Number.isFinite(seconds) || seconds < 0) {
    return "0:00";
  }

  const minutes = Math.floor(seconds / 60);
  const remainingSeconds = Math.floor(seconds % 60);
  return `${minutes}:${remainingSeconds.toString().padStart(2, "0")}`;
};

type MusicPlayerWindowProps = HTMLAttributes<HTMLDivElement> & {
  volume?: number;
};

export function MusicPlayerWindow({
  className = "",
  volume = 0.74,
  ...props
}: MusicPlayerWindowProps) {
  const audioRef = useRef<HTMLAudioElement>(null);
  const resumeAfterTrackChangeRef = useRef(false);
  const skipAnimationTimerRef = useRef<number | null>(null);
  const [trackIndex, setTrackIndex] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);
  const [skipAnimation, setSkipAnimation] = useState<-1 | 1 | null>(null);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(TRACKS[0].duration);
  const track = TRACKS[trackIndex];
  const progress = duration > 0 ? (currentTime / duration) * 100 : 0;

  const themeStyle: MusicThemeStyle = {
    "--music-base": track.base,
    "--music-highlight": track.highlight,
    "--music-secondary": track.secondary,
    "--music-shadow": track.shadow,
    "--music-primary": track.primaryText,
    "--music-secondary-text": track.secondaryText,
    "--music-progress": `${progress}%`,
  };

  useEffect(() => {
    const audio = audioRef.current;

    if (!audio) {
      return;
    }

    audio.volume = Math.min(Math.max(volume, 0), 1);
  }, [volume]);

  useEffect(
    () => () => {
      if (skipAnimationTimerRef.current !== null) {
        window.clearTimeout(skipAnimationTimerRef.current);
      }
    },
    [],
  );

  useEffect(() => {
    const audio = audioRef.current;

    if (!audio) {
      return;
    }

    setCurrentTime(0);
    setDuration(track.duration);
    audio.load();

    if (resumeAfterTrackChangeRef.current) {
      void audio.play().catch(() => {
        resumeAfterTrackChangeRef.current = false;
        setIsPlaying(false);
      });
    }
  }, [track.audioSrc, track.duration]);

  const changeTrack = (direction: -1 | 1) => {
    const audio = audioRef.current;
    resumeAfterTrackChangeRef.current = audio ? !audio.paused : isPlaying;
    setTrackIndex(
      (currentIndex) =>
        (currentIndex + direction + TRACKS.length) % TRACKS.length,
    );
  };

  const animateTrackChange = (direction: -1 | 1) => {
    if (skipAnimation !== null) {
      return;
    }

    setSkipAnimation(direction);
    changeTrack(direction);
    skipAnimationTimerRef.current = window.setTimeout(() => {
      setSkipAnimation(null);
      skipAnimationTimerRef.current = null;
    }, 440);
  };

  const togglePlayback = () => {
    const audio = audioRef.current;

    if (!audio) {
      return;
    }

    if (audio.paused) {
      void audio.play();
    } else {
      audio.pause();
    }
  };

  const handleSeek = (event: ChangeEvent<HTMLInputElement>) => {
    const audio = audioRef.current;
    const nextTime = Number(event.target.value);

    if (!audio) {
      return;
    }

    audio.currentTime = nextTime;
    setCurrentTime(nextTime);
  };

  const handleSeekPointerDown = (
    event: ReactPointerEvent<HTMLInputElement>,
  ) => {
    const audio = audioRef.current;

    if (!audio) {
      return;
    }

    const bounds = event.currentTarget.getBoundingClientRect();
    const ratio = Math.min(
      Math.max((event.clientX - bounds.left) / bounds.width, 0),
      1,
    );
    const nextTime = ratio * (duration || track.duration);
    audio.currentTime = nextTime;
    setCurrentTime(nextTime);
  };

  const handleTrackEnded = () => {
    resumeAfterTrackChangeRef.current = true;
    setTrackIndex((currentIndex) => (currentIndex + 1) % TRACKS.length);
  };

  return (
    <SmoothCorner
      className={`music-player-window ${className}`.trim()}
      radius={18}
      outlineColor="rgba(255, 255, 255, 0.14)"
      outlineWidth={1}
      style={themeStyle}
      aria-label="Music player"
      {...props}
    >
      <div className="music-player-window__backdrop" aria-hidden="true">
        <div className="music-player-window__base" />
        <img
          key={track.artworkSrc}
          className="music-player-window__blurred-artwork"
          src={track.artworkSrc}
          alt=""
          draggable="false"
        />
        <div className="music-player-window__gradients" />
        <div className="music-player-window__dark-overlay" />
      </div>

      <WindowTrafficLights />

      <div className="music-player-window__content">
        <a
          key={`${track.artworkSrc}-cover-link`}
          className={`music-player-window__cover-link ${
            isPlaying
              ? "music-player-window__cover--playing"
              : "music-player-window__cover--paused"
          }`}
          href={track.songUrl}
          aria-label={`Open ${track.title} in Apple Music`}
        >
          <img
            className="music-player-window__cover"
            src={track.artworkSrc}
            width="632"
            height="632"
            alt={`${track.title} artwork`}
            draggable="false"
          />
        </a>

        <div className="music-player-window__metadata" aria-live="polite">
          <strong title={track.title}>{track.title}</strong>
          <span>{track.artist}</span>
        </div>

        <div className="music-player-window__timeline">
          <input
            className="music-player-window__range music-player-window__range--progress"
            type="range"
            min="0"
            max={duration || track.duration}
            step="0.01"
            value={Math.min(currentTime, duration || track.duration)}
            onChange={handleSeek}
            onPointerDown={handleSeekPointerDown}
            aria-label="Song progress"
          />
          <div className="music-player-window__times" aria-hidden="true">
            <span>{formatTime(currentTime)}</span>
            <span>-{formatTime(Math.max(duration - currentTime, 0))}</span>
          </div>
        </div>

        <div className="music-player-window__transport">
          <button
            type="button"
            onClick={() => animateTrackChange(-1)}
            aria-label="Previous song"
          >
            <span
              className={`music-player-window__skip-glyph music-player-window__skip-glyph--back ${
                skipAnimation === -1
                  ? "music-player-window__skip-glyph--animating"
                  : ""
              }`.trim()}
              aria-hidden="true"
            >
              <IoPlay className="music-player-window__skip-incoming" />
              <IoPlay className="music-player-window__skip-inner" />
              <IoPlay className="music-player-window__skip-outer" />
            </span>
          </button>
          <button
            className={`music-player-window__play ${
              isPlaying ? "music-player-window__play--pause" : ""
            }`.trim()}
            type="button"
            onClick={togglePlayback}
            aria-label={isPlaying ? "Pause" : "Play"}
          >
            <span className="music-player-window__play-glyph" aria-hidden="true">
              <IoPlay className="music-player-window__play-icon" />
              <IoPause className="music-player-window__pause-icon" />
            </span>
          </button>
          <button
            type="button"
            onClick={() => animateTrackChange(1)}
            aria-label="Next song"
          >
            <span
              className={`music-player-window__skip-glyph ${
                skipAnimation === 1
                  ? "music-player-window__skip-glyph--animating"
                  : ""
              }`.trim()}
              aria-hidden="true"
            >
              <IoPlay className="music-player-window__skip-incoming" />
              <IoPlay className="music-player-window__skip-inner" />
              <IoPlay className="music-player-window__skip-outer" />
            </span>
          </button>
        </div>

      </div>

      <audio
        ref={audioRef}
        src={track.audioSrc}
        preload="auto"
        onLoadedMetadata={(event) =>
          setDuration(event.currentTarget.duration || track.duration)
        }
        onTimeUpdate={(event) => setCurrentTime(event.currentTarget.currentTime)}
        onPlay={() => {
          resumeAfterTrackChangeRef.current = true;
          setIsPlaying(true);
        }}
        onPause={() => setIsPlaying(false)}
        onEnded={handleTrackEnded}
      />
    </SmoothCorner>
  );
}
