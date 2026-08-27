import {
  IoArrowBack,
  IoArrowForward,
  IoArrowUp,
  IoLogoApple,
} from "react-icons/io5";
import { FaGithub } from "react-icons/fa6";
import {
  Suspense,
  lazy,
  useEffect,
  useRef,
  useState,
  type MouseEvent,
} from "react";
import { useReducedMotion } from "motion/react";
import { BlurFade } from "./components/BlurFade";
import { AnimatedDeviceSwitchIcon } from "./components/AnimatedDeviceSwitchIcon";
import { AnimatedInputGainIcon } from "./components/AnimatedInputGainIcon";
import { AnimatedSpeakerIcon } from "./components/AnimatedSpeakerIcon";
import { AnimatedSpeakerSlashIcon } from "./components/AnimatedSpeakerSlashIcon";
import { AnimatedSlidersIcon } from "./components/AnimatedSlidersIcon";
import { AnimatedStripedBoltIcon } from "./components/AnimatedStripedBoltIcon";
import { AnimatedVolumeMixIcon } from "./components/AnimatedVolumeMixIcon";
import { ConfettiButton } from "./components/ConfettiButton";
import { DiaTextReveal } from "./components/DiaTextReveal";
import { DownloadCallout } from "./components/DownloadCallout";
import { Highlighter } from "./components/Highlighter";
import { MacDesktopPreview } from "./components/MacDesktopPreview";
import { ThemeImage } from "./components/ThemeImage";
import { useGitHubReleases } from "./hooks/useGitHubReleases";
import { formatDisplayVersion } from "./lib/githubReleases";
import {
  appRouteFromPathname,
  appRoutePath,
  publicUrl,
  type AppRoute,
} from "./lib/sitePaths";

const DOWNLOAD_URL =
  "https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg";
const REPOSITORY_URL = "https://github.com/ljmng7/MacMix";
const ChangelogPage = lazy(() => import("./components/ChangelogPage"));
const LegalPage = lazy(() => import("./components/LegalPage"));

const FEATURES = [
  {
    title: "App-by-app volume mix",
    icon: "sliders",
  },
  {
    title: "Boost\u00a0up\u00a0to 200%",
    icon: "speaker-wave",
  },
  {
    title: "Instant device switching",
    icon: "device-switch",
  },
  {
    title: "Independent input gain",
    icon: "input-gain",
  },
  {
    title: "One-click muting",
    icon: "speaker-slash",
  },
  {
    title: "Always in the menu bar",
    icon: "volume-mix",
  },
  {
    title: "Crazy fast native app",
    icon: "striped-bolt",
  },
  {
    title: "Free and open source",
    icon: "github",
  },
] as const;

const SOCIAL_LINKS = [
  {
    label: "GitHub",
    href: "https://github.com/ljmng7",
    icon: "github-black.svg",
  },
  {
    label: "小红书",
    href: "https://www.xiaohongshu.com/user/profile/66a6d5f2000000001d020f1b",
    icon: "xiaohongshu-black.svg",
  },
  {
    label: "抖音",
    href: "https://v.douyin.com/aTWTd9BPAFI/",
    icon: "tiktok-black.svg",
  },
  {
    label: "X",
    href: "https://x.com/ming_li28643",
    icon: "x-black.svg",
  },
  {
    label: "Instagram",
    href: "https://www.instagram.com/lucid.jasmine/",
    icon: "instagram-black.svg",
  },
  {
    label: "Email",
    href: "mailto:jazmin_li@icloud.com",
    icon: "email-black.svg",
  },
] as const;

type SiteRoute = AppRoute;
type PagePhase = "idle" | "leaving" | "entering";

function getRouteFromPathname(): SiteRoute {
  return appRouteFromPathname(window.location.pathname);
}

function Brand({
  version,
  onBrandClick,
  onVersionClick,
}: {
  version: string;
  onBrandClick: (event: MouseEvent<HTMLAnchorElement>) => void;
  onVersionClick: (event: MouseEvent<HTMLAnchorElement>) => void;
}) {
  return (
    <div className="brand-lockup">
      <a
        className="brand"
        href="#top"
        aria-label="Back to top"
        onClick={onBrandClick}
      >
        <span className="brand__icon-frame" aria-hidden="true">
          <ThemeImage
            className="brand__icon"
            lightSrc="/assets/MacMix/MacMix.png"
            darkSrc="/assets/MacMix/MacMix_Dark.png"
            alt=""
          />
          <IoArrowUp className="brand__top-arrow" aria-hidden="true" />
        </span>
        <span className="brand__name">MacMix</span>
      </a>
      <a
        className="brand__version"
        href={appRoutePath("changelog")}
        aria-label={`Open changelog for ${version}`}
        onClick={onVersionClick}
      >
        {version}
      </a>
    </div>
  );
}

