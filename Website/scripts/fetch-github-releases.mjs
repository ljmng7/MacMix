#!/usr/bin/env node
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const outputPath = path.join(root, "src", "generated", "github-releases.json");

const isNullableString = (value) => typeof value === "string" || value === null;

const normalizeRelease = (value) => {
  if (
    typeof value !== "object" ||
    value === null ||
    typeof value.id !== "number" ||
    typeof value.tag_name !== "string" ||
    !isNullableString(value.name) ||
    !isNullableString(value.body) ||
    typeof value.html_url !== "string" ||
    !isNullableString(value.published_at) ||
    typeof value.created_at !== "string" ||
    typeof value.prerelease !== "boolean" ||
    typeof value.draft !== "boolean"
  ) {
    throw new Error("GitHub returned an unexpected release payload.");
  }

  return {
    id: value.id,
    tag_name: value.tag_name,
    name: value.name,
    body: value.body,
    html_url: value.html_url,
    published_at: value.published_at,
    created_at: value.created_at,
    prerelease: value.prerelease,
    draft: value.draft,
  };
};

export const normalizeReleases = (value) => {
  if (!Array.isArray(value)) {
    throw new Error("GitHub returned an unexpected releases payload.");
  }

  return value
    .map(normalizeRelease)
    .filter((release) => !release.draft)
    .sort((a, b) => {
      const aDate = a.published_at ?? a.created_at;
      const bDate = b.published_at ?? b.created_at;
      return new Date(bDate).getTime() - new Date(aDate).getTime();
    });
};

export async function generateReleaseSnapshot({
  repository = process.env.GITHUB_REPOSITORY || "ljmng7/MacMix",
  apiUrl = process.env.GITHUB_API_URL || "https://api.github.com",
  token = process.env.GITHUB_TOKEN,
  fetchImpl = fetch,
  destination = outputPath,
} = {}) {
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository)) {
    throw new Error(`Invalid GitHub repository: ${repository}`);
  }

  const apiBase = apiUrl.endsWith("/") ? apiUrl : `${apiUrl}/`;
  const requestUrl = new URL(`repos/${repository}/releases`, apiBase);
  requestUrl.searchParams.set("per_page", "30");

  const headers = {
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "MacMix-Pages-build",
  };
  if (token) headers.Authorization = `Bearer ${token}`;

  const response = await fetchImpl(requestUrl, { headers });
  if (!response.ok) {
    throw new Error(
      `GitHub releases snapshot failed with ${response.status}: ${await response.text()}`,
    );
  }

  const releases = normalizeReleases(await response.json());
  await mkdir(path.dirname(destination), { recursive: true });
  await writeFile(destination, `${JSON.stringify(releases, null, 2)}\n`, "utf8");
  return releases;
}

const invokedPath = process.argv[1] ? pathToFileURL(process.argv[1]).href : null;
if (invokedPath === import.meta.url) {
  const releases = await generateReleaseSnapshot();
  console.log(`Generated ${path.relative(root, outputPath)} with ${releases.length} releases.`);
}
