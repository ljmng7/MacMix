import assert from "node:assert/strict";
import test from "node:test";
import { normalizeReleases } from "../scripts/fetch-github-releases.mjs";

const release = (overrides = {}) => ({
  id: 1,
  tag_name: "v1.0.0",
  name: "MacMix 1.0.0",
  body: "Initial release",
  html_url: "https://github.com/ljmng7/MacMix/releases/tag/v1.0.0",
  published_at: "2026-01-01T00:00:00Z",
  created_at: "2026-01-01T00:00:00Z",
  prerelease: false,
  draft: false,
  ...overrides,
});

test("normalizes, filters drafts, and sorts releases newest first", () => {
  const result = normalizeReleases([
    release(),
    release({ id: 2, tag_name: "v1.1.0", published_at: "2026-02-01T00:00:00Z" }),
    release({ id: 3, tag_name: "v2.0.0", draft: true }),
  ]);

  assert.deepEqual(
    result.map(({ tag_name }) => tag_name),
    ["v1.1.0", "v1.0.0"],
  );
});

test("rejects malformed GitHub payloads", () => {
  assert.throws(() => normalizeReleases({}), /unexpected releases payload/);
  assert.throws(() => normalizeReleases([release({ id: "1" })]), /unexpected release payload/);
});
