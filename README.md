# X Video Downloader

A tiny native macOS app for downloading videos from public X/Twitter posts. Paste one or more post URLs, choose a folder, and download the best available video as MP4.

![macOS](https://img.shields.io/badge/macOS-13%2B-black)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

## Features

- Accepts `x.com` and `twitter.com` status URLs, including URLs mixed into other text
- Removes duplicate post IDs before downloading
- Downloads the best available video and audio streams
- Merges streams into MP4 when needed
- Never overwrites an existing file
- Runs locally with no X API key and no paid service

## Install

1. Install the two runtime dependencies:

   ```bash
   brew install yt-dlp ffmpeg
   ```

2. Download the latest ZIP from [Releases](../../releases/latest), unzip it, and open **X Video Downloader.app**.

The downloadable release is ad-hoc signed rather than notarized. On first launch, macOS may require you to right-click the app and choose **Open**.

## Build from source

Requires macOS 13 or newer and Xcode Command Line Tools.

```bash
git clone https://github.com/nickdrezza/x-video-downloader.git
cd x-video-downloader
./scripts/build.sh
open ".build/X Video Downloader.app"
```

The build script compiles for the current Mac architecture, generates the `.icns` file, assembles the app bundle, and ad-hoc signs it. To create a distributable ZIP:

```bash
./scripts/package.sh
```

## How it works

The UI is a small AppKit application written in Swift. It extracts post IDs from pasted text and invokes [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) locally. FFmpeg merges separate video and audio streams when the source requires it.

No credentials or X API access are required for public posts. Deleted, protected, age-restricted, region-restricted, or login-only posts may not download.

## Responsible use

Only download videos you have permission to save. You are responsible for complying with copyright law, the source platform's terms, and any applicable local rules.

## License

[MIT](LICENSE)
