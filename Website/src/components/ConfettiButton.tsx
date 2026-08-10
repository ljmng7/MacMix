import confetti from "canvas-confetti";
import type { GlobalOptions, Options } from "canvas-confetti";
import { forwardRef, type ComponentPropsWithRef, type MouseEvent } from "react";

type ConfettiButtonProps = ComponentPropsWithRef<"a"> & {
  confettiDisabled?: boolean;
  effect?: "burst" | "fireworks";
  options?: Options & GlobalOptions;
};

export const ConfettiButton = forwardRef<HTMLAnchorElement, ConfettiButtonProps>(
  function ConfettiButton(
    {
      children,
      confettiDisabled = false,
      effect = "burst",
      onClick,
      options,
      ...props
    },
    ref,
  ) {
    const handleClick = (event: MouseEvent<HTMLAnchorElement>) => {
      onClick?.(event);

      if (event.defaultPrevented || confettiDisabled) {
        return;
      }

      if (effect === "fireworks") {
        const duration = 3 * 1000;
        const animationEnd = Date.now() + duration;
        const randomInRange = (min: number, max: number) =>
          Math.random() * (max - min) + min;

        const interval = window.setInterval(() => {
          const timeLeft = animationEnd - Date.now();

          if (timeLeft <= 0) {
            window.clearInterval(interval);
            return;
          }

          const particleCount = 50 * (timeLeft / duration);
          const defaults = {
            ...options,
            startVelocity: 30,
            spread: 360,
            ticks: 60,
            zIndex: 0,
          };

          void confetti({
            ...defaults,
            particleCount,
            origin: { x: randomInRange(0.1, 0.3), y: Math.random() - 0.2 },
          });
          void confetti({
            ...defaults,
            particleCount,
            origin: { x: randomInRange(0.7, 0.9), y: Math.random() - 0.2 },
          });
        }, 250);

        return;
      }

      const rect = event.currentTarget.getBoundingClientRect();
      const result = confetti({
        ...options,
        origin: {
          x: (rect.left + rect.width / 2) / window.innerWidth,
          y: (rect.top + rect.height / 2) / window.innerHeight,
        },
      });

      void Promise.resolve(result).catch((error: unknown) => {
        console.error("Confetti button error:", error);
      });
    };

    return (
      <a ref={ref} onClick={handleClick} {...props}>
        {children}
      </a>
    );
  },
);
