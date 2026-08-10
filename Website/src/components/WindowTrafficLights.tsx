type WindowTrafficLightsProps = {
  className?: string;
};

export function WindowTrafficLights({
  className = "",
}: WindowTrafficLightsProps) {
  return (
    <svg
      className={`window-traffic-lights ${className}`.trim()}
      viewBox="0 0 1200 952"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      aria-hidden="true"
      focusable="false"
    >
      <circle cx="27" cy="25" r="6" fill="#FF5F57" />
      <circle cx="47" cy="25" r="6" fill="#FEBC2E" />
      <circle cx="67" cy="25" r="6" fill="#28C840" />
    </svg>
  );
}
