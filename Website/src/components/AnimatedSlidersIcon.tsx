const TOP_THUMB =
  "M628 237L724 237C793 237 841.5 188 841.5 119C841.5 50 793 1.5 724 1.5L628 1.5C559 1.5 510.5 50 510.5 119C510.5 188 559 237 628 237Z";
const TOP_THUMB_INNER =
  "M628 176.5C594 176.5 571 153 571 119C571 85.5 594 62 628 62L724 62C757.5 62 781 85.5 781 119C781 153 757.5 176.5 724 176.5Z";

const MIDDLE_THUMB =
  "M497 424.5C497 493.5 448 542 379.5 542L283.5 542C214.5 542 165.5 493.5 165.5 424.5C165.5 355.5 214.5 306.5 283.5 306.5L379.5 306.5C448 306.5 497 355.5 497 424.5Z";
const MIDDLE_THUMB_INNER =
  "M283.5 367C249.5 367 226 390.5 226 424.5C226 458 249.5 481.5 283.5 481.5L379.5 481.5C413 481.5 436.5 458 436.5 424.5C436.5 390.5 413 367 379.5 367Z";

const BOTTOM_THUMB =
  "M841.5 730C841.5 798.5 793 847.5 724 847.5L628 847.5C559 847.5 510.5 798.5 510.5 730C510.5 661 559 612 628 612L724 612C793 612 841.5 661 841.5 730Z";
const BOTTOM_THUMB_INNER =
  "M628 672.5C594 672.5 571 696 571 730C571 763.5 594 787 628 787L724 787C757.5 787 781 763.5 781 730C781 696 757.5 672.5 724 672.5Z";

function SliderThumb({
  className,
  outerPath,
  innerPath,
}: {
  className: string;
  outerPath: string;
  innerPath: string;
}) {
  return (
    <g className={`animated-sliders-icon__thumb ${className}`}>
      <path d={outerPath} />
      <path className="animated-sliders-icon__thumb-inner" d={innerPath} />
    </g>
  );
}

export function AnimatedSlidersIcon() {
  return (
    <svg
      className="animated-sliders-icon"
      viewBox="0 0 1007.5 847.5"
      role="presentation"
      focusable="false"
    >
      <rect className="animated-sliders-icon__track" width="1007.5" height="80.5" x="0" y="79" rx="40.25" />
      <rect className="animated-sliders-icon__track" width="1007.5" height="80.5" x="0" y="384" rx="40.25" />
      <rect className="animated-sliders-icon__track" width="1007.5" height="80.5" x="0" y="689.5" rx="40.25" />
      <SliderThumb
        className="animated-sliders-icon__thumb--top"
        outerPath={TOP_THUMB}
        innerPath={TOP_THUMB_INNER}
      />
      <SliderThumb
        className="animated-sliders-icon__thumb--middle"
        outerPath={MIDDLE_THUMB}
        innerPath={MIDDLE_THUMB_INNER}
      />
      <SliderThumb
        className="animated-sliders-icon__thumb--bottom"
        outerPath={BOTTOM_THUMB}
        innerPath={BOTTOM_THUMB_INNER}
      />
    </svg>
  );
}
