import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type ElementType,
} from "react";
import { useReducedMotion } from "motion/react";

const DEFAULT_CHARACTER_SET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".split("");

type HyperTextProps = {
  children: string;
  className?: string;
  duration?: number;
  delay?: number;
  as?: ElementType;
  animateOnHover?: boolean;
  characterSet?: string[];
  id?: string;
};

function randomCharacter(characterSet: string[], uppercase: boolean) {
  const character =
    characterSet[Math.floor(Math.random() * characterSet.length)] ?? "";
  return uppercase ? character.toUpperCase() : character.toLowerCase();
}

export function HyperText({
  children,
  className,
  duration = 800,
  delay = 0,
  as: Component = "div",
  animateOnHover = true,
  characterSet = DEFAULT_CHARACTER_SET,
  id,
}: HyperTextProps) {
  const prefersReducedMotion = useReducedMotion();
  const [displayText, setDisplayText] = useState(children);
  const animationFrameRef = useRef<number | null>(null);
  const delayTimerRef = useRef<number | null>(null);
  const isAnimatingRef = useRef(false);

  const stopAnimation = useCallback(() => {
    if (animationFrameRef.current !== null) {
      window.cancelAnimationFrame(animationFrameRef.current);
      animationFrameRef.current = null;
    }
    isAnimatingRef.current = false;
    setDisplayText(children);
  }, [children]);

  const startAnimation = useCallback(() => {
    if (prefersReducedMotion || isAnimatingRef.current) {
      return;
    }

    const startedAt = performance.now();
    const revealableCharacters = [...children].filter((character) => character !== " ").length;
    isAnimatingRef.current = true;

    const update = (now: number) => {
      const progress = Math.min((now - startedAt) / duration, 1);
      const revealedCount = Math.floor(progress * revealableCharacters);
      let seenCharacters = 0;

      setDisplayText(
        [...children]
          .map((character) => {
            if (character === " ") {
              return character;
            }

            const isFirstCharacter = seenCharacters === 0;
            const isRevealed = seenCharacters < revealedCount;
            seenCharacters += 1;
            return isRevealed
              ? character
              : randomCharacter(characterSet, isFirstCharacter);
          })
          .join(""),
      );

      if (progress < 1) {
        animationFrameRef.current = window.requestAnimationFrame(update);
      } else {
        stopAnimation();
      }
    };

    animationFrameRef.current = window.requestAnimationFrame(update);
  }, [characterSet, children, duration, prefersReducedMotion, stopAnimation]);

  useEffect(() => {
    setDisplayText(children);

    if (prefersReducedMotion) {
      return;
    }

    delayTimerRef.current = window.setTimeout(startAnimation, delay);

    return () => {
      if (delayTimerRef.current !== null) {
        window.clearTimeout(delayTimerRef.current);
        delayTimerRef.current = null;
      }
      if (animationFrameRef.current !== null) {
        window.cancelAnimationFrame(animationFrameRef.current);
        animationFrameRef.current = null;
      }
      isAnimatingRef.current = false;
    };
  }, [children, delay, prefersReducedMotion, startAnimation]);

  return (
    <Component
      id={id}
      className={className}
      aria-label={children}
      onPointerEnter={animateOnHover ? startAnimation : undefined}
    >
      {displayText}
    </Component>
  );
}
