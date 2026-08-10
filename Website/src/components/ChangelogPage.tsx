import type { CSSProperties } from "react";
import { IoArrowForward, IoRefresh } from "react-icons/io5";
import ReactMarkdown, { type Components } from "react-markdown";
import remarkGfm from "remark-gfm";
import type { GitHubRelease } from "../lib/githubReleases";
import { BlurFade } from "./BlurFade";
import { HyperText } from "./HyperText";

type ChangelogPageProps = {
  releases: GitHubRelease[];
  isLoading: boolean;
  error: string | null;
  onRetry: () => void;
};

type ReleaseEntryStyle = CSSProperties & {
  "--release-index": number;
};

const markdownComponents: Components = {
  a: ({ href, children }) => (
    <a href={href} target="_blank" rel="noopener noreferrer">
      {children}
    </a>
  ),
};

function formatReleaseDate(value: string) {
  return new Intl.DateTimeFormat("en", {
    year: "numeric",
    month: "long",
    day: "numeric",
  }).format(new Date(value));
}

function normalizeReleaseBody(body: string | null) {
  if (!body) {
    return "Release details are available on GitHub.";
  }

  const lines = body.replace(/\r\n/g, "\n").trim().split("\n");
  if (/^#{0,3}\s*MacMix\b.*\brelease\s*$/i.test(lines[0]?.trim() ?? "")) {
    lines.shift();
  }

  return lines.join("\n").trim() || "Release details are available on GitHub.";
}

function LoadingTimeline() {
  return (
    <div className="release-skeletons" role="status" aria-label="Loading releases">
      {[0, 1, 2].map((item) => (
        <div className="release-skeleton" key={item} aria-hidden="true">
          <div className="release-skeleton__date" />
          <div className="release-skeleton__body">
            <div className="release-skeleton__title" />
            <div className="release-skeleton__line" />
            <div className="release-skeleton__line release-skeleton__line--short" />
          </div>
        </div>
      ))}
    </div>
  );
}

export function ChangelogPage({
  releases,
  isLoading,
  error,
  onRetry,
}: ChangelogPageProps) {
  return (
    <section className="changelog-page" aria-labelledby="changelog-title">
      <BlurFade className="changelog-intro" delay={0.05} offset={10} blur={false}>
        <HyperText as="h1" id="changelog-title">
          Changelog
        </HyperText>
      </BlurFade>

      {isLoading && releases.length === 0 ? <LoadingTimeline /> : null}

      {error && releases.length === 0 ? (
        <div className="changelog-error" role="alert">
          <span>GitHub is taking a little too long to answer.</span>
          <button type="button" onClick={onRetry}>
            <IoRefresh aria-hidden="true" />
            Try again
          </button>
        </div>
      ) : null}

      {releases.length > 0 ? (
        <div className="release-timeline" aria-label="MacMix releases">
          {releases.map((release, index) => {
            const releaseDate = release.published_at ?? release.created_at;
            const title = release.name?.trim() || `MacMix ${release.tag_name}`;
            const style: ReleaseEntryStyle = { "--release-index": index };

            return (
              <article className="release-entry" key={release.id} style={style}>
                <aside className="release-entry__meta">
                  <time dateTime={releaseDate}>{formatReleaseDate(releaseDate)}</time>
                  <a
                    className="release-entry__version"
                    href={release.html_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    aria-label={`View ${release.tag_name} on GitHub`}
                  >
                    {release.tag_name}
                  </a>
                </aside>

                <div className="release-entry__content">
                  <span className="release-entry__rail" aria-hidden="true">
                    <span className="release-entry__dot" />
                  </span>

                  <header className="release-entry__header">
                    <div className="release-entry__title-row">
                      <h2>{title}</h2>
                      {index === 0 ? (
                        <span className="release-entry__latest">Latest</span>
                      ) : null}
                      {release.prerelease ? (
                        <span className="release-entry__prerelease">Pre-release</span>
                      ) : null}
                    </div>
                  </header>

                  <div className="release-entry__markdown">
                    <ReactMarkdown
                      remarkPlugins={[remarkGfm]}
                      components={markdownComponents}
                    >
                      {normalizeReleaseBody(release.body)}
                    </ReactMarkdown>
                  </div>

                  <a
                    className="release-entry__github-link"
                    href={release.html_url}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    View release on GitHub
                    <IoArrowForward aria-hidden="true" />
                  </a>
                </div>
              </article>
            );
          })}
        </div>
      ) : null}

      {error && releases.length > 0 ? (
        <p className="changelog-stale-note">
          Showing the most recently cached releases while GitHub reconnects.
        </p>
      ) : null}
    </section>
  );
}

export default ChangelogPage;
