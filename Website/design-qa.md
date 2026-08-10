# Design QA — Homepage footer

- Source visual truth: `/var/folders/5w/7prlyhqs05qgkt_704cr22vh0000gn/T/codex-clipboard-62ed0766-99e9-4145-a722-6fb960a9060f.png`
- Desktop implementation: `/tmp/macmix-wordmark-smaller-spaced-desktop.png`
- Mobile implementation: `/tmp/macmix-wordmark-smaller-spaced-mobile.png`
- Source pixels: `3248 × 1998`; the source includes browser chrome and a different product header, so the comparison is normalized to the lower CTA/social/wordmark composition rather than treated as a 1:1 full-page clone.
- Desktop viewport and pixels: `1440 × 1000` CSS px at device scale `1`, captured as `1440 × 1000` pixels.
- Mobile viewport and pixels: `390 × 844` CSS px at device scale `1`, captured as `390 × 844` pixels.
- State: homepage scrolled to the bottom, social buttons at rest; hover was checked separately.

## Full-view comparison evidence

The source and final desktop capture were opened together in one comparison view. The implementation preserves the reference hierarchy: final feature row, centered dark Download for Mac CTA, a muted glass social row, and an oversized single-color wordmark cropped by the page bottom. The implementation intentionally uses the six direct contact links from the supplied personal homepage rather than the source screenshot's unrelated three services.

## Focused region comparison evidence

The footer region was inspected at desktop and mobile sizes. The CTA reuses the existing MacMix button component and matches the site's established typography, radius, motion, and brown shadow. Supplied black SVGs are used without path changes. The wordmark uses `--ink` only; the visible fade comes from a transparency mask. Mobile has no horizontal overflow, and all six contact controls remain on one centered row.

## Required fidelity surfaces

- Fonts and typography: the CTA and wordmark use the site's existing system font stack and approved optical weights. No reference-specific foreign typography was introduced.
- Spacing and layout rhythm: the final vertical rhythm closely follows the source's CTA → social row → wordmark sequence. The feature section remains untouched.
- Colors and visual tokens: the footer uses `--paper`, `--ink`, and `--button-glass`; the wordmark has no color gradient.
- Image quality and asset fidelity: all six social icons are byte-identical copies of the supplied `figma-social-icons/*-black.svg` source assets.
- Copy and content: CTA remains `Download for Mac`; contacts and destinations match the personal homepage.

## Comparison history

1. Initial capture found one P2 spacing issue: the CTA was too close to the features while the social row was too far from the wordmark.
2. Fixed by moving the footer content down and shortening the footer stage, preserving the source's three-part vertical rhythm.
3. Post-fix desktop and mobile captures show no remaining P0, P1, or P2 mismatch.
4. User follow-up identified the remaining feature-to-download gap as too large. The stacked spacing was reduced from `270px` to `128px` on desktop and from `176px` to `98px` on mobile; the revised captures preserve the social/wordmark rhythm without overflow.
5. A second follow-up reduced the social controls to `42/20px` desktop and `38/18px` mobile button/art sizes. The wordmark was reduced to `21vw`, its tracking relaxed from `-0.085em` to `-0.055em`, and its base opacity lowered from `12%` to `8.5%` with a quieter mask midpoint.
6. The final `x` received responsive transparent inline padding so its glyph no longer touches the footer crop boundary; at `390px` it retains about `7px` of internal right safety space with no horizontal overflow. Social hover elevation was removed completely: the button shell stays at the exact same coordinates and only its icon changes from `46%` to `82%` opacity while scaling to `1.06`.
7. The wordmark was reduced again to `18.5vw` desktop and `25vw` mobile while tracking was relaxed to `-0.03em`. At `390px` the rendered wordmark is about `351px` wide with roughly `19px` on each side and no clipping.

## Interaction and runtime checks

- Download href resolves to the existing latest-release DMG URL.
- GitHub, 小红书, 抖音, X, Instagram, and Email hrefs match the personal homepage.
- Social icon opacity transitions from `0.46` to `1` on hover and returns to `0.46` on exit.
- Browser console errors: `0`.
- Mobile horizontal overflow: `0px`.

## Follow-up polish

No blocking follow-up. The six-service row is an intentional content expansion from the three-icon visual reference.

final result: passed