function ChangelogRouteLink({
  isBack,
  isTransitioning,
  onClick,
}: {
  isBack: boolean;
  isTransitioning: boolean;
  onClick: (event: MouseEvent<HTMLAnchorElement>) => void;
}) {
  return (
    <a
      className={[
        "header-link",
        "header-link--changelog",
        isBack && "header-link--back",
        isTransitioning && "header-link--transitioning",
      ]
        .filter(Boolean)
        .join(" ")}
      href={appRoutePath(isBack ? "home" : "changelog")}
      onClick={onClick}
      aria-label={isBack ? "Back home" : "Open changelog"}
      aria-disabled={isTransitioning || undefined}
    >
      <span
        className="header-link__face header-link__face--changelog"
        aria-hidden={isBack}
      >
        <img
          className="header-link__icon header-link__icon--changelog"
          src={publicUrl("/assets/MacMix/svgs/text.square.and.bookmark.fill.svg")}
          alt=""
          aria-hidden="true"
        />
        <span>Changelog</span>
      </span>
      <span
        className="header-link__face header-link__face--back"
        aria-hidden={!isBack}
      >
        <IoArrowBack
          className="header-link__icon header-link__back-arrow header-link__back-arrow--left"
          aria-hidden="true"
        />
        <span className="header-link__back-label">Back home</span>
        <IoArrowBack
          className="header-link__icon header-link__back-arrow header-link__back-arrow--right"
          aria-hidden="true"
        />
      </span>
    </a>
  );
}

function DownloadButton({ compact = false }: { compact?: boolean }) {
  const [isSuccessful, setIsSuccessful] = useState(false);

  const handleDownloadClick = () => {
    if (isSuccessful) {
      return;
    }

    window.requestAnimationFrame(() => {
      window.requestAnimationFrame(() => setIsSuccessful(true));
    });
  };

  return (
    <ConfettiButton
      className={[
        "download-button",
        compact && "download-button--compact",
        isSuccessful && "download-button--successful",
      ]
        .filter(Boolean)
        .join(" ")}
      href={DOWNLOAD_URL}
      download="MacMix.dmg"
      confettiDisabled={isSuccessful}
      effect={compact ? "fireworks" : "burst"}
      onClick={handleDownloadClick}
      options={{
        particleCount: 50,
        spread: 45,
        startVelocity: 45,
        decay: 0.9,
        gravity: 1,
        ticks: 200,
        scalar: 0.9,
        zIndex: 100,
        disableForReducedMotion: true,
        colors: ["#6c9bea", "#c9dcff", "#f4c65d", "#f2766b", "#f5f2ec"],
      }}
    >
      {isSuccessful ? (
        <span className="download-button__success" role="status" aria-live="polite">
          Successfully!
        </span>
      ) : (
        <span className="download-button__content">
          <IoLogoApple className="download-button__apple" aria-hidden="true" />
          <span className="download-button__label">Download for Mac</span>
          <IoArrowForward className="download-button__arrow" aria-hidden="true" />
        </span>
      )}
    </ConfettiButton>
  );
}

function Features() {
  return (
    <section className="features" aria-label="MacMix features">
      <ul className="features__grid">
        {FEATURES.map((feature) => (
          <li
            className={[
              "feature",
              feature.icon === "sliders" && "feature--sliders",
              feature.icon === "volume-mix" && "feature--volume-mix",
              feature.icon === "speaker-wave" && "feature--speaker-wave",
              feature.icon === "device-switch" && "feature--device-switch",
              feature.icon === "input-gain" && "feature--input-gain",
              feature.icon === "speaker-slash" && "feature--speaker-slash",
              feature.icon === "striped-bolt" && "feature--striped-bolt",
              feature.icon === "github" && "feature--github",
            ]
              .filter(Boolean)
              .join(" ")}
            key={feature.title}
          >
            <span className="feature__icon" aria-hidden="true">
              {feature.icon === "sliders" ? (
                <AnimatedSlidersIcon />
              ) : feature.icon === "volume-mix" ? (
                <AnimatedVolumeMixIcon />
              ) : feature.icon === "speaker-wave" ? (
                <AnimatedSpeakerIcon />
              ) : feature.icon === "device-switch" ? (
                <AnimatedDeviceSwitchIcon />
              ) : feature.icon === "input-gain" ? (
                <AnimatedInputGainIcon />
              ) : feature.icon === "speaker-slash" ? (
                <AnimatedSpeakerSlashIcon />
              ) : feature.icon === "striped-bolt" ? (
                <AnimatedStripedBoltIcon />
              ) : feature.icon === "github" ? (
                <FaGithub />
              ) : (
                null
              )}
            </span>
            <h2>{feature.title}</h2>
          </li>
        ))}
      </ul>
    </section>
  );
}

