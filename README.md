# Universal App Builder for TypingMind

This personal plugin lets Waqas operate app builds from a TypingMind conversation. It is a build controller, not a compiler in the browser. The chat model writes real Flutter app source and tests; a dedicated GitHub repository persists them and GitHub Actions performs Android/Linux and iPhone/macOS builds.

## Native Swift iPhone builds (v6)

Version 6 adds a separate native Swift/UIKit macOS pipeline. Inspect uploads with Toolbox/JSZip, save original files and app identity with **Save Native iPhone Project**, then run **Build Native iPhone IPA** at the exact saved SHA. **Check Native iPhone Build** resumes the same request. The worker generates a controlled XcodeGen spec and typed Info.plist, archives and analyzes an arm64 iPhone device app, verifies its bundle/Payload, and publishes the IPA, report and SHA-256 through a separate verifying publisher. Unsigned export needs no certificates or UDIDs; it **must be signed before installation**.

Supported native projects currently use Swift source, supported text Resources, system UIKit/WebKit/AVFoundation frameworks, audio background mode and minimum iOS 15. Uploaded build scripts, custom project overrides, third-party packages, entitlements and binary asset import are not supported by the controller. Extra requirements need a reviewed matching pipeline; never silently omit app capabilities. Tests are marked not run when no test target exists. Compile/analysis success does not imply unit/UI testing or physical-device testing.

Read App Project now discovers actual project IDs with `paths:[]` and no ID, reports framework/source hints and limits its claims to the configured repository/branch. Use exact returned file paths. Repository operations belong in builder tools, not Toolbox network fetches. The generated plugin embeds backend constants only in functions that need them to reduce duplicated data.

## Current status

