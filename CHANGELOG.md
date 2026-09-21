# Changelog

All notable changes to this project are documented here.

## 1.3.0 — 2026-09-20

- Compact the default window and resize it when Logs are opened
- Replace mode and size popups with selectable segmented controls
- Default the size limit to 20 MB
- Move Logs beside the primary action and remove the Cancel button
- Keep the selected output folder across launches
- Add first-launch and menu-accessible Full Disk Access setup
- Package a drag-to-Applications DMG alongside the ZIP

## 1.2.0 — 2026-09-20

- Renamed the app to X Downloader
- Add Download + compress and Compress only modes
- Restore image attachment downloads through `gallery-dl`
- Add target-size image and video compression through FFmpeg
- Add file drag-and-drop and multi-file selection
- Add compact Activity disclosure for detailed logs
- Keep authenticated browser-cookie support in the app menu

## 1.1.0 — 2026-09-20

- Renamed the app to X Downloader
- Added authenticated browser-cookie support
- Accepted Reddit and removed-platform video URLs alongside X/Twitter URLs
- Continued through mixed batches and skipped posts without downloadable video
- Kept video downloads and audio merging through `yt-dlp` and FFmpeg

## 1.0.1 — 2026-09-20

- Replaced the app icon with a compact pixel-art design matching the Open Media Compressor icon family

## 1.0.0 — 2026-09-20

- Initial public release
- Parse multiple X/Twitter post links from pasted text
- Deduplicate links by post ID
- Download and merge the best available video using `yt-dlp` and FFmpeg
- Choose and remember a destination folder
- Native macOS paste shortcuts, cancellation, progress, and activity output
