import Foundation

enum MediaKind {
    case image
    case video
    case unsupported
}

struct MediaCommandResult {
    let status: Int32
    let output: String
}

typealias MediaCommandRunner = (_ executable: String, _ arguments: [String]) throws -> MediaCommandResult

enum MediaCompressionError: LocalizedError {
    case unsupportedFile(String)
    case invalidTarget
    case invalidMedia(String)
    case targetTooSmall(String)
    case outputTooLarge(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile(let name):
            return "Format not supported for \"\(name)\". Choose a photo or video."
        case .invalidTarget:
            return "Max size must be a positive number."
        case .invalidMedia(let message), .targetTooSmall(let message), .outputTooLarge(let message), .commandFailed(let message):
            return message
        }
    }
}

struct MediaCompressionEngine {
    let ffmpegPath: String
    let ffprobePath: String

    private let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "webm", "mkv", "avi", "wmv", "flv", "mpeg", "mpg", "ts", "mts", "m2ts", "3gp", "ogv", "vob"
    ]
    private let imageExtensions: Set<String> = [
        "jpg", "jpeg", "jfif", "png", "apng", "webp", "gif", "bmp", "tif", "tiff", "avif", "heic", "heif", "svg"
    ]

    func kind(for url: URL) -> MediaKind {
        let extensionName = url.pathExtension.lowercased()
        if videoExtensions.contains(extensionName) { return .video }
        if imageExtensions.contains(extensionName) { return .image }
        return .unsupported
    }

    func compress(
        inputURL: URL,
        outputURL: URL,
        targetBytes: Int64,
        run: MediaCommandRunner
    ) throws -> Int64 {
        guard targetBytes > 0 else { throw MediaCompressionError.invalidTarget }

        switch kind(for: inputURL) {
        case .image:
            return try compressImage(inputURL: inputURL, outputURL: outputURL, targetBytes: targetBytes, run: run)
        case .video:
            return try compressVideo(inputURL: inputURL, outputURL: outputURL, targetBytes: targetBytes, run: run)
        case .unsupported:
            throw MediaCompressionError.unsupportedFile(inputURL.lastPathComponent)
        }
    }

    private func compressImage(
        inputURL: URL,
        outputURL: URL,
        targetBytes: Int64,
        run: MediaCommandRunner
    ) throws -> Int64 {
        let dimensions = try probeDimensions(inputURL: inputURL, run: run)
        var width = dimensions.width
        var height = dimensions.height

        for _ in 0..<10 {
            let maximum = try encodeImage(
                inputURL: inputURL,
                outputURL: outputURL,
                width: width,
                height: height,
                quality: 2,
                run: run
            )
            if maximum <= targetBytes { return maximum }

            let minimum = try encodeImage(
                inputURL: inputURL,
                outputURL: outputURL,
                width: width,
                height: height,
                quality: 31,
                run: run
            )
            if minimum <= targetBytes {
                var best = minimum
                var low = 3
                var high = 30
                for _ in 0..<9 where low <= high {
                    let quality = (low + high) / 2
                    let candidate = try encodeImage(
                        inputURL: inputURL,
                        outputURL: outputURL,
                        width: width,
                        height: height,
                        quality: quality,
                        run: run
                    )
                    if candidate <= targetBytes {
                        best = candidate
                        high = quality - 1
                    } else {
                        low = quality + 1
                    }
                }
                return best
            }

            let ratio = sqrt(Double(targetBytes) / Double(max(minimum, 1)))
            let scale = min(0.9, max(0.35, ratio * 0.94))
            let nextWidth = max(1, Int(Double(width) * scale))
            let nextHeight = max(1, Int(Double(height) * scale))
            if nextWidth == width && nextHeight == height { break }
            width = nextWidth
            height = nextHeight
        }

        throw MediaCompressionError.outputTooLarge("Could not compress \(inputURL.lastPathComponent) below the requested size.")
    }

    private func encodeImage(
        inputURL: URL,
        outputURL: URL,
        width: Int,
        height: Int,
        quality: Int,
        run: MediaCommandRunner
    ) throws -> Int64 {
        let filter = "format=rgba,scale=\(width):\(height):force_original_aspect_ratio=decrease:flags=lanczos,pad=\(width):\(height):(ow-iw)/2:(oh-ih)/2:color=white,format=yuvj420p"
        let result = try run(ffmpegPath, [
            "-hide_banner", "-loglevel", "error", "-y",
            "-i", inputURL.path,
            "-frames:v", "1", "-an", "-map_metadata", "-1",
            "-vf", filter,
            "-c:v", "mjpeg", "-q:v", String(quality), "-f", "image2",
            outputURL.path
        ])
        guard result.status == 0 else {
            throw MediaCompressionError.commandFailed("FFmpeg could not encode \(inputURL.lastPathComponent) as JPEG.\n\(result.output)")
        }
        let bytes = try fileSize(outputURL)
        guard bytes > 0 else {
            throw MediaCompressionError.invalidMedia("FFmpeg produced an empty JPEG for \(inputURL.lastPathComponent).")
        }
        return bytes
    }

    private func compressVideo(
        inputURL: URL,
        outputURL: URL,
        targetBytes: Int64,
        run: MediaCommandRunner
    ) throws -> Int64 {
        let probe = try probeVideo(inputURL: inputURL, run: run)
        var plan = try buildVideoPlan(probe: probe, targetBytes: targetBytes)

        for _ in 0..<3 {
            let result = try run(ffmpegPath, buildVideoArguments(inputURL: inputURL, outputURL: outputURL, plan: plan))
            guard result.status == 0 else {
                throw MediaCompressionError.commandFailed("FFmpeg could not encode \(inputURL.lastPathComponent) as MP4.\n\(result.output)")
            }

            let outputBytes = try fileSize(outputURL)
            if outputBytes <= targetBytes { return outputBytes }

            let tightenedVideoBitrate = max(60_000, Int(Double(plan.videoBitrate) * (Double(targetBytes) / Double(outputBytes)) * 0.94))
            guard tightenedVideoBitrate < plan.videoBitrate else { break }
            plan.videoBitrate = tightenedVideoBitrate
        }

        throw MediaCompressionError.outputTooLarge("Could not compress \(inputURL.lastPathComponent) below the requested size.")
    }

    private func buildVideoPlan(probe: VideoProbe, targetBytes: Int64) throws -> VideoPlan {
        guard probe.duration > 0, targetBytes > 0 else {
            throw MediaCompressionError.invalidMedia("Could not read the duration of the video.")
        }

        let totalBitrate = Int(Double(targetBytes * 8) * 0.965 / probe.duration)
        let audioBitrate: Int
        if probe.hasAudio {
            audioBitrate = totalBitrate >= 900_000 ? 128_000 : totalBitrate >= 450_000 ? 96_000 : 64_000
        } else {
            audioBitrate = 0
        }
        let minimumBitrate = 60_000 + (probe.hasAudio ? 64_000 : 0)
        guard totalBitrate >= minimumBitrate else {
            throw MediaCompressionError.targetTooSmall(
                "The requested size is too small for this video duration. Try a larger target."
            )
        }

        let videoBitrate = max(60_000, totalBitrate - audioBitrate)
        let frameRate = min(30, normalizeFrameRate(probe.frameRate))
        let bitsPerPixel = Double(videoBitrate) / Double(max(1, probe.width * probe.height)) / frameRate
        let maxHeight: Int
        if bitsPerPixel < 0.025 || videoBitrate < 450_000 {
            maxHeight = min(probe.height, 360)
        } else if bitsPerPixel < 0.045 || videoBitrate < 900_000 {
            maxHeight = min(probe.height, 480)
        } else if bitsPerPixel < 0.075 || videoBitrate < 2_000_000 {
            maxHeight = min(probe.height, 720)
        } else {
            maxHeight = min(probe.height, 1080)
        }
        return VideoPlan(
            videoBitrate: videoBitrate,
            audioBitrate: audioBitrate,
            maxHeight: maxHeight,
            frameRate: frameRate,
            hasAudio: probe.hasAudio
        )
    }

    private func buildVideoArguments(inputURL: URL, outputURL: URL, plan: VideoPlan) -> [String] {
        let frameRate = decimal(plan.frameRate)
        let videoFilter = "fps=\(frameRate),scale=-2:min(\(plan.maxHeight)\\,ih):flags=lanczos"
        var arguments = [
            "-hide_banner", "-loglevel", "error", "-y",
            "-i", inputURL.path,
            "-map", "0:v:0"
        ]
        if plan.hasAudio {
            arguments += ["-map", "0:a:0"]
        } else {
            arguments += ["-an"]
        }
        arguments += [
            "-map_metadata", "-1", "-map_chapters", "-1",
            "-vf", videoFilter,
            "-c:v", "libx264", "-preset", "veryfast", "-profile:v", "high", "-level", "4.1", "-pix_fmt", "yuv420p",
            "-b:v", String(plan.videoBitrate), "-maxrate", String(Int(Double(plan.videoBitrate) * 1.25)),
            "-bufsize", String(plan.videoBitrate * 2)
        ]
        if plan.hasAudio {
            arguments += [
                "-c:a", "aac", "-b:a", String(plan.audioBitrate), "-ac", "2", "-ar", "48000",
                "-af", "aresample=async=1:first_pts=0"
            ]
        }
        arguments += ["-movflags", "+faststart", outputURL.path]
        return arguments
    }

    private func probeDimensions(inputURL: URL, run: MediaCommandRunner) throws -> (width: Int, height: Int) {
        let result = try run(ffprobePath, [
            "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=width,height",
            "-of", "json", inputURL.path
        ])
        guard result.status == 0,
              let json = try? JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any],
              let streams = json["streams"] as? [[String: Any]],
              let stream = streams.first,
              let width = stream["width"] as? Int,
              let height = stream["height"] as? Int,
              width > 0, height > 0 else {
            throw MediaCompressionError.invalidMedia("Could not read the dimensions of \(inputURL.lastPathComponent).")
        }
        return (width, height)
    }

    private func probeVideo(inputURL: URL, run: MediaCommandRunner) throws -> VideoProbe {
        let result = try run(ffprobePath, [
            "-v", "error",
            "-show_entries", "stream=codec_type,width,height,r_frame_rate:format=duration",
            "-of", "json", inputURL.path
        ])
        guard result.status == 0,
              let json = try? JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any],
              let streams = json["streams"] as? [[String: Any]],
              let video = streams.first(where: { ($0["codec_type"] as? String) == "video" }),
              let width = video["width"] as? Int,
              let height = video["height"] as? Int,
              let rateText = video["r_frame_rate"] as? String else {
            throw MediaCompressionError.invalidMedia("Could not read the video metadata for \(inputURL.lastPathComponent).")
        }

        let duration: Double
        if let format = json["format"] as? [String: Any], let value = format["duration"] as? String, let parsed = Double(value) {
            duration = parsed
        } else if let format = json["format"] as? [String: Any], let parsed = format["duration"] as? Double {
            duration = parsed
        } else {
            throw MediaCompressionError.invalidMedia("Could not read the duration of \(inputURL.lastPathComponent).")
        }

        let rateParts = rateText.split(separator: "/").compactMap { Double($0) }
        let frameRate = rateParts.count == 2 && rateParts[1] > 0 ? rateParts[0] / rateParts[1] : rateParts.first ?? 30
        return VideoProbe(
            duration: duration,
            width: width,
            height: height,
            frameRate: frameRate,
            hasAudio: streams.contains { ($0["codec_type"] as? String) == "audio" }
        )
    }

    private func fileSize(_ url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let number = attributes[.size] as? NSNumber, number.int64Value > 0 else {
            throw MediaCompressionError.invalidMedia("The output file is empty.")
        }
        return number.int64Value
    }

    private func normalizeFrameRate(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 30 }
        let supported = [23.976, 24.0, 25.0, 29.97, 30.0]
        if let closest = supported.min(by: { abs($0 - value) < abs($1 - value) }), abs(closest - value) <= 0.04 {
            return closest
        }
        return min(30, value)
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

private struct VideoProbe {
    let duration: Double
    let width: Int
    let height: Int
    let frameRate: Double
    let hasAudio: Bool
}

private struct VideoPlan {
    var videoBitrate: Int
    let audioBitrate: Int
    let maxHeight: Int
    let frameRate: Double
    let hasAudio: Bool
}