The repository is public and Universal App Builder v5 is installed and enabled in TypingMind. A repository-only Contents/Actions read-write token with No expiration is configured in its password setting. Android release signing inputs are stored in encrypted GitHub Actions Secrets. TypingMind verified the connection, generated the `builder_test` Flutter counter app and widget tests, saved commit `d7cd70825a05c2b66116fd2754186b8b164ca84e`, and dispatched Android run [42108523682](https://github.com/waqasusg-star/typingmind-mobile-builder/actions/runs/42108523682). Analysis, tests, release compilation, signature verification and Release publication all passed. [Download the signed test APK and report](https://github.com/waqasusg-star/typingmind-mobile-builder/releases/tag/builds%2Fbuilder_test%2Fbt-e2e-android-0001-d7cd7082%2Fandroid). No physical phone was tested. Apple signing remains unconfigured; no installable IPA has been delivered.

## iPhone export for external signing

Version 5 adds `ios_unsigned`, Waqas's preferred iPhone route. It compiles an arm64 iPhone device build on macOS with Flutter `--no-codesign`, runs analysis and tests, checks device bundle metadata and executable architecture, and packages the real app under `Payload/<app>.app` in `-ios-unsigned.ipa`. No signing certificate, password or device ID is required, uploaded or used. This IPA **must be signed before installation** using a compatible signing service such as [IPA Signer](https://www.ipasigner.com/). The selected certificate/profile must support the app capabilities and target iPhone. A simulator app or source ZIP is never presented as the IPA. First live native validation of this export is pending.

Signed `ios` and `both` modes retain their existing certificate/profile requirements. `both` means signed Android + signed iPhone; it does not select unsigned export. Unsigned reports explicitly say `requires_signing: true`, `signature_verified: false` and `install_ready: false`. The Release publisher and downloader enforce the matching unsigned-package checks and hashes.

## Universal modes

Version 5 keeps the same plugin ID and private settings and adds Windows and Manifest V3 extension modes. Android and iPhone continue through the existing reviewed pipeline. Windows produces an unsigned per-user EXE installer and a portable ZIP containing the executable, Flutter assets/DLLs and Visual C++ runtime DLLs. CI runs analysis and widget tests, installs the generated installer in a temporary directory, launches the installed app, then removes the temporary installation. This is a launch smoke check, not full UI testing or trusted-publisher signing.

Extensions use `Save Chrome Extension`, safe UTF-8 JSON/HTML/CSS/JS/SVG/Markdown files, and a required `tests/extension.test.cjs` exporting `async function({context,extensionId,assert})`. The isolated Chromium test context loads the actual Manifest V3 package and runs the project's behavior checks. Missing generic icons/background worker are supplied by the packaging worker. Project metadata and test files are excluded from the ZIP. Load locally by extracting the ZIP, opening `chrome://extensions`, enabling Developer mode, and choosing Load unpacked. Chrome Web Store publication is separate and requires its developer account, listing/privacy disclosures and review. No automatic store publication or silent browser installation is performed.

Use `Save App Project` for Flutter apps and `Save Chrome Extension` for extensions. Keep project IDs and app identifiers stable. Build target choices are `android`, `ios`, `both` (Android + iPhone), `windows`, or `extension`. A Flutter project cannot be silently converted into an extension with the same ID. Build reports distinguish signed mobile apps, unsigned Windows software and unpacked extension packages. Download validation requires the corresponding successful analysis/tests, platform checks and package hashes.

Ask “check my build” to resume asynchronous jobs. The AI must not use interpreter wait loops or repeatedly dispatch builds to check progress. Get Build Downloads accepts `diagnostics_only: true` to read reports without attaching large binaries. Prefer lasting Release URLs for downloads.

The Chrome integration run [42112423188](https://github.com/waqasusg-star/typingmind-mobile-builder/actions/runs/42112423188) passed Manifest V3 validation, JavaScript syntax checks, real Chromium load and note persistence tests. Its ZIP is available in Releases. Windows run [42113711933](https://github.com/waqasusg-star/typingmind-mobile-builder/actions/runs/42113711933) passed analysis, widget tests, native compilation, silent installer deployment, installed-app launch, UTF-8 diagnostics and Release publication. Its unsigned EXE installer and portable ZIP are available in [Releases](https://github.com/waqasusg-star/typingmind-mobile-builder/releases). Apple signing remains unconfigured.

A dedicated Universal App Builder agent is configured and pinned in TypingMind with the existing working DeepSeek Flash model, only the Universal App Builder plugin, concise build-status instructions and conversation starters. Token/signing values were preserved and never copied into source.

## Tools

Setup Status; Connect Builder; Install Build Pipeline; Save App Project; Read App Project; Build App or Extension; Check Build Progress; Get Build Downloads; Save Chrome Extension.

The controller restricts requests to one configured repository, requires explicit opt-in for public source operations, prevents unsafe file paths, commits without force, checks reviewed backend contents before builds and handles uncertain dispatches without blind retries. Native packages are returned as real TypingMind attachments only after ZIP checks, a successful signing report and matching SHA-256. Browser CORS/size limits or artifact expiry may require the official artifact download instead.

## One-time setup

Choose the GitHub account, create a dedicated repository initialized with a README, and configure its owner/repository in TypingMind plugin Settings. Enter a narrowly scoped GitHub token in the password field. The token needs Contents and Actions read/write, plus Workflows write for initial pipeline installation. ChatGPT's connected GitHub accounts do not automatically authorize TypingMind. Do not paste credentials in chat.

Install Build Pipeline writes only the reviewed `.github/workflows/mobile-builder.yml` and `.builder/` helpers; differing existing files are not overwritten. There are no push/pull-request build triggers, background chat loops, billing-limit changes or app-store publication. Builds run only on explicit dispatch and consume the account's GitHub Actions allowance/billing. Maximum worker times are 5 minutes for readiness, 30 minutes for Android, 40 minutes for iPhone, 35 minutes for Windows and 12 minutes for extensions. Diagnostic Actions artifact retention is 14 days. Successful signed packages, SHA-256 checksums and build reports are also saved in GitHub Releases, which have no automatic artifact expiry. A separate publishing job verifies the report identity and hashes and never executes app source. Release downloads are public in this repository; availability depends on GitHub and the repository remaining available.

Configure these repository secrets through GitHub's secure settings:

- Android: ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD. Preserve this signing identity for future app updates.
- iPhone: APPLE_CERTIFICATE_P12_BASE64, APPLE_CERTIFICATE_PASSWORD, APPLE_PROVISIONING_PROFILE_BASE64, APPLE_TEAM_ID. Direct installation requires an explicit, unexpired ad hoc profile for the app and target device(s). Initial Apple enrollment/authorization and phone installation prompts remain necessary.

Connection fields are optional in the UI so the offline Setup Status tool can run before setup; runtime checks still require them for every GitHub operation.

The plugin never reads secret values from GitHub. Build workers receive required signing inputs only for their build step; temporary signing files/keychains are removed and known secret values are redacted from uploaded logs. Source should contain no provider tokens or signing credentials. The build workers execute generated source/dependencies: use a dedicated repository and trusted dependencies.

## Workflow and scope

Ask TypingMind to create a Flutter app with real requested behavior and meaningful tests. Save UTF-8 source under `lib/`, `test/`, `assets/` and supported root files. `pubspec.yaml` name must match the stable project ID. Build the exact saved commit, keep its request ID, inspect readiness and build reports, repair actual failures and retrieve package artifacts. A missing/skipped platform is not successful delivery.

Version 4 supports text source/assets, not binary attachment import, native project overrides or arbitrary shell/workflow editing. External APIs, databases, notifications, permissions or native integrations need actual implementation and testing; they are not supplied automatically. Flutter stable is fetched from the official Flutter repository for each build, and the resolved SDK version is recorded in the report. SDK/dependency changes may require repairs.

The iOS workflow is prepared but untested on a Mac with signing access; Xcode/CocoaPods/provisioning compatibility must be validated in the first real run. A successful signature is not proof of functional testing on a phone. The plugin never presents simulator builds, source ZIPs or unsigned IPAs as installable apps.

## Development

Run `python3 typingmind-plugin/build_plugin.py` to regenerate the installable JSON. Run `node tests/test.cjs` and `python3 -m unittest discover -s tests -p 'test_*.py'` before installation. Import `typingmind-plugin/Mobile-App-Builder.json` through TypingMind → Plugins → Create plugin → JSON Editor if it is not already installed.

Official references:

- https://docs.typingmind.com/plugins/build-a-typingmind-plugin
- https://docs.github.com/en/rest/actions/workflows
- https://docs.github.com/en/rest/actions/artifacts
- https://docs.github.com/en/rest/git/trees
- https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile

## Validation

Controller tests passed for settings/privacy, public-source opt-in, safe paths, credential guards, atomic non-forced writes, stale-edit protection, reviewed pipeline checks, uncertain dispatches, bounded ZIP/CRC/raw-deflate handling, signing-report/hash gates, attachment output and Release-link discovery after diagnostic artifact expiry. Eight worker/publisher tests passed, covering missing mobile signing, extension source/path validation, platform-specific package release gates, tampered hashes, and Unicode failure logs under Windows legacy encoding. Build workers retain read-only job tokens; the separate publisher alone has repository Contents write permission and executes no app source.

The first real Android run succeeded from inside TypingMind. The published APK SHA-256 is `8a64a9744b334108eb66d180a8b88438795c61c49f78d34e17efab3b6a44fb32`. Its Release has no automatic Actions artifact expiry. iOS compilation/signing, phone installation and physical-device behavior remain unverified.

## Public source and token lifetime

The owner requested public source and a token with No expiration. Public source must be explicitly enabled in TypingMind Settings. Repository visibility does not remove the need for authenticated writes/build control. The token remains in the TypingMind password field; Android/Apple signing inputs remain in encrypted GitHub Secrets and must never be committed. Public app source, logs and artifacts can be viewed by others, so client documents and private business data must not be embedded. No expiration means no scheduled expiry, not guaranteed lifetime: GitHub can revoke credentials and automatically revokes tokens unused for a year. Apple signing certificates/profiles have separate expiration rules.

## Version 7 delivery and work modules

Native builds publish a versioned unsigned IPA and matching updated source ZIP, plus hashes and a build report. Actual archived app version/build must match metadata. Plugin Settings → Work modules profile chooses Complete delivery, Review and fix, Web compatibility, or Build and release. Select Work Modules can choose individual task modules. This organizes the selected model’s work; it does not guarantee correctness or create unsupported tools. Cloudflare completion remains a real-device check; builds never solve verification challenges.
