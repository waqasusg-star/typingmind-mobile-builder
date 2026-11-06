# HDrama 1.1.2 (build 4)

Preserves com.waqas.hdrama and the existing native app features and stored data. Based on the uploaded 1.1.0 source, verified compiler fixes and the subsequent 1.1.1 source update.

- Known ad-host filtering remains; broad path and overlay/countdown heuristics are removed.
- Cosmetic rules apply only to the app site; DOM cleanup skips verification pages, protected widgets, forms, media and frames.
- Allows standard about:blank/about:srcdoc subframes and keeps website cookies/storage. No CAPTCHA solving, token spoofing or verification bypass is added.
- Tap Site → Enable compatibility to pause filtering and page helpers for this host, retaining cookies. Ads may appear. Restore blocking after verification to re-enable native Play detection.
- Observer token and HLS callback compiler fixes from 1.1.0 are retained.

The build report records actual compile/static analysis/device-package results, source SHA and file hashes. Physical-device Cloudflare completion, streaming, ad blocking and signing-service compatibility require real-device verification; no pass is claimed. IPA output is unsigned and must be signed before installation.