function HomeFooter() {
  return (
    <footer className="home-footer">
      <div className="home-footer__content">
        <DownloadButton />

        <nav className="home-footer__socials" aria-label="Contact and social links">
          {SOCIAL_LINKS.map((social) => {
            const isExternal = social.href.startsWith("http");

            return (
              <a
                className="home-footer__social"
                href={social.href}
                key={social.label}
                target={isExternal ? "_blank" : undefined}
                rel={isExternal ? "noopener noreferrer" : undefined}
                aria-label={social.label}
                title={social.label}
              >
                <img
                  src={publicUrl(`/assets/figma-social-icons/${social.icon}`)}
                  alt=""
                  aria-hidden="true"
                />
              </a>
            );
          })}
        </nav>
      </div>

      <div className="home-footer__wordmark" aria-hidden="true">
        MacMix
      </div>
    </footer>
  );
}

function HomePage() {
  return (
    <>
      <section className="hero" aria-labelledby="hero-title">
        <BlurFade className="hero__heading-wrap" delay={0.12}>
          <h1 className="hero__heading" id="hero-title">
            <span className="hero__heading-line--desktop">
              Your{" "}
              <Highlighter
                action="highlight"
                color="var(--accent-soft)"
                strokeWidth={2}
                animationDuration={650}
                iterations={2}
                padding={3}
                multiline={false}
                isView
                className="hero__mac-highlight"
              >
                <span className="hero__mac-lockup">
                  <IoLogoApple className="hero__apple" aria-hidden="true" />
                  <span>Mac&rsquo;s</span>
                </span>
              </Highlighter>{" "}
              sound.
            </span>
            <span className="hero__heading-line--desktop">
              All in one{" "}
              <DiaTextReveal
                className="hero__mix-reveal"
                text="Mix"
                textColor="var(--ink)"
              />
            </span>
            <span className="hero__heading-line--mobile">
              <Highlighter
                action="highlight"
                color="var(--accent-soft)"
                strokeWidth={2}
                animationDuration={650}
                iterations={2}
                padding={3}
                multiline={false}
                isView
                className="hero__mac-highlight"
              >
                <span className="hero__mac-lockup">
                  <IoLogoApple className="hero__apple" aria-hidden="true" />
                  <span>Mac&rsquo;s</span>
                </span>
              </Highlighter>{" "}
              sound.
            </span>
            <span className="hero__heading-line--mobile">
              In one{" "}
              <DiaTextReveal
                className="hero__mix-reveal"
                text="Mix"
                textColor="var(--ink)"
              />
            </span>
          </h1>
        </BlurFade>

        <BlurFade className="hero__actions" delay={0.28} offset={10}>
          <div className="hero__download-callout">
            <DownloadButton />
            <DownloadCallout />
          </div>
          <a
            className="github-button"
            href={REPOSITORY_URL}
            target="_blank"
            rel="noopener noreferrer"
          >
            <span className="github-button__content">
              <span className="github-button__icon-slot" aria-hidden="true">
                <FaGithub className="github-button__icon" />
              </span>
              <span className="github-button__label">View on GitHub</span>
            </span>
          </a>
        </BlurFade>

        <BlurFade className="hero__peek" delay={0.45} offset={18}>
          <MacDesktopPreview />
          <div className="preview-interaction-hint">
            <span className="preview-interaction-hint__icon" aria-hidden="true">
              <span className="preview-interaction-hint__hand" />
            </span>
            <span>Tips... It's interactive!</span>
          </div>
        </BlurFade>
      </section>
      <Features />
      <HomeFooter />
    </>
  );
}

