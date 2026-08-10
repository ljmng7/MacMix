const baseUrl = import.meta.env.BASE_URL.endsWith("/")
  ? import.meta.env.BASE_URL
  : `${import.meta.env.BASE_URL}/`;

const basePath = baseUrl === "/" ? "" : baseUrl.slice(0, -1);

export type AppRoute = "home" | "changelog";

export const publicUrl = (path: string) => {
  if (/^(?:[a-z]+:)?\/\//i.test(path) || path.startsWith("data:")) {
    return path;
  }

  return `${baseUrl}${path.replace(/^\/+/, "")}`;
};

export const publicSrcSet = (srcSet?: string) =>
  srcSet
    ?.split(",")
    .map((candidate) => {
      const [url, ...descriptor] = candidate.trim().split(/\s+/);
      return [publicUrl(url), ...descriptor].join(" ");
    })
    .join(", ");

export const appRoutePath = (route: AppRoute) =>
  route === "changelog" ? `${basePath}/changelog` : `${basePath}/`;

export const appRouteFromPathname = (pathname: string): AppRoute => {
  const pathWithinSite =
    basePath && pathname.startsWith(basePath)
      ? pathname.slice(basePath.length) || "/"
      : pathname;

  return pathWithinSite.replace(/\/$/, "") === "/changelog"
    ? "changelog"
    : "home";
};
