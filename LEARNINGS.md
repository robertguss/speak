# Learnings

## Mac distribution

- Share the Mac app as a notarized Developer ID DMG: archive `SpeakMac` (Release), export with `method: developer-id`, then notarize and staple the app first and the DMG second. `xcrun notarytool` works with the App Store Connect API key (`~/.asc/keys/AuthKey_MGCM6P66Z4.p8`, key ID `MGCM6P66Z4`, issuer `f12a1d2d-b2d6-4c91-89ab-639b18bae03c`).
- `codesign --sign "Developer ID Application: Robert Guss (34SDRG9ZZ2)"` is ambiguous because the certificate is in both the System and login keychains. Sign with the SHA-1 hash `06454DF4B8A0FF3888D64377C064C4E9F7A643E8` instead.
- macOS ties the Accessibility grant to the code signature. Debug and Release builds from Xcode are signed with Apple Development, but share the bundle ID with the Developer ID build, so their old grants make the switch in System Settings do nothing for the installed app. Fix: quit Speak, run `tccutil reset Accessibility com.robertguss.speak.mac` (plus `ListenEvent` and `PostEvent`), delete the Apple Development copies, then grant the permission again.
- Mac TestFlight requires App Sandbox. According to Apple DTS, posting ⌘V (PostEvent privilege) and a listen-only `CGEventTap` (Input Monitoring) work in a sandboxed app. `AXIsProcessTrusted` and a `.defaultTap` event tap do not, and the Wispr import would need a folder picked by the user. Speak has not been ported to the sandbox.

## iOS TestFlight

- App Store Connect record: "Speak Dictation" (app ID `6827558692`, bundle ID `com.robertguss.speak.ios`). The name "Speak" was already taken. The home-screen name still comes from `CFBundleDisplayName`.
- Apps can't be created through the App Store Connect API; the first record has to be made by hand on the website.
- Upload with `xcodebuild -exportArchive` and `method: app-store-connect`, `destination: upload`. Each upload needs a higher `CURRENT_PROJECT_VERSION`.
- The `asc` CLI rejects a `.p8` key file that other users can read; `chmod 600` it.
