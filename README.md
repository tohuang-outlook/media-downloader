# subtitle-burner

A pair of native macOS apps for bilingual subtitle generation and media downloading.

---

## Apps

| App | Description |
|-----|-------------|
| **SubtitleBurner** | Transcribe, translate, and burn Chinese + English subtitles into any video |
| **MediaDownloader** | Download YouTube and Instagram media via `yt-dlp` and `gallery-dl` |

---

## SubtitleBurner

### Screenshot

Dark purple two-column workspace UI. Settings panel on the left, live process log on the right.

### How it works

1. Converts source video to H.264 + AAC MP4
2. Extracts a 16kHz mono WAV directly from the original source
3. Runs **Whisper** with word-level timestamps (`--word_timestamps True`) to generate an accurate English `.srt`
4. Post-processes the SRT — splits multi-sentence cues at punctuation boundaries for better readability
5. Translates English → Traditional Chinese using your chosen AI provider
6. Generates a bilingual `.ass` file with two independent subtitle styles (Chinese above, English below)
7. Burns subtitles into the final video using **ffmpeg + libass**

### Build

```sh
./build.sh
```

### Launch

```sh
open SubtitleBurner.app
```

### Requirements

```sh
brew install ffmpeg
pip install openai-whisper
```

Verify:
```sh
ffmpeg -version
ffmpeg -filters | grep ass    # must show the ass filter
whisper --help
```

### Features

#### Dark workstation UI
Two-column layout — settings on the left, timestamped color-coded process log on the right. Matches a professional tool aesthetic (VS Code + Final Cut Pro style).

#### Bilingual subtitles
Chinese and English are rendered as two independent ASS subtitle tracks:
- **Chinese** — `Heiti SC`, ~2.6% of video height, positioned above English
- **English** — `Arial`, ~2.2% of video height, at the very bottom
- Small visual gap between the two lines for readability
- Horizontal margins scale with video width to prevent overflow on vertical (9:16) video

#### Subtitle size reference

| Resolution | Chinese | English |
|------------|---------|---------|
| 1920×1080 (horizontal) | ~50px | ~42px |
| 1080×1920 (vertical 9:16) | ~28px | ~24px |
| 1280×720 | ~19px | ~16px |

#### Sync offset
A **Sync Offset (seconds)** field lets you manually shift subtitles earlier or later:
- `-0.5` → shift subtitles 0.5s earlier
- `+1.0` → shift subtitles 1.0s later
- Default: `0.0`

#### Translation providers

| Provider | Default model |
|----------|--------------|
| OpenAI | `gpt-4.1-mini` |
| DeepSeek | `deepseek-chat` |
| Kimi 2.5 | `moonshot-v1-8k` |
| Google Gemini | `gemini-2.5-flash` |

#### API key storage
API keys are stored securely in the macOS **Keychain** — not in plain text. Switching providers automatically loads the saved key for that provider.

#### Batch processing
Drop multiple video files onto the window or use **Add Files…** to queue them. Click **Run Batch** to process all files sequentially. Each file shows its status (Queued / Running / Done / Failed / Cancelled).

#### Cancel
Click **Cancel** at any time to stop the current job or batch. The active ffmpeg/Whisper process is terminated immediately.

#### Settings persistence
All tool paths, whisper model, translate provider/model, output folder, and sync offset are saved via `UserDefaults` and restored on next launch.

### Workflow

**Full automated pipeline:**
1. Drop a video file onto the window (or use Add Files…)
2. Enter your API key and click **Save**
3. Set sync offset if needed (default 0.0)
4. Click **Run All**

**Step by step:**
1. **English SRT** → transcribes audio with Whisper
2. **Translate EN→ZH** → calls AI provider to generate Chinese SRT
3. **Merge ASS+Burn** → combines into `.ass` and burns into video

All output goes into `<output_folder>/<filename>_subtitle_work/`.

---

## MediaDownloader

### Screenshot

Dark workstation two-column UI. Settings and options on the left, terminal-style process log on the right.

### Build

```sh
./build_media_downloader.sh
```

### Verify SwiftPM build and tests

