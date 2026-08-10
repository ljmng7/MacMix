// Every visible contour below is copied directly from switch.2.svg.
// The compound filled-switch path is separated into its original two subpaths
// only so the thumb can travel while preserving the asset's exact geometry.
const OUTLINED_TRACK =
  "M236 456L717.5 456C848 456 953.5 364 953.5 228C953.5 92 848 0 717.5 0L236 0C105.5 0 0 92 0 228C0 364 105.5 456 236 456ZM236 380.5C149 380.5 78.5 319 78.5 228C78.5 137 149 75.5 236 75.5L717.5 75.5C804.5 75.5 875 137 875 228C875 319 804.5 380.5 717.5 380.5Z";

const OUTLINED_THUMB =
  "M236 346.5L381.5 346.5C449.5 346.5 504 298.5 504 228C504 157 449.5 109 381.5 109L236 109C168 109 113.5 157 113.5 227.5C113.5 298.5 168 346.5 236 346.5Z";

const FILLED_TRACK =
  "M214 944L739.5 944C858 944 953.5 861 953.5 738.5C953.5 616 858 533 739.5 533L214 533C95.5 533 0 616 0 738.5C0 861 95.5 944 214 944Z";

const FILLED_THUMB =
  "M594.5 867.5C520.5 867.5 461 815.5 461 738C461 661 520.5 609 594.5 609L747.5 609C822 609 881 661 881 738.5C881 815.5 822 867.5 747.5 867.5Z";

export function AnimatedVolumeMixIcon() {
  return (
    <svg
      className="animated-volume-mix-icon"
      viewBox="0 0 953.5 945.5"
      aria-hidden="true"
      focusable="false"
    >
      <path d={OUTLINED_TRACK} />
      <path
        className="animated-volume-mix-icon__thumb animated-volume-mix-icon__thumb--top"
        d={OUTLINED_THUMB}
      />
      <path d={FILLED_TRACK} />
      <path
        className="animated-volume-mix-icon__thumb animated-volume-mix-icon__thumb--paper animated-volume-mix-icon__thumb--bottom"
        d={FILLED_THUMB}
      />
    </svg>
  );
}
