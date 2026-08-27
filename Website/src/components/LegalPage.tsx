import { BlurFade } from "./BlurFade";

type LegalDocument = "privacy-policy" | "terms-of-use";

type LegalPageProps = {
  document: LegalDocument;
};

const LAST_UPDATED = "August 27, 2026";

function ExternalLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <a href={href} target="_blank" rel="noopener noreferrer">
      {children}
    </a>
  );
}

function PrivacyPolicy() {
  return (
    <>
      <p className="legal-document__updated">
        <strong>Last updated:</strong>{" "}
        <time dateTime="2026-08-27">{LAST_UPDATED}</time>
      </p>

      <p>
        MacMix is a native macOS audio utility. This Privacy Policy explains what
        information MacMix processes, where that processing happens, and when
        information is shared with service providers. It applies to the MacMix app,
        MacMix Studio licensing, and the MacMix website.
      </p>

      <h2>1. Audio and device data stay on your Mac</h2>
      <p>
        MacMix reads information exposed by macOS to show and control audio devices,
        system volume, microphone input gain, per-app audio sessions, Bluetooth audio
        accessory battery levels, listening modes, Spatial Audio state, and—when you
        enable the feature—Now Playing information.
      </p>
      <p>
        Per-app mixing uses macOS audio process taps for local, real-time volume
        control. MacMix does not record, save, transmit, or upload the audio content it
        processes. Audio samples are used only in memory to produce the adjusted output
        on your Mac.
      </p>

      <h2>2. Permissions</h2>
      <ul>
        <li>
          <strong>System Audio Recording:</strong> required only for per-app audio
          mixing. MacMix uses it to process app audio locally and not to create a
          recording.
        </li>
        <li>
          <strong>Bluetooth:</strong> used to read battery information for connected
          audio accessories when supported by macOS and the device.
        </li>
      </ul>
      <p>
        You can manage these permissions at any time in macOS System Settings. Some
        features will be unavailable if the relevant permission is denied or revoked.
      </p>

      <h2>3. Information stored locally</h2>
      <p>
        MacMix stores settings on your Mac, including interface preferences, panel
        visibility, per-app volume and mute choices, app exclusions, device-related
        volume preferences, and permission-status hints. These settings can include app
        bundle identifiers and locally visible device identifiers or names needed to
        restore your choices. They are not uploaded by MacMix.
      </p>
      <p>
        If you activate MacMix Studio, the license key, license instance identifiers,
        and validation timestamps are stored in the macOS Keychain on that Mac. Studio
        deactivation removes those local license credentials. Other preferences remain
        until you reset them or remove the related app data; uninstalling the app alone
        may not remove Keychain items.
      </p>

      <h2>4. MacMix Studio purchases and licensing</h2>
      <p>
        Studio checkout is hosted by Dodo Payments, which acts as the merchant of record.
        Dodo Payments collects and processes the information needed to complete the
        transaction, such as your name, email address, billing details, payment details,
        tax information, fraud-prevention signals, and purchase records. MacMix does not
        receive or store your full card or payment-account details. Review the{" "}
        <ExternalLink href="https://dodopayments.com/privacy-policy">
          Dodo Payments Privacy Policy
        </ExternalLink>{" "}
        for its independent processing practices.
      </p>
      <p>
        MacMix uses a Cloudflare Worker to request the hosted checkout session and to
        receive signed entitlement events from Dodo Payments. The entitlement service
        stores limited transaction and license-delivery records in a private Neon
        PostgreSQL database, including Dodo customer, payment, entitlement, grant, and
        webhook identifiers; delivery or revocation status; timestamps; and relevant
        error information. It intentionally does not store the issued license key or the
        complete webhook payload.
      </p>
      <p>
        When you activate, validate, or deactivate Studio, MacMix sends the license key,
        a locally provided name for the Mac, and the applicable license instance
        identifier to Dodo Payments. This is necessary to enforce the device limit,
        confirm entitlement status, and release an activation when you deactivate a Mac.
      </p>

      <h2>5. Updates, website hosting, and technical logs</h2>
      <p>
        MacMix uses Sparkle to check the official MacMix update feed hosted through
        GitHub. Those network requests necessarily disclose ordinary connection data,
        such as your IP address and user agent, to the hosting provider. MacMix does not
        add advertising or behavioral analytics to update checks.
      </p>
      <p>
        The MacMix website is hosted with GitHub Pages. MacMix does not use advertising
        trackers or first-party analytics on the website. GitHub states that it logs a
        visitor&apos;s IP address for security purposes when a GitHub Pages site is visited;
        its handling of that information is governed by the{" "}
        <ExternalLink href="https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement">
          GitHub Privacy Statement
        </ExternalLink>
        . Cloudflare, Neon, Dodo Payments, and GitHub may also retain security and
        operational logs under their own policies.
      </p>

      <h2>6. How information is used and shared</h2>
      <p>
        Information handled outside your Mac is used only to provide checkout, deliver
        and administer licenses, prevent fraud and abuse, comply with tax and legal
        obligations, maintain service security, distribute updates, and respond to
        support requests. MacMix does not sell personal information and does not share it
        for cross-context behavioral advertising.
      </p>
      <p>
        Service providers may process information in countries other than your own. They
        act under their own terms and privacy policies, and may disclose information when
        required by law or necessary to protect their services and users.
      </p>

      <h2>7. Retention and security</h2>
      <p>
        Local preferences remain on your Mac until you change or remove them. Studio
        transaction and entitlement records are retained only as reasonably necessary to
        deliver and verify licenses, handle support, prevent abuse, maintain accounting
        records, and meet legal obligations. Payment providers may retain transaction
        records for longer periods required by financial, tax, fraud-prevention, and
        compliance rules.
      </p>
      <p>
        Reasonable technical and organizational safeguards are used, including HTTPS,
        signed webhooks, private service credentials, limited database records, and the
        macOS Keychain. No storage or transmission method can be guaranteed to be
        completely secure.
      </p>

      <h2>8. Your choices and rights</h2>
      <p>
        You can revoke macOS permissions, change or delete local preferences, deactivate
        a Studio license on a Mac, and contact us about access, correction, deletion, or
        other rights available under applicable privacy law. Requests concerning payment
        information controlled directly by Dodo Payments should also be submitted through
        Dodo Payments&apos; privacy or support channels. Some records may be retained where
        required by law or needed to establish, exercise, or defend legal claims.
      </p>

      <h2>9. Children</h2>
      <p>
        MacMix is a general-purpose utility and is not directed to children. We do not
        knowingly collect personal information from children through MacMix. If you
        believe a child has provided personal information, please contact us.
      </p>

      <h2>10. Changes and contact</h2>
      <p>
        This policy may be updated when MacMix features, service providers, or legal
        requirements change. The date at the top of this page will identify the latest
        version. Questions or privacy requests can be sent to{" "}
        <a href="mailto:jazmin_li@icloud.com">jazmin_li@icloud.com</a>.
      </p>
    </>
  );
}

