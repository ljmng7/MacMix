import { useEffect, useRef, type HTMLAttributes } from "react";
import { Safari } from "./Safari";
import { publicUrl } from "../lib/sitePaths";

const VIDEO_SRC = publicUrl(
  "/assets/MacMix/Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)_1080p.mp4",
);
const YOUTUBE_URL = "youtube.com";

type SafariVideoWindowProps = HTMLAttributes<HTMLDivElement> & {
  volume?: number;
};

export function SafariVideoWindow({
  className = "",
  volume = 1,
  ...props
}: SafariVideoWindowProps) {
  const videoRef = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    if (videoRef.current) {
      videoRef.current.volume = Math.min(Math.max(volume, 0), 1);
    }
  }, [volume]);

  return (
    <div
      className={`safari-video-window ${className}`.trim()}
      aria-label={`Safari browser showing https://${YOUTUBE_URL}`}
      {...props}
    >
      <div className="safari-video-window__screen">
        <video
          ref={videoRef}
          className="safari-video-window__video"
          src={VIDEO_SRC}
          controls
          playsInline
          preload="metadata"
        />
      </div>

      <Safari
        className="magicui-safari-frame"
        url={YOUTUBE_URL}
        media
        mode="simple"
      />
    </div>
  );
}
