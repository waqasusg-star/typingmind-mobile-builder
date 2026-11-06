# Native iPhone build repair

Source: uploaded HDrama-iOS-1.1.0-adblock.zip. Bundle ID com.waqas.hdrama, version 1.1.0, build 2, native Swift implementation and ad blocker preserved.

The first real Xcode 16.4 device archive reported three observer-token type errors. Download and playback observer properties now use NSObjectProtocol, matching NotificationCenter.addObserver. The HLS progress delegate now accepts [NSValue] and unwraps timeRangeValue, matching AVAssetDownloadDelegate. The standalone XcodeGen spec now generates correctly typed Info.plist values, including the audio background-mode array and iPad orientation array.

The native worker generates a controlled project and builds an arm64 iPhone device archive without certificates or UDIDs, runs static analysis, and verifies the IPA Payload and package hash. Its report records actual results. No test target was supplied; no unit/UI test or physical-device validation is claimed. Any resulting unsigned IPA MUST BE SIGNED BEFORE INSTALLATION with a compatible profile/certificate covering the device and app capabilities.
