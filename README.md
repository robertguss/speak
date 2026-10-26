# Speak

Open-source, bring-your-own-key dictation for Mac, iPhone, and iPad.

- **Mac:** a menu bar app. Tap or hold one modifier key to dictate, and the text is pasted at the cursor.
- **iPhone/iPad:** a custom keyboard that inserts dictated text into any app. The main app records in the background.
- **Providers:** OpenAI-compatible (OpenAI, Groq, local servers), Deepgram, or ElevenLabs Scribe, with an optional LLM cleanup pass.
- **Settings and keys** sync between devices through iCloud Keychain.
- **Private by design:** no account, no server, no analytics. Audio goes only to the provider you choose, and each clip is deleted after it's transcribed.

The plan is in [`docs/plans/2026-10-25-2102-feat-byok-dictation-app-plan.md`](docs/plans/2026-10-25-2102-feat-byok-dictation-app-plan.md).

## Requirements

- Xcode 27 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- An Apple Developer account. The team ID is set once, as `DEVELOPMENT_TEAM` in `project.yml`.
- iCloud Keychain turned on for every device that should share settings.

## Build your own copy

Bundle IDs are unique across all Apple developer teams, so to build Speak under your own account, swap in your team ID and your own reverse-DNS prefix:

1. In `project.yml`, set `DEVELOPMENT_TEAM` to your team ID (Xcode → Settings → Accounts, or developer.apple.com → Membership).
2. Replace `com.robertguss.speak` with your own prefix everywhere it appears:

   ```sh
   rg -l com.robertguss.speak | xargs sed -i '' 's/com\.robertguss\.speak/com.yourname.speak/g'
   ```

3. Follow the steps below.

## Generate the project

The Xcode project is generated and not checked in.

```sh
xcodegen generate
open Speak.xcodeproj
```

Run `xcodegen generate` again after you add or remove files or change `project.yml`.

## Signing

All targets use automatic signing with the team in `project.yml`. The bundle IDs are:

| Target | Bundle ID |
|---|---|
| Mac app | `com.robertguss.speak.mac` |
| iOS app | `com.robertguss.speak.ios` |
| Keyboard extension | `com.robertguss.speak.ios.keyboard` |

The apps share the keychain group `<TEAM>.com.robertguss.speak.shared`. The iOS app and its keyboard share the App Group `group.com.robertguss.speak`.

The first time, open the project in Xcode and build each scheme once with your account signed in (Xcode → Settings → Accounts). Xcode then registers the bundle IDs, the App Group, and the provisioning profiles. After that, command-line builds work:

```sh
xcodebuild -project Speak.xcodeproj -scheme SpeakMac -allowProvisioningUpdates build
```

## Run the tests

```sh
(cd Packages/DictationCore && swift test)
xcodebuild -project Speak.xcodeproj -scheme SpeakMac -destination 'platform=macOS' test
```

No test makes a live network call.

## Mac app

1. Run the `SpeakMac` scheme from Xcode. A microphone icon appears in the menu bar.
2. Follow the onboarding window to grant Microphone and Accessibility access.
3. If you choose Fn/Globe as the dictation key, set System Settings → Keyboard → "Press 🌐 key to" to **Do Nothing**.

Keep a stable signing identity. macOS ties the Accessibility grant to the code signature, so ad-hoc or changing signatures make you grant it again after every rebuild.

### Daily use: Developer ID build

For an app you keep in `/Applications`, export a Developer ID build:

1. In Xcode, choose Product → Archive with the `SpeakMac` scheme.
2. In the Organizer, choose Distribute App → Direct Distribution (Developer ID), and let Xcode create the Developer ID provisioning profile. The profile is required for the keychain access group.
3. Let Xcode notarize the app, then export it and move it to `/Applications`.
4. Grant Microphone and Accessibility access again for this copy.

## iPhone and iPad

1. Run the `SpeakiOS` scheme on the device.
2. Open Settings → General → Keyboard → Keyboards → Add New Keyboard, and choose **Speak**.
3. Tap **Speak** in that list and turn on **Allow Full Access**. The keyboard needs it to talk to the app and to open the app.
4. Open the Speak app and enter your provider and API key.
5. In any text field, switch to the Speak keyboard with the globe key and tap the mic. The first time, this opens the app to start a recording session. Swipe back to your app and tap the mic again to dictate.

The session keeps the microphone ready in the background, so the orange recording indicator stays on until the session ends after the idle timeout (5 minutes by default) or when you end it in the app.

## License

[MIT](LICENSE)
