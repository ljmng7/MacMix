import {
  animate,
  motion,
  useInView,
  useMotionValue,
  useReducedMotion,
  useTransform,
  type HTMLMotionProps,
} from "motion/react";
import { useEffect, useRef, useState } from "react";

const DEFAULT_COLORS = [
  "#c679c4",
  "#fa3d1d",
  "#ffb005",
  "#e1e1fe",
  "#0358f7",
];
const BAND_HALF = 17;
const SWEEP_START = -BAND_HALF;
const SWEEP_END = 100 + BAND_HALF;

const sweepEase = (t: number) =>
  t < 0.5 ? 4 * t ** 3 : 1 - (-2 * t + 2) ** 3 / 2;

function buildGradient(pos: number, colors: string[], textColor: string) {
  const bandStart = pos - BAND_HALF;
  const bandEnd = pos + BAND_HALF;

  if (bandStart >= 100) {
    return `linear-gradient(90deg, ${textColor}, ${textColor})`;
  }

  const parts: string[] = [];
  if (bandStart > 0) {
    parts.push(`${textColor} 0%`, `${textColor} ${bandStart.toFixed(2)}%`);
  }

  colors.forEach((color, index) => {
    const percentage =
      colors.length === 1
        ? pos
        : bandStart + (index / (colors.length - 1)) * BAND_HALF * 2;
    parts.push(`${color} ${percentage.toFixed(2)}%`);
  });

  if (bandEnd < 100) {
    parts.push(
      `transparent ${bandEnd.toFixed(2)}%`,
      "transparent 100%",
    );
  }

  return `linear-gradient(90deg, ${parts.join(", ")})`;
}

function measureWidths(element: HTMLElement, texts: string[]) {
  const ghost = element.cloneNode() as HTMLElement;
  Object.assign(ghost.style, {
    position: "absolute",
    visibility: "hidden",
    pointerEvents: "none",
    width: "auto",
    whiteSpace: "nowrap",
  });
  element.parentElement?.appendChild(ghost);
  const widths = texts.map((text) => {
    ghost.textContent = text;
    return ghost.getBoundingClientRect().width;
  });
  ghost.remove();
  return widths;
}

export interface DiaTextRevealProps extends Omit<
  HTMLMotionProps<"span">,
  "ref" | "children" | "style" | "animate" | "transition" | "color"
> {
  text: string | string[];
  colors?: string[];
  textColor?: string;
  duration?: number;
  delay?: number;
  repeat?: boolean;
  repeatDelay?: number;
  startOnView?: boolean;
  once?: boolean;
  className?: string;
  fixedWidth?: boolean;
}

export function DiaTextReveal({
  text,
  colors = DEFAULT_COLORS,
  textColor = "var(--foreground)",
  duration = 1.5,
  delay = 0,
  repeat = false,
  repeatDelay = 0.5,
  startOnView = true,
  once = true,
  className,
  fixedWidth = false,
  ...props
}: DiaTextRevealProps) {
  const texts = Array.isArray(text) ? text : [text];
  const isMulti = texts.length > 1;
  const prefersReducedMotion = useReducedMotion();
  const spanRef = useRef<HTMLSpanElement>(null);
  const optionsRef = useRef({
    colors,
    textColor,
    duration,
    delay,
    repeat,
    repeatDelay,
    texts,
  });
  optionsRef.current = {
    colors,
    textColor,
    duration,
    delay,
    repeat,
    repeatDelay,
    texts,
  };

  const indexRef = useRef(0);
  const hasPlayedRef = useRef(false);
  const timerRef = useRef<ReturnType<typeof setTimeout>>(undefined);
  const playRef = useRef<() => void>(() => undefined);
  const stopRef = useRef<(() => void) | null>(null);
  const [activeIndex, setActiveIndex] = useState(0);
  const [measuredWidths, setMeasuredWidths] = useState<number[]>([]);
  const sweepPosition = useMotionValue(SWEEP_START);
  const backgroundImage = useTransform(sweepPosition, (position) =>
    buildGradient(
      position,
      optionsRef.current.colors,
      optionsRef.current.textColor,
    ),
  );
  const isInView = useInView(spanRef, { once, amount: 0.1 });

  useEffect(() => {
    const element = spanRef.current;
    if (!element || !isMulti) return;
    setMeasuredWidths(measureWidths(element, texts));
  }, [isMulti, texts]);

  playRef.current = () => {
    const currentOptions = optionsRef.current;
    sweepPosition.set(SWEEP_START);
    const controls = animate(sweepPosition, SWEEP_END, {
      duration: currentOptions.duration,
      delay: currentOptions.delay,
      ease: sweepEase,
      onComplete() {
        if (!currentOptions.repeat) return;
        timerRef.current = setTimeout(() => {
          const nextIndex =
            (indexRef.current + 1) % currentOptions.texts.length;
          indexRef.current = nextIndex;
          setActiveIndex(nextIndex);
          playRef.current();
        }, currentOptions.repeatDelay * 1000);
      },
    });
    stopRef.current = () => controls.stop();
  };

  useEffect(() => {
    if (prefersReducedMotion) {
      sweepPosition.set(SWEEP_END);
      return;
    }
    if (startOnView && !isInView) return;
    if (once && hasPlayedRef.current) return;

    hasPlayedRef.current = true;
    playRef.current();

    return () => {
      stopRef.current?.();
      clearTimeout(timerRef.current);
    };
  }, [isInView, once, prefersReducedMotion, startOnView, sweepPosition]);

  const fixedW =
    isMulti && fixedWidth && measuredWidths.length > 0
      ? Math.max(...measuredWidths)
      : undefined;
  const animatedWidth =
    isMulti && !fixedWidth && measuredWidths[activeIndex] != null
      ? measuredWidths[activeIndex]
      : undefined;

  return (
    <motion.span
      ref={spanRef}
      className={["dia-text-reveal", className].filter(Boolean).join(" ")}
      style={{
        color: "transparent",
        backgroundClip: "text",
        WebkitBackgroundClip: "text",
        backgroundSize: "100% 100%",
        backgroundImage,
        ...(isMulti && {
          display: "inline-block",
          overflow: "hidden",
          whiteSpace: "nowrap",
          ...(fixedW != null && { width: fixedW }),
        }),
      }}
      animate={animatedWidth != null ? { width: animatedWidth } : undefined}
      transition={{ duration: 0.4, ease: [0.4, 0, 0.2, 1] }}
      {...props}
    >
      {texts[activeIndex]}
    </motion.span>
  );
}
