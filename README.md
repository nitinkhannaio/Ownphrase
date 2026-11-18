# Ownphrase

Ownphrase is a personal English writing agent for iPhone. Its primary input is a system-wide custom keyboard. The companion app holds your writing notebook, daily lessons, and settings.

## How it learns

- Ordinary typing updates on-device counts of writing traits, common word choices, and a small set of English patterns. The keyboard observes passages authored through its keys. Unaccepted ordinary passages are transient.
- When Apple’s on-device language model is available, it can also classify a passage by register and communication style. Only bounded labels and deduplicated evidence enter this memory. Context is an estimate. Ambiguous passages use a general register.
- Rewrite previews the text and offers My voice, Friendly, Professional, Casual, Fix grammar, and Shorter. Tapping a preset sends the preview, the preset instruction, and a bounded voice summary to OpenAI. A missing key routes directly to setup on supported hosts. Choosing an option saves the original and the accepted rewrite in the notebook. The next request uses the updated voice profile. Select the original to replace it, or copy a rewrite to paste yourself. Copying alone does not add it to the notebook.
- Today groups correction examples and highlights recurring word choices. A local reminder can show a lesson topic at the time you choose when that day's writing provides evidence before the reminder hour.

## Run on your iPhone

1. Open `Ownphrase.xcodeproj` with Xcode 26.2 or later. The app targets iPhone on iOS 26.0 and later.
2. Choose your signing team for both Ownphrase and OwnphraseKeyboard. Provision matching bundle identifiers and an App Group for both targets. For a fork, substitute your own available IDs everywhere in `project.yml`, `BuildSupport/Ownphrase.entitlements`, `Shared/Local/OwnStore.swift` and `Shared/Model/APIKeyStore.swift`, then regenerate the project with `xcodegen generate`.
3. Run the Ownphrase scheme on your iPhone. In iPhone Settings → General → Keyboard → Keyboards, add Ownphrase, enable Allow Full Access, and choose it as your keyboard. iOS handles secure text fields, certain phone fields, and apps that disable extensions.
4. Enter your OpenAI API key in Ownphrase → Settings. Ordinary typing and aggregate learning work without an API key. Use the practice editor to try it before writing in other apps.

## Data and processing

The shared SQLite directory uses iOS file protection and is excluded from backup. The OpenAI key lives in the shared device-only Keychain. There is no project-operated server, analytics SDK, backup, or sync service. Erasing the notebook clears examples and learned memory. Key removal and pausing everyday learning are separate settings.

OpenAI processing uses the Responses API with `store: false`. OpenAI's own service-side data handling depends on your API account and [OpenAI data controls](https://developers.openai.com/api/docs/guides/your-data).

## Build and test

The generated Xcode project is checked in. Run the Ownphrase scheme's tests with Command-U on an iOS 26 simulator. Regenerate the project after changing source membership or target settings. Tests exercise persistence, privacy boundaries, selection safety, and request construction without a real API key.

The keyboard implements tap typing, capitalization, suggestions, autocorrection, repeat delete, cursor dragging, numbers, punctuation and common emoji. Swipe-to-type and personal-device typing-feel validation remain open. On-device semantic inference needs compatible hardware and an available system model. Live rewrite quality and notification delivery should be evaluated with a signed build on a real iPhone.

MIT licensed.

## Keyboard comparison

Open [the interactive comparison](docs/keyboard/comparison.html) locally to view Apple and Ownphrase in the same editor, inspect amplified pixel differences, and look up each key's rectangle. The comparison covers iOS 26.2 on an iPhone 17 Pro simulator. Each of the 190 visible key rectangles across the six captures matches its reference rectangle at 3× resolution. The same key can appear in several captures.

Letterforms, icons, next-word suggestions, and the rewrite control differ in the image comparison. Ownphrase uses the public system font and a local prediction implementation. The measured layouts cover letters in portrait and landscape, numbers, symbols, mid-word lowercase letters, and dark portrait. Other field types, hardware sizes, touch timing, and prediction quality need separate validation.
