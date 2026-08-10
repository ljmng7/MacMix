import { useCallback, useEffect, useState } from "react";
import {
  fetchGitHubReleases,
  readCachedReleases,
  type GitHubRelease,
} from "../lib/githubReleases";

type ReleasesState = {
  releases: GitHubRelease[];
  isLoading: boolean;
  error: string | null;
};

export function useGitHubReleases() {
  const [state, setState] = useState<ReleasesState>(() => {
    const cachedReleases = readCachedReleases();
    return {
      releases: cachedReleases ?? [],
      isLoading: cachedReleases === null,
      error: null,
    };
  });

  const loadReleases = useCallback(async (signal?: AbortSignal) => {
    setState((current) => ({ ...current, isLoading: true, error: null }));

    try {
      const releases = await fetchGitHubReleases(signal);
      setState({ releases, isLoading: false, error: null });
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") {
        return;
      }

      setState((current) => ({
        ...current,
        isLoading: false,
        error:
          error instanceof Error
            ? error.message
            : "The releases could not be loaded.",
      }));
    }
  }, []);

  useEffect(() => {
    const controller = new AbortController();
    void loadReleases(controller.signal);
    return () => controller.abort();
  }, [loadReleases]);

  return {
    ...state,
    retry: () => void loadReleases(),
  };
}