function TermsOfUse() {
  return (
    <>
      <p className="legal-document__updated">
        <strong>Last updated:</strong>{" "}
        <time dateTime="2026-08-27">{LAST_UPDATED}</time>
      </p>

      <p>
        These Terms of Use govern your use of the official MacMix application, MacMix
        Studio features, website, downloads, and related services. By downloading,
        installing, purchasing, or using MacMix, you agree to these terms. If you do not
        agree, do not use MacMix or purchase MacMix Studio.
      </p>

      <h2>1. MacMix and MacMix Studio</h2>
      <p>
        MacMix provides native macOS controls for system volume, audio input and output
        devices, per-app audio mixing, and related audio features. Some capabilities are
        included in the free version, while additional capabilities require a valid
        MacMix Studio license.
      </p>
      <p>
        Feature availability can depend on your Mac, macOS version, connected hardware,
        app behavior, granted permissions, and interfaces made available by Apple or
        other device vendors. A feature shown in MacMix may be unavailable when the
        required system or hardware support is absent.
      </p>

      <h2>2. Free and open-source software</h2>
      <p>
        The public MacMix source code is made available under the{" "}
        <ExternalLink href="https://github.com/ljmng7/MacMix/blob/main/LICENSE">
          MIT License
        </ExternalLink>
        . That license governs the source code identified by the repository. MacMix names,
        app icons, screenshots, artwork, and other brand assets are not granted under the
        MIT License unless expressly stated otherwise.
      </p>

      <h2>3. Studio license</h2>
      <p>
        MacMix Studio is currently offered as a one-time purchase for activation on up to
        three Macs that you own or control. A purchase grants a limited, non-exclusive,
        non-transferable, revocable right to use the Studio features included with the
        product. It does not transfer ownership of MacMix, its private source code, or its
        brand assets.
      </p>
      <p>
        You are responsible for keeping your license key confidential. You may not sell,
        publish, share, sublicense, or use a key to exceed the applicable activation
        limit. You may deactivate one Mac and activate another through MacMix, subject to
        the license service being available and the entitlement remaining valid.
      </p>
      <p>
        “One-time purchase” means there is no recurring subscription charge for the
        purchased Studio license. It does not promise that every future product, paid
        add-on, major edition, third-party service, or feature will be included forever.
        Updates and future Studio features may be added, changed, or discontinued as the
        product evolves, subject to applicable law and any specific promise made at the
        time of purchase.
      </p>

      <h2>4. Payment, taxes, delivery, and refunds</h2>
      <p>
        Dodo Payments is the merchant of record and authorized reseller for MacMix Studio.
        Dodo Payments processes payment, applicable taxes, invoices, fraud checks,
        disputes, and refunds. Your transaction is also governed by the{" "}
        <ExternalLink href="https://dodopayments.com/archive/buyer-terms">
          Dodo Payments Buyer Terms
        </ExternalLink>
        . Prices, currency conversion, purchasing-power adjustments, and taxes shown at
        checkout may vary by location and payment method.
      </p>
      <p>
        After successful payment, Dodo Payments delivers the license key to the email
        address supplied at checkout. You are responsible for providing an accurate email
        address and retaining access to the key. If delivery fails or the key does not
        activate, contact us with the order details so the issue can be investigated.
      </p>
      <p>
        Refund requests are handled by Dodo Payments in accordance with its Buyer Terms,
        platform rules, and applicable consumer law. A refund, chargeback, reversal,
        fraudulent transaction, or revoked entitlement may cause the corresponding Studio
        license to be disabled.
      </p>

      <h2>5. Acceptable use</h2>
      <p>You must not:</p>
      <ul>
        <li>use MacMix or its services in violation of applicable law;</li>
        <li>share, resell, publish, or fraudulently obtain Studio license keys;</li>
        <li>circumvent licensing, activation limits, security, or access controls;</li>
        <li>
          interfere with the checkout, licensing, update, website, or entitlement
          infrastructure, including through automated abuse or excessive requests; or
        </li>
        <li>
          misuse MacMix to access or process audio or information without the permissions
          and authority required by law.
        </li>
      </ul>
      <p>
        Nothing in this section restricts rights expressly granted by an applicable
        open-source license or rights that cannot lawfully be restricted.
      </p>

      <h2>6. Updates and service changes</h2>
      <p>
        MacMix may provide updates through Sparkle or other official distribution
        channels. Updates can add, modify, or remove features; address compatibility or
        security issues; or change minimum system requirements. Licensing, checkout,
        update, and website services may occasionally be unavailable for maintenance,
        security, network, or third-party reasons.
      </p>

      <h2>7. Your responsibilities</h2>
      <p>
        You are responsible for deciding whether MacMix is suitable for your setup,
        maintaining appropriate backups, reviewing volume levels before playback, and
        using audio, Bluetooth, and system permissions responsibly. Audio routing and
        volume changes can affect connected equipment, recordings, calls, streams, and
        hearing safety; verify important configurations before relying on them.
      </p>

      <h2>8. Third-party services and content</h2>
      <p>
        MacMix depends on macOS frameworks and may link to or interoperate with services
        provided by Apple, Dodo Payments, Cloudflare, Neon, GitHub, Sparkle, and hardware
        or app vendors. Their products and services are governed by their own terms and
        policies. MacMix is not responsible for third-party availability, changes, or
        content.
      </p>

      <h2>9. Disclaimer of warranties</h2>
      <p>
        To the maximum extent permitted by law, MacMix and its related services are
        provided “as is” and “as available,” without warranties of any kind, express or
        implied, including warranties of merchantability, fitness for a particular
        purpose, non-infringement, uninterrupted availability, or error-free operation.
        Nothing in these terms excludes warranties or consumer rights that cannot be
        excluded under applicable law.
      </p>

      <h2>10. Limitation of liability</h2>
      <p>
        To the maximum extent permitted by law, the MacMix developer will not be liable
        for indirect, incidental, special, consequential, or punitive damages, or for lost
        data, revenue, profits, business, or use arising from MacMix or related services.
        Where liability cannot be excluded, total liability relating to a paid Studio
        license will not exceed the amount you paid for that license. These limits do not
        apply where prohibited by law.
      </p>

      <h2>11. Suspension and termination</h2>
      <p>
        Studio access may be suspended or revoked if the entitlement is refunded,
        reversed, fraudulent, used beyond its activation limit, or materially violates
        these terms. You may stop using MacMix at any time and may deactivate Studio from
        the app. Provisions that by their nature should survive termination—including
        intellectual property, disclaimers, limitations of liability, and payment
        obligations—will continue to apply.
      </p>

      <h2>12. Changes, severability, and contact</h2>
      <p>
        These terms may be updated to reflect product, service, or legal changes. Material
        changes will apply prospectively where required by law. If any provision is found
        unenforceable, the remaining provisions remain in effect. Failure to enforce a
        provision is not a waiver of it.
      </p>
      <p>
        Questions about MacMix or these terms can be sent to{" "}
        <a href="mailto:jazmin_li@icloud.com">jazmin_li@icloud.com</a>.
      </p>
    </>
  );
}

export function LegalPage({ document }: LegalPageProps) {
  const isPrivacyPolicy = document === "privacy-policy";
  const title = isPrivacyPolicy ? "Privacy Policy" : "Terms of Use";

  return (
    <section className="changelog-page legal-page" aria-labelledby="legal-page-title">
      <BlurFade className="changelog-intro" delay={0.05} offset={10} blur={false}>
        <h1 id="legal-page-title">{title}</h1>
      </BlurFade>

      <BlurFade className="legal-document release-entry__markdown" delay={0.12} offset={14}>
        {isPrivacyPolicy ? <PrivacyPolicy /> : <TermsOfUse />}
      </BlurFade>
    </section>
  );
}

export default LegalPage;
