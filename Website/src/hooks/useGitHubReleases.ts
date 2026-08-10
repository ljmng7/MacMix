import {
  bundledGitHubReleases,
} from "../lib/githubReleases";

const retryBundledReleases = () => undefined;

export function useGitHubReleases() {
  return {
    releases: bundledGitHubReleases,
    isLoading: false,
    error: null,
    retry: retryBundledReleases,
  };
}
