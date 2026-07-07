# Flowave — App Store Metadata (English / en-US)

Master copy of everything needed to publish Flowave on the App Store.
Character limits noted per field. Copy-paste into App Store Connect.

---

## App Name  (≤30)
```
Flowave: Focus & Sleep
```

## Subtitle  (≤30)
```
Binaural beats & focus timer
```

## Promotional Text  (≤170, editable without review)
```
Focus, relax, and sleep with binaural beats, generative music, and nature sounds — plus a Pomodoro timer that syncs your focus history across your devices via iCloud.
```

## Keywords  (≤100, comma separated, no spaces)
```
pomodoro,concentration,study,relax,whitenoise,rain,ambient,meditation,brainwave,calm,noise
```
> Words already in the Name/Subtitle (focus, sleep, binaural, beats, timer) are indexed automatically and intentionally omitted here.

## Description  (≤4000)
```
Flowave blends sound and focus into one calm, distraction-free space. Generate binaural beats, ambient soundscapes, and nature sounds entirely on your device, and pair them with a built-in Pomodoro timer to structure your work, study, and rest.

Everything is synthesized in real time — no downloads, no streaming, no account. Just open the app and press play.

SOUNDS THAT ADAPT TO YOU
• 30 binaural beat presets across five brainwave bands — Delta, Theta, Alpha, Beta, and Gamma — for deep rest, meditation, calm focus, active work, and peak concentration.
• 20 generative "modular synth" tracks in five moods: Ambient, Focus, Uplifting, Deep, and Dreamy.
• 7 natural ambiences — ocean, rain, forest, stream, campfire, wind, and white noise — each with its own volume.
• Layer anything together: mix a binaural beat with rain and a soft synth pad to build your perfect atmosphere.

A POMODORO TIMER BUILT FOR FLOW
• Simple mode for a single focus countdown, or Cycle mode to repeat work and break intervals.
• Fully adjustable focus time, break time, and number of sets.
• Your chosen sound plays automatically during focus and can pause on breaks.
• Phase changes are announced with local notifications, even in the background.

SEE YOUR PROGRESS
• Every completed focus session is saved to your history.
• A clean chart shows your daily focus time over the last 7 or 30 days, plus totals and averages.

SYNC ACROSS YOUR DEVICES
• Turn on iCloud to keep your focus history — and even a running session — in sync across iPhone, iPad, and Mac. Start on one device and pick up right where you left off on another.
• Prefer to keep everything local? Switch iCloud off in Settings and all data stays on this device only.

DESIGNED TO BE SIMPLE
• No sign-up, no ads, no tracking.
• Works fully offline.
• Available in English, Japanese, Simplified and Traditional Chinese, German, French, Italian, Spanish, and Portuguese.

Headphones or earbuds are recommended for binaural beats, since the effect comes from hearing a slightly different frequency in each ear.

Flowave is a relaxation, focus, and productivity tool. It is not a medical device and is not intended to diagnose, treat, cure, or prevent any condition. If you have a medical concern, please consult a qualified professional.
```

## What's New — v1.0  (≤4000)
```
Welcome to Flowave 1.0!
• 30 binaural beat presets, 20 generative synth tracks, and 7 natural ambiences you can freely mix.
• A built-in Pomodoro timer with focus history and daily charts.
• iCloud sync across your devices — or keep everything local.
• Available in 9 languages.
```

---

## App Store Connect settings

| Field | Value |
|---|---|
| Primary Category | Productivity |
| Secondary Category | Health & Fitness |
| Age Rating | 4+ |
| Copyright | © 2026 Tomohiro Hayashi |
| Bundle ID | com.tomohiro.flowave |
| Price | Free (adjustable) |
| Content Rights | Does not contain, show, or access third-party content |

## App Privacy (Nutrition Label)
- **Data Not Collected.**
- Pomodoro history is stored in the user's own iCloud (iCloud Key-Value Storage); the developer has no access.
- No account, no analytics, no ads, no tracking. Notifications are local only.
- Privacy Policy URL is required (see /docs/privacy.html).

## Export Compliance
- No non-exempt encryption used. Answer **No** to the encryption question
  (equivalent to `ITSAppUsesNonExemptEncryption = NO`).

## App Review — Notes
```
Flowave requires no account or login. All audio is generated on-device in real time; there are no downloads or streaming.

Binaural beats work best with headphones (a different frequency is played in each ear). Notifications are used only for local Pomodoro phase alerts. Pomodoro history optionally syncs via the user's own iCloud (key-value storage) and can be disabled in Settings; no data is collected by the developer.
```
- Demo account: not required.

---

## URLs (fill in after hosting — see /docs)
- Support URL:  https://burggarten.github.io/flowave/support.html
- Privacy Policy URL:  https://burggarten.github.io/flowave/privacy.html
- Marketing URL: (optional)

## Screenshots required
- iPhone 6.9" (e.g. 1320×2868) — required
- iPhone 6.5" (1242×2688) — recommended
- iPad 13" (e.g. 2064×2752) — required (app supports iPad)

Suggested shots & captions:
1. Sounds list + Now Playing — "Binaural beats, tuned to how you feel."
2. Ambience mixer — "Layer rain, forest, and more."
3. Pomodoro timer ring — "Focus in cycles that fit you."
4. History chart — "Watch your focus add up."
5. Settings (iCloud) — "Sync everywhere, or keep it private."

## Still needed
- App Icon 1024×1024 (generated — see Assets.xcassets/AppIcon.appiconset).
- Real hosting for Support/Privacy URLs (GitHub Pages from /docs).
- Contact email: tomohiro.hayashi@gmail.com

## Regenerating screenshots
The UI test `Binaural_beatsUITests/testCaptureAppStoreScreenshots` captures all five
screens in English. It relies on two launch arguments the app honors ONLY when present
(no effect in production):
- `-UITestSeed`  — seeds sample Pomodoro history so the chart is populated.
- `-UITestQuiet` — suppresses the notification-permission prompt.
Language is forced with `-AppleLanguages (en) -AppleLocale en_US`.

Run (boot the simulator first to avoid a cold-boot stall):
```
xcrun simctl boot "iPhone 17 Pro Max"    # or "iPad Pro 13-inch (M5)"
xcodebuild test -project "Binaural beats.xcodeproj" -scheme "Binaural beats" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:"Binaural beatsUITests/Binaural_beatsUITests/testCaptureAppStoreScreenshots" \
  -resultBundlePath /tmp/shots.xcresult
xcrun xcresulttool export attachments --path /tmp/shots.xcresult --output-path /tmp/shots
```
If the runner reports "Busy / preflight" or hangs, run `xcrun simctl erase <device>` and retry.
Current screenshots live in AppStore/screenshots/{iphone-6.9,ipad-13}/.
