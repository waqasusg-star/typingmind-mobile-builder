# HDrama iOS 1.1.2 (build 4)

See BUILD_NOTES.md for the current compatibility changes and testing limits. This is native Swift/UIKit source. `xcodegen generate` reads project.yml; open HDrama.xcodeproj to build/sign locally. Minimum iOS 15.0. Bundle ID com.waqas.hdrama.

Use Site → Enable compatibility if verification stalls. It pauses ad filters and page helpers for this site and retains website storage. Restore ad blocking after verification. This is a compatibility fix, not a claim of passing Cloudflare on a real iPhone.

GitHub builds publish a versioned unsigned arm64 IPA, a matching source ZIP, SHA256SUMS.txt and Build-Report.json. Sign the IPA with a compatible certificate/profile before installing.
