import releasesSnapshot from "../generated/github-releases.json";

export type GitHubRelease = {
  id: number;
  tag_name: string;
  name: string | null;
  body: string | null;
  html_url: string;
  published_at: string | null;
  created_at: string;
  prerelease: boolean;
  draft: boolean;
};

function isGitHubRelease(value: unknown): value is GitHubRelease {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const release = value as Record<string, unknown>;
  return (
    typeof release.id === "number" &&
    typeof release.tag_name === "string" &&
    (typeof release.name === "string" || release.name === null) &&
    (typeof release.body === "string" || release.body === null) &&
    typeof release.html_url === "string" &&
    (typeof release.published_at === "string" || release.published_at === null) &&
    typeof release.created_at === "string" &&
    typeof release.prerelease === "boolean" &&
    typeof release.draft === "boolean"
  );
}

function parseReleases(value: unknown): GitHubRelease[] {
  if (!Array.isArray(value)) {
    throw new Error("GitHub returned an unexpected releases payload.");
  }

  return value
    .filter(isGitHubRelease)
    .filter((release) => !release.draft)
    .sort((a, b) => {
      const aDate = a.published_at ?? a.created_at;
      const bDate = b.published_at ?? b.created_at;
      return new Date(bDate).getTime() - new Date(aDate).getTime();
    });
}

export function formatDisplayVersion(tagName: string): string {
  const match = tagName.match(/(\d+)(?:\.(\d+))?/);
  if (!match) {
    return tagName.startsWith("v") ? tagName : `v${tagName}`;
  }

  return `v${match[1]}${match[2] ? `.${match[2]}` : ""}`;
}

export const bundledGitHubReleases = parseReleases(releasesSnapshot);
