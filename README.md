# X Downloader

A tiny native macOS app for downloading and compressing media from X/Twitter, Reddit, and removed-platform. Paste links or choose local files, set an optional target size, and keep the processing local.

![macOS](https://img.shields.io/badge/macOS-13%2B-black)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

## Features

- Download + compress mode for X/Twitter, Reddit, `redd.it`, and removed-platform links
- Image attachments are downloaded with `gallery-dl`; video attachments are downloaded with `yt-dlp`
- Compress-only mode for multiple local image and video files
- Optional max-size target in MB or KB; empty means no size limit and preserves the downloaded/input file
- JPEG image output with quality search, resizing, and white flattening for transparency
- H.264/AAC MP4 video output with bitrate planning, resizing, frame-rate normalization, and retries
- Removes media metadata and chapters from compressed video output
- Drag-and-drop or multi-file selection for local compression
- Extracts supported URLs mixed into other text and removes duplicates
- Uses cookies from the selected browser instead of anonymous requests
- Never overwrites an existing file
- Runs locally with no API key and no paid service

## Install

1. Install the two runtime dependencies:

   ```bash
   brew install yt-dlp gallery-dl ffmpeg
   ```

2. Log into the supported site in Safari, Chrome, Firefox, Edge, Brave, Chromium, Opera, or Vivaldi. The browser-cookie choice is in the **X Downloader → Browser Cookies** menu.
3. Download the latest ZIP from [Releases](../../releases/latest), unzip it, and open **X Downloader.app**.

The downloadable release is ad-hoc signed rather than notarized. On first launch, macOS may require you to right-click the app and choose **Open**.

## Build from source

Requires macOS 13 or newer and Xcode Command Line Tools.

```bash
git clone https://github.com/nickdrezza/x-video-downloader.git
cd x-video-downloader
./scripts/build.sh
open ".build/X Downloader.app"
```

The build script compiles for the current Mac architecture, generates the `.icns` file, assembles the app bundle, and ad-hoc signs it. To create a distributable ZIP:

```bash
./scripts/package.sh
```

## How it works

The UI is a small AppKit application written in Swift. Download mode runs `gallery-dl` for image attachments and `yt-dlp` for video attachments, both with `--cookies-from-browser` for the selected browser. FFmpeg merges separate video and audio streams when the source requires it, then applies the local compression layer when a max size is set.

Compress-only mode uses the installed FFmpeg executable and follows the same target-size behavior as the companion Open Media Compressor: quality search first, then dimension reduction when quality alone cannot meet the target. The app does not store credentials or cookies; the download tools read the selected browser's local cookie store when a download starts. The account must already be allowed to view the media. Deleted, protected, age-restricted, region-restricted, or login-only posts may still fail.

## Responsible use

Only download videos you have permission to save. You are responsible for complying with copyright law, the source platform's terms, and any applicable local rules.

## License

[MIT](LICENSE)
