import type { ImgHTMLAttributes } from "react";
import { publicSrcSet, publicUrl } from "../lib/sitePaths";

type ThemeImageProps = Omit<
  ImgHTMLAttributes<HTMLImageElement>,
  "src" | "srcSet"
> & {
  lightSrc: string;
  darkSrc: string;
  lightSrcSet?: string;
  darkSrcSet?: string;
};

export function ThemeImage({
  lightSrc,
  darkSrc,
  lightSrcSet,
  darkSrcSet,
  sizes,
  ...props
}: ThemeImageProps) {
  return (
    <picture className="theme-picture">
      <source
        media="(prefers-color-scheme: dark)"
        srcSet={publicSrcSet(darkSrcSet) ?? publicUrl(darkSrc)}
        sizes={sizes}
      />
      <img
        {...props}
        src={publicUrl(lightSrc)}
        srcSet={publicSrcSet(lightSrcSet)}
        sizes={sizes}
      />
    </picture>
  );
}
