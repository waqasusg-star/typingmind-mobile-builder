# Mobile App Builder for TypingMind

This personal plugin lets Waqas operate app builds from a TypingMind conversation. It is a build controller, not a compiler in the browser. The chat model writes real Flutter app source and tests; a dedicated GitHub repository persists them and GitHub Actions performs Android/Linux and iPhone/macOS builds.

## Current status

The repository is public and Mobile App Builder v3 is installed and enabled in TypingMind. A repository-only Contents/Actions read-write token with No expiration is configured in its password setting. Android release signing inputs are stored in encrypted GitHub Actions Secrets. TypingMind verified the connection, generated the `builder_test` Flutter counter app and widget tests, saved commit `d7cd70825a05c2b66116fd2754186b8b164ca84e`, and dispatched Android run [42108523682](https://github.com/waqasusg-star/typingmind-mobile-builder/actions/runs/42108523682). Analysis, tests, release compilation, signature verification and Release publication all passed. [Download the signed test APK and report](https://github.com/waqasusg-star/typingmind-mobile-builder/releases/tag/builds%2Fbuilder_test%2Fbt-e2e-android-0001-d7cd7082%2Fandroid). No physical phone was tested. Apple signing remains unconfigured; no installable IPA has been delivered.

## Tools

Setup Status; Connect Builder; Install Build Pipeline; Save App Project; Read App Project; Build Android or iPhone; Check Build Progress; Get Build Downloads.

The controller restricts requests to one configured repository, requires explicit opt-in for public source operations, prevents unsafe file paths, commits without force, checks reviewed backend contents before builds and handles uncertain dispatches without blind retries. Native packages are returned as real TypingMind attachments only after ZIP checks, a successful signing report and matching SHA-256. Browser CORS/size limits or artifact expiry may require the official artifact download instead.

## One-time setup

Choose the GitHub account, create a dedicated repository initialized with a README, and configure its owner/repository in TypingMind plugin Settings. Enter a narrowly scoped GitHub token in the password field. The token needs Contents and Actions read/write, plus Workflows write for initial pipeline installation. ChatGPT's connected GitHub accounts do not automatically authorize TypingMind. Do not paste credentials in chat.

Install Build Pipeline writes only the reviewed `.github/workflows/mobile-builder.yml` plus `.builder/build.py` and `.builder/publish.py`; differing existing files are not overwritten. There are no push/pull-request build triggers, background chat loops, billing-limit changes or app-store publication. Builds run only on explicit dispatch and consume the account's GitHub Actions allowance/billing. Maximum worker times are 5 minutes for readiness, 30 minutes for Android and 40 minutes for iPhone. Diagnostic Actions artifact retention is 14 days. Successful signed packages, SHA-256 checksums and build reports are also saved in GitHub Releases, which have no automatic artifact expiry. A separate publishing job verifies the report identity and hashes and never executes app source. Release downloads are public in this repository; availability depends on GitHub and the repository remaining available.

Configure these repository secrets through GitHub's secure settings:

- Android: ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD. Preserve this signing identity for future app updates.
- iPhone: APPLE_CERTIFICATE_P12_BASE64, APPLE_CERTIFICATE_PASSWORD, APPLE_PROVISIONING_PROFILE_BASE64, APPLE_TEAM_ID. Direct installation requires an explicit, unexpired ad hoc profile for the app and target device(s). Initial Apple enrollment/authorization and phone installation prompts remain necessary.

Connection fields are optional in the UI so the offline Setup Status tool can run before setup; runtime checks still require them for every GitHub operation.

The plugin never reads secret values from GitHub. Build workers receive required signing inputs only for their build step; temporary signing files/keychains are removed and known secret values are redacted from uploaded logs. Source should contain no provider tokens or signing credentials. The build workers execute generated source/dependencies: use a dedicated repository and trusted dependencies.

## Workflow and scope

Ask TypingMind to create a Flutter app with real requested behavior and meaningful tests. Save UTF-8 source under `lib/`, `test/`, `assets/` and supported root files. `pubspec.yaml` name must match the stable project ID. Build the exact saved commit, keep its request ID, inspect readiness and build reports, repair actual failures and retrieve package artifacts. A missing/skipped platform is not successful delivery.

Version 3 supports text source/assets, not binary attachment import, native project overrides or arbitrary shell/workflow editing. External APIs, databases, notifications, permissions or native integrations need actual implementation and testing; they are not supplied automatically. Flutter stable is fetched from the official Flutter repository for each build, and the resolved SDK version is recorded in the report. SDK/dependency changes may require repairs.

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

Controller tests passed for settings/privacy, public-source opt-in, safe paths, credential guards, atomic non-forced writes, stale-edit protection, reviewed pipeline checks, uncertain dispatches, bounded ZIP/CRC/raw-deflate handling, signing-report/hash gates, attachment output and Release-link discovery after diagnostic artifact expiry. Four worker/publisher tests passed, including rejection of failed, unsigned, mismatched or tampered packages. Build workers retain read-only job tokens; the separate publisher alone has repository Contents write permission and executes no app source.

The first real Android run succeeded from inside TypingMind. The published APK SHA-256 is `8a64a9744b334108eb66d180a8b88438795c61c49f78d34e17efab3b6a44fb32`. Its Release has no automatic Actions artifact expiry. iOS compilation/signing, phone installation and physical-device behavior remain unverified.

## Public source and token lifetime

The owner requested public source and a token with No expiration. Public source must be explicitly enabled in TypingMind Settings. Repository visibility does not remove the need for authenticated writes/build control. The token remains in the TypingMind password field; Android/Apple signing inputs remain in encrypted GitHub Secrets and must never be committed. Public app source, logs and artifacts can be viewed by others, so client documents and private business data must not be embedded. No expiration means no scheduled expiry, not guaranteed lifetime: GitHub can revoke credentials and automatically revokes tokens unused for a year. Apple signing certificates/profiles have separate expiration rules.
