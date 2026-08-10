import type { PropsWithChildren } from "react";
import { motion, useReducedMotion } from "motion/react";

type BlurFadeProps = PropsWithChildren<{
  className?: string;
  delay?: number;
  offset?: number;
  blur?: boolean;
}>;

export function BlurFade({
  children,
  className,
  delay = 0,
  offset = 14,
  blur = true,
}: BlurFadeProps) {
  const prefersReducedMotion = useReducedMotion();

  return (
    <motion.div
      className={className}
      initial={
        prefersReducedMotion
          ? false
          : {
              opacity: 0,
              y: offset,
              ...(blur ? { filter: "blur(10px)" } : {}),
            }
      }
      animate={{
        opacity: 1,
        y: 0,
        ...(blur ? { filter: "blur(0px)" } : {}),
      }}
      transition={{
        duration: prefersReducedMotion ? 0 : 0.72,
        delay: prefersReducedMotion ? 0 : delay,
        ease: [0.16, 1, 0.3, 1],
      }}
    >
      {children}
    </motion.div>
  );
}