export function App() {
  const headerRef = useRef<HTMLElement>(null);
  const transitionTimerRef = useRef<number | null>(null);
  const enterFrameRef = useRef<number | null>(null);
  const prefersReducedMotion = useReducedMotion();
  const [route, setRoute] = useState<SiteRoute>(getRouteFromPathname);
  const [pagePhase, setPagePhase] = useState<PagePhase>("idle");
  const [transitionTarget, setTransitionTarget] = useState<SiteRoute | null>(null);
  const { releases, isLoading, error, retry } = useGitHubReleases();
  const latestVersion = releases[0]
    ? formatDisplayVersion(releases[0].tag_name)
    : "v…";

  useEffect(() => {
    let frameId: number | null = null;

    const updateHeaderGlass = () => {
      frameId = null;
      const revealDistance = window.innerWidth <= 640 ? 60 : 80;
      const progress = Math.min(
        Math.max((window.scrollY - 4) / revealDistance, 0),
        1,
      );
      headerRef.current?.style.setProperty(
        "--header-scroll-progress",
        progress.toFixed(4),
      );
    };

    const handleScroll = () => {
      if (frameId === null) {
        frameId = window.requestAnimationFrame(updateHeaderGlass);
      }
    };

    updateHeaderGlass();
    window.addEventListener("scroll", handleScroll, { passive: true });
    window.addEventListener("resize", handleScroll, { passive: true });

    return () => {
      window.removeEventListener("scroll", handleScroll);
      window.removeEventListener("resize", handleScroll);
      if (frameId !== null) {
        window.cancelAnimationFrame(frameId);
      }
    };
  }, []);

  useEffect(() => {
    const handlePopState = () => {
      window.scrollTo(0, 0);
      setRoute(getRouteFromPathname());
      setPagePhase("entering");
      enterFrameRef.current = window.requestAnimationFrame(() => {
        setPagePhase("idle");
      });
    };

    window.addEventListener("popstate", handlePopState);
    return () => window.removeEventListener("popstate", handlePopState);
  }, []);

  useEffect(() => {
    switch (route) {
      case "changelog":
        document.title = "Changelog — MacMix";
        break;
      case "privacy-policy":
        document.title = "Privacy Policy — MacMix";
        break;
      case "terms-of-use":
        document.title = "Terms of Use — MacMix";
        break;
      case "home":
        document.title = "MacMix — Mac's sound. In one mix.";
        break;
    }
  }, [route]);

  useEffect(() => {
    return () => {
      if (transitionTimerRef.current !== null) {
        window.clearTimeout(transitionTimerRef.current);
      }
      if (enterFrameRef.current !== null) {
        window.cancelAnimationFrame(enterFrameRef.current);
      }
    };
  }, []);

  const navigateTo = (nextRoute: SiteRoute) => {
    if (nextRoute === route || pagePhase === "leaving") {
      window.scrollTo({ top: 0, behavior: prefersReducedMotion ? "auto" : "smooth" });
      return;
    }

    setTransitionTarget(nextRoute);
    setPagePhase("leaving");

    transitionTimerRef.current = window.setTimeout(
      () => {
        const nextPath = appRoutePath(nextRoute);
        window.history.pushState(null, "", nextPath);
        window.scrollTo(0, 0);
        setRoute(nextRoute);
        setTransitionTarget(null);
        setPagePhase("entering");

        enterFrameRef.current = window.requestAnimationFrame(() => {
          setPagePhase("idle");
        });
      },
      prefersReducedMotion ? 0 : 560,
    );
  };

  const handleBrandClick = (event: MouseEvent<HTMLAnchorElement>) => {
    event.preventDefault();
    window.scrollTo({
      top: 0,
      behavior: prefersReducedMotion ? "auto" : "smooth",
    });
  };

  const handleVersionClick = (event: MouseEvent<HTMLAnchorElement>) => {
    event.preventDefault();
    navigateTo("changelog");
  };

  const handleChangelogRouteClick = (event: MouseEvent<HTMLAnchorElement>) => {
    event.preventDefault();
    navigateTo(route === "home" ? "changelog" : "home");
  };

  const showBackControl = transitionTarget
    ? transitionTarget !== "home"
    : route !== "home";

  return (
    <div className="site-shell" id="top">
      <header ref={headerRef} className="site-header">
        <div className="site-header__inner">
          <BlurFade className="site-header__brand-reveal" delay={0.04} offset={6}>
            <Brand
              version={latestVersion}
              onBrandClick={handleBrandClick}
              onVersionClick={handleVersionClick}
            />
          </BlurFade>

          <nav className="site-nav" aria-label="Primary navigation">
            <BlurFade
              className="site-nav__item-reveal site-nav__item-reveal--route"
              delay={0.1}
              offset={6}
            >
              <ChangelogRouteLink
                isBack={showBackControl}
                isTransitioning={pagePhase === "leaving"}
                onClick={handleChangelogRouteClick}
              />
            </BlurFade>
            <BlurFade
              className="site-nav__item-reveal site-nav__item-reveal--download"
              delay={0.16}
              offset={6}
            >
              <DownloadButton compact />
            </BlurFade>
          </nav>
        </div>
      </header>

      <main
        className={`page-content page-content--${pagePhase}`}
        aria-busy={pagePhase !== "idle"}
      >
        {route === "changelog" ? (
          <Suspense fallback={<div className="changelog-module-loading" />}>
            <ChangelogPage
              releases={releases}
              isLoading={isLoading}
              error={error}
              onRetry={retry}
            />
          </Suspense>
        ) : route === "privacy-policy" || route === "terms-of-use" ? (
          <Suspense fallback={<div className="changelog-module-loading" />}>
            <LegalPage document={route} />
          </Suspense>
        ) : (
          <HomePage />
        )}
      </main>
    </div>
  );
}
