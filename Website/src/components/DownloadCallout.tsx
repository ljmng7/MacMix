export function DownloadCallout() {
  return (
    <svg
      className="download-callout"
      viewBox="0 0 210 70"
      aria-hidden="true"
      focusable="false"
    >
      <path
        className="download-callout__stroke download-callout__stroke--echo"
        d="M205 55 C174 56 160 33 128 34 C110 34 96 39 82 45"
      />
      <path
        className="download-callout__stroke"
        d="M205 53 C174 54 160 31 127 32 C109 32 94 37 81 44"
      />
      <path
        className="download-callout__arrowhead"
        d="M96 33 C91 37 86 41 81 44 C86 47 91 49 97 50"
      />
      <text
        className="download-callout__label"
        x="-8"
        y="49"
      >
        Free!
      </text>
    </svg>
  );
}
