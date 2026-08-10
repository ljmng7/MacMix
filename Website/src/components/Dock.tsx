import React, { useRef, type PropsWithChildren } from "react";
import {
  motion,
  useMotionValue,
  useSpring,
  useTransform,
  type MotionProps,
  type MotionValue,
} from "motion/react";

export interface DockProps
  extends Omit<MotionProps & React.HTMLAttributes<HTMLDivElement>, "children"> {
  className?: string;
  iconSize?: number;
  iconMagnification?: number;
  disableMagnification?: boolean;
  iconDistance?: number;
  direction?: "top" | "middle" | "bottom";
  children: React.ReactNode;
}

const DEFAULT_SIZE = 50;
const DEFAULT_MAGNIFICATION = 75;
const DEFAULT_DISTANCE = 175;
const DEFAULT_DISABLE_MAGNIFICATION = false;

const Dock = React.forwardRef<HTMLDivElement, DockProps>(
  (
    {
      className = "",
      children,
      iconSize = DEFAULT_SIZE,
      iconMagnification = DEFAULT_MAGNIFICATION,
      disableMagnification = DEFAULT_DISABLE_MAGNIFICATION,
      iconDistance = DEFAULT_DISTANCE,
      direction = "middle",
      ...props
    },
    ref,
  ) => {
    const mouseX = useMotionValue(Number.POSITIVE_INFINITY);

    const renderChildren = () =>
      React.Children.map(children, (child) => {
        if (
          React.isValidElement<DockIconProps>(child) &&
          child.type === DockIcon
        ) {
          return React.cloneElement(child, {
            ...child.props,
            mouseX,
            size: iconSize,
            magnification: iconMagnification,
            disableMagnification,
            distance: iconDistance,
          });
        }

        return child;
      });

    const directionClass = `magic-dock--${direction}`;

    return (
      <motion.div
        ref={ref}
        onMouseMove={(event) => mouseX.set(event.pageX)}
        onMouseLeave={() => mouseX.set(Number.POSITIVE_INFINITY)}
        {...props}
        className={`magic-dock ${directionClass} ${className}`.trim()}
      >
        {renderChildren()}
      </motion.div>
    );
  },
);

Dock.displayName = "Dock";

export interface DockIconProps
  extends Omit<
    MotionProps & React.HTMLAttributes<HTMLDivElement>,
    "children"
  > {
  size?: number;
  magnification?: number;
  disableMagnification?: boolean;
  distance?: number;
  mouseX?: MotionValue<number>;
  className?: string;
  children?: React.ReactNode;
  props?: PropsWithChildren;
}

const DockIcon = ({
  size = DEFAULT_SIZE,
  magnification = DEFAULT_MAGNIFICATION,
  disableMagnification,
  distance = DEFAULT_DISTANCE,
  mouseX,
  className = "",
  children,
  ...props
}: DockIconProps) => {
  const ref = useRef<HTMLDivElement>(null);
  const padding = Math.max(6, size * 0.2);
  const defaultMouseX = useMotionValue(Number.POSITIVE_INFINITY);

  const distanceCalc = useTransform(
    mouseX ?? defaultMouseX,
    (value: number) => {
      const bounds = ref.current?.getBoundingClientRect() ?? {
        x: 0,
        width: 0,
      };

      return value - bounds.x - bounds.width / 2;
    },
  );

  const targetSize = disableMagnification ? size : magnification;
  const sizeTransform = useTransform(
    distanceCalc,
    [-distance, 0, distance],
    [size, targetSize, size],
  );
  const scaleSize = useSpring(sizeTransform, {
    mass: 0.1,
    stiffness: 150,
    damping: 12,
  });

  return (
    <motion.div
      ref={ref}
      style={{ width: scaleSize, height: scaleSize, padding }}
      className={`magic-dock__icon ${
        disableMagnification ? "magic-dock__icon--static" : ""
      } ${className}`.trim()}
      {...props}
    >
      <div>{children}</div>
    </motion.div>
  );
};

DockIcon.displayName = "DockIcon";

export { Dock, DockIcon };
