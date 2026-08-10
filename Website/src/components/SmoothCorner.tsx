import {
  forwardRef,
  useId,
  useLayoutEffect,
  useRef,
  useState,
  type CSSProperties,
  type HTMLAttributes,
  type ReactNode,
} from "react";

type SmoothCornerProps = Omit<HTMLAttributes<HTMLDivElement>, "children"> & {
  children: ReactNode;
  radius: number;
  exponent?: number;
  outlineColor?: string;
  outlineWidth?: number;
};

type Size = {
  width: number;
  height: number;
};

const CORNER_STEPS = 24;

function buildContinuousCornerPath(
  width: number,
  height: number,
  requestedRadius: number,
  exponent: number,
) {
  const radius = Math.min(requestedRadius, width / 2, height / 2);
  const power = 2 / exponent;
  const commands: string[] = [];

  const point = (x: number, y: number) =>
    `${(x / width).toFixed(6)} ${(y / height).toFixed(6)}`;

  const addArc = (
    centerX: number,
    centerY: number,
    startAngle: number,
    endAngle: number,
  ) => {
    for (let index = 1; index <= CORNER_STEPS; index += 1) {
      const progress = index / CORNER_STEPS;
      const angle = startAngle + (endAngle - startAngle) * progress;
      const cosine = Math.cos(angle);
      const sine = Math.sin(angle);
      const x =
        centerX +
        radius * Math.sign(cosine) * Math.abs(cosine) ** power;
      const y =
        centerY + radius * Math.sign(sine) * Math.abs(sine) ** power;

      commands.push(`L ${point(x, y)}`);
    }
  };

  commands.push(`M ${point(radius, 0)}`);
  commands.push(`L ${point(width - radius, 0)}`);
  addArc(width - radius, radius, -Math.PI / 2, 0);
  commands.push(`L ${point(width, height - radius)}`);
  addArc(width - radius, height - radius, 0, Math.PI / 2);
  commands.push(`L ${point(radius, height)}`);
  addArc(radius, height - radius, Math.PI / 2, Math.PI);
  commands.push(`L ${point(0, radius)}`);
  addArc(radius, radius, Math.PI, (Math.PI * 3) / 2);
  commands.push("Z");

  return commands.join(" ");
}

export const SmoothCorner = forwardRef<HTMLDivElement, SmoothCornerProps>(
  (
    {
      children,
      radius,
      exponent = 3.2,
      outlineColor,
      outlineWidth = 1,
      className = "",
      style,
      ...props
    },
    forwardedRef,
  ) => {
    const localRef = useRef<HTMLDivElement>(null);
    const [size, setSize] = useState<Size>({ width: 0, height: 0 });
    const clipId = `smooth-corner-${useId().replaceAll(":", "")}`;

    useLayoutEffect(() => {
      const element = localRef.current;

      if (!element) {
        return;
      }

      let frameId: number | null = null;
      const updateSize = () => {
        frameId = null;
        const rect = element.getBoundingClientRect();
        const nextSize = { width: rect.width, height: rect.height };

        setSize((current) =>
          Math.abs(current.width - nextSize.width) < 0.1 &&
          Math.abs(current.height - nextSize.height) < 0.1
            ? current
            : nextSize,
        );
      };
      const requestUpdate = () => {
        if (frameId === null) {
          frameId = window.requestAnimationFrame(updateSize);
        }
      };
      const observer = new ResizeObserver(requestUpdate);

      observer.observe(element);
      updateSize();

      return () => {
        observer.disconnect();
        if (frameId !== null) {
          window.cancelAnimationFrame(frameId);
        }
      };
    }, []);

    const path =
      size.width > 0 && size.height > 0
        ? buildContinuousCornerPath(
            size.width,
            size.height,
            radius,
            exponent,
          )
        : "";
    const clipStyle: CSSProperties = path
      ? {
          clipPath: `url(#${clipId})`,
          WebkitClipPath: `url(#${clipId})`,
        }
      : {};

    const setRefs = (node: HTMLDivElement | null) => {
      localRef.current = node;
      if (typeof forwardedRef === "function") {
        forwardedRef(node);
      } else if (forwardedRef) {
        forwardedRef.current = node;
      }
    };

    return (
      <div
        ref={setRefs}
        className={`smooth-corner ${className}`.trim()}
        style={{ ...style, ...clipStyle }}
        {...props}
      >
        <svg
          className="smooth-corner__defs"
          width="0"
          height="0"
          aria-hidden="true"
          focusable="false"
        >
          <defs>
            <clipPath id={clipId} clipPathUnits="objectBoundingBox">
              <path d={path || "M 0 0 H 1 V 1 H 0 Z"} />
            </clipPath>
          </defs>
        </svg>
        {children}
        {outlineColor && path ? (
          <svg
            className="smooth-corner__outline"
            viewBox="0 0 1 1"
            preserveAspectRatio="none"
            aria-hidden="true"
            focusable="false"
          >
            <path
              d={path}
              fill="none"
              stroke={outlineColor}
              strokeWidth={outlineWidth}
              vectorEffect="non-scaling-stroke"
            />
          </svg>
        ) : null}
      </div>
    );
  },
);

SmoothCorner.displayName = "SmoothCorner";