If SwiftPM hits a local `./.build/build.db` error in this workspace, use the bundled verifier, which builds and tests in a clean temporary build directory:

```sh
./verify_swiftpm.sh
```

### Launch

```sh
open MediaDownloader.app
```

### Requirements

```sh
brew install yt-dlp gallery-dl ffmpeg
```

### Features

#### Download modes

| Mode | Tool | Output |
|------|------|--------|
| YT Video | yt-dlp | `.mp4` |
| YT Audio | yt-dlp | `.mp3` |
| IG Video | gallery-dl | `.mp4` |
| IG Photo | gallery-dl | `.jpg` / `.png` |

#### Download size
Choose from **Best**, **1080p**, **720p**, **480p**, **360p** using pill selectors.

#### Convert MP4
Optionally re-encode the downloaded MP4 to a target resolution or custom width after download.

#### Instagram carousel
Use the **IG Indexes** field to select specific carousel items:

| Value | Behaviour |
|-------|-----------|
| `all` | Every matching item |
| `1` | First item only |
| `1,3,5` | Items 1, 3, 5 |
| `2-8` | Items 2 through 8 |

Click **List** to check how many items are in the carousel before downloading.

#### Browser cookies
Select **Safari**, **Chrome**, or **Firefox** to use your logged-in session for Instagram or age-restricted YouTube content.

#### URL history
The URL field remembers your last 20 URLs — click the dropdown to re-use a previous URL.

#### Tool Paths (collapsible)
Click **› TOOL PATHS** to expand and set custom paths for `yt-dlp`, `gallery-dl`, and `ffmpeg`. Paths are auto-detected from Homebrew on first launch.

#### Settings persistence
All settings (format, size, cookies, output folder, tool paths) are saved via `UserDefaults` and restored on next launch.

---

## Build a DMG installer

To package both apps into a distributable `.dmg`:

```sh
./build_all_dmg.sh
```

This produces `SubtitleBurner-Tools.dmg`.

### Reduce Gatekeeper friction

For the smoothest install experience on another Mac, use a Developer ID certificate plus notarization:

```sh
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="your-notarytool-profile"
./build_all_dmg.sh
```

Or use Apple ID credentials directly:

```sh
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_APPLE_ID="you@example.com"
export NOTARY_PASSWORD="app-specific-password"
export NOTARY_TEAM_ID="TEAMID"
./build_all_dmg.sh
```

Without Developer ID signing and notarization, the apps still work, but the first launch on another Mac will usually require right-click → Open.

---

## Project structure

```
subtitle-burner/
├── SubtitleBurnerApp.swift          # SubtitleBurner — all-in-one source
├── MediaDownloaderApp.swift         # MediaDownloader — all-in-one source
├── build.sh                         # Build SubtitleBurner.app
├── build_media_downloader.sh        # Build MediaDownloader.app
├── build_dmg.sh                     # Package MediaDownloader into DMG
├── SubtitleBurnerIcon-1024.png      # App icon source
├── MediaDownloaderIcon-1024.png     # App icon source
└── README.md
```

---

## Troubleshooting

**SwiftPM `./.build/build.db` disk I/O error**
```sh
./verify_swiftpm.sh
```
This project may hit a local SwiftPM database issue when using the default `./.build` directory. The verifier script uses `/private/tmp/media-downloader-swiftpm-build` instead.

**"Apple cannot check it for malicious software"**
```sh
xattr -cr SubtitleBurner.app
xattr -cr MediaDownloader.app
```

**ffmpeg missing `ass` filter**
```sh
brew reinstall ffmpeg
```

**Whisper not found**
```sh
pip install openai-whisper
which whisper   # copy this path into the app's whisper field
```

**Subtitles out of sync**
Use the **Sync Offset** field in SubtitleBurner. Try `-0.5` or `-1.0` if subtitles are consistently late.

**Instagram download fails**
Instagram requires browser cookies. Select Chrome/Safari/Firefox in the cookies dropdown (the browser where you are logged into Instagram).

---

## Legal

MediaDownloader is intended for content you own, have permission to download, or that the platform explicitly allows you to save. Respect copyright and platform terms of service.
