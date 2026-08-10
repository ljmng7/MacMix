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

const RELEASES_API_URL =
  "https://api.github.com/repos/ljmng7/MacMix/releases?per_page=30";
const RELEASES_CACHE_KEY = "macmix.github-releases.v1";
const RELEASES_CACHE_TTL = 30 * 60 * 1000;

type ReleasesCache = {
  cachedAt: number;
  releases: GitHubRelease[];
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

export function readCachedReleases(): GitHubRelease[] | null {
  try {
    const rawCache = window.localStorage.getItem(RELEASES_CACHE_KEY);
    if (!rawCache) {
      return null;
    }

    const cache = JSON.parse(rawCache) as Partial<ReleasesCache>;
    if (
      typeof cache.cachedAt !== "number" ||
      Date.now() - cache.cachedAt > RELEASES_CACHE_TTL
    ) {
      return null;
    }

    return parseReleases(cache.releases);
  } catch {
    return null;
  }
}

export async function fetchGitHubReleases(
  signal?: AbortSignal,
): Promise<GitHubRelease[]> {
  const response = await fetch(RELEASES_API_URL, {
    headers: {
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
    },
    signal,
  });

  if (!response.ok) {
    throw new Error(`GitHub releases request failed with ${response.status}.`);
  }

  const releases = parseReleases(await response.json());

  try {
    window.localStorage.setItem(
      RELEASES_CACHE_KEY,
      JSON.stringify({ cachedAt: Date.now(), releases } satisfies ReleasesCache),
    );
  } catch {
    // Releases still render when storage is disabled or unavailable.
  }

  return releases;
}
