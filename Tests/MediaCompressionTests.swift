import Foundation

@main
struct MediaCompressionTests {
    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw NSError(domain: "Tests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func run(_ executable: String, _ arguments: [String]) throws -> MediaCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return MediaCommandResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let engine = MediaCompressionEngine(ffmpegPath: CommandLine.arguments[2], ffprobePath: CommandLine.arguments[3])
        let target = try MediaSize.targetBytes(text: "20", unit: .megabytes)!
        try require(target == 20_000_000, "20 MB must mean 20,000,000 bytes")
        try require(try MediaSize.targetBytes(text: "500", unit: .kilobytes) == 500_000, "KB must be decimal")
        try require(try MediaSize.targetBytes(text: "0.0019", unit: .kilobytes) == 1, "Fractional bytes must round down")
        try require(try MediaSize.targetBytes(text: "  ", unit: .megabytes) == nil, "Blank means unlimited")
        for text in ["0", "-1", "nan", "inf", "1e100", "9223372036854.776", "0.0000001", "abc"] {
            do {
                _ = try MediaSize.targetBytes(text: text, unit: .megabytes)
                throw NSError(domain: "Tests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Accepted invalid target: \(text)"])
            } catch MediaCompressionError.invalidTarget { }
        }
        try require(MediaSize.format(20_200_000) == "20.20 MB", "Display must match decimal target")

        let image = folder.appendingPathComponent("image.png")
        let jpeg = folder.appendingPathComponent("image.jpg")
        var qualities: [Int] = []
        let imageRunner: MediaCommandRunner = { executable, arguments in
            if executable == engine.ffprobePath {
                return MediaCommandResult(status: 0, output: "{\"streams\":[{\"width\":1600,\"height\":900}]}")
            }
            let quality = Int(arguments[arguments.firstIndex(of: "-q:v")! + 1])!
            qualities.append(quality)
            let bytes = quality == 2 ? 2500 : quality == 31 ? 400 : quality >= 19 ? 900 : 1100
            try Data(repeating: UInt8(quality), count: bytes).write(to: URL(fileURLWithPath: arguments.last!))
            return MediaCommandResult(status: 0, output: "")
        }
        let imageBytes = try engine.compress(inputURL: image, outputURL: jpeg, targetBytes: 1000, run: imageRunner)
        try require(imageBytes == 900 && (try Data(contentsOf: jpeg)).count == 900, "JPEG must contain the fitting candidate")
        try require(qualities.suffix(2) == [18, 19], "Exercise an oversized final search candidate")

        let video = folder.appendingPathComponent("video.mp4")
        let mp4 = folder.appendingPathComponent("retry.mp4")
        let videoProbe = "{\"streams\":[{\"codec_type\":\"video\",\"width\":1280,\"height\":720,\"r_frame_rate\":\"30/1\"},{\"codec_type\":\"audio\"}],\"format\":{\"duration\":\"30\"}}"
        var encodeCount = 0
        let retryRunner: MediaCommandRunner = { executable, arguments in
            if executable == engine.ffprobePath { return MediaCommandResult(status: 0, output: videoProbe) }
            encodeCount += 1
            let bytes = encodeCount == 1 ? 20_200_000 : 19_500_000
            try Data(repeating: 0, count: bytes).write(to: URL(fileURLWithPath: arguments.last!))
            return MediaCommandResult(status: 0, output: "")
        }
        try require(try engine.compress(inputURL: video, outputURL: mp4, targetBytes: target, run: retryRunner) == 19_500_000, "Oversized video must retry")
        try require(encodeCount == 2, "Oversized first encode must not be saved")
        let failureOutput = folder.appendingPathComponent("failure.mp4")
        let oversizedRunner: MediaCommandRunner = { executable, arguments in
            if executable == engine.ffprobePath { return MediaCommandResult(status: 0, output: videoProbe) }
            try Data(repeating: 0, count: 20_200_000).write(to: URL(fileURLWithPath: arguments.last!))
            return MediaCommandResult(status: 0, output: "")
        }
        do {
            _ = try engine.compress(inputURL: video, outputURL: failureOutput, targetBytes: target, run: oversizedRunner)
            throw NSError(domain: "Tests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Accepted oversized output"])
        } catch MediaCompressionError.outputTooLarge { }
        try require(!fm.fileExists(atPath: failureOutput.path), "Failure must leave no oversized output")
        try require(!(try fm.contentsOfDirectory(atPath: folder.path)).contains(where: { $0.hasPrefix(".XDownloader-") }), "Staging files must be removed")

        // Use real encoders to check file size, media integrity, duration, and audio retention.
        let realInput = folder.appendingPathComponent("real-source.mp4")
        let generated = try run(engine.ffmpegPath, ["-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=1280x720:rate=30,noise=alls=30:allf=t", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000", "-t", "20", "-c:v", "libx264", "-preset", "ultrafast", "-crf", "16", "-c:a", "aac", realInput.path])
        try require(generated.status == 0, generated.output)
        try require((try fm.attributesOfItem(atPath: realInput.path)[.size] as! NSNumber).int64Value > target, "Fixture must exceed 20 MB")
        for (label, bytes) in [("20mb", target), ("500kb", Int64(500_000))] {
            let output = folder.appendingPathComponent("real-\(label).mp4")
            let actual = try engine.compress(inputURL: realInput, outputURL: output, targetBytes: bytes, run: run)
            try require(actual <= bytes, "Real video exceeded \(label)")
            let decoded = try run(engine.ffmpegPath, ["-v", "error", "-i", output.path, "-f", "null", "-"])
            try require(decoded.status == 0 && decoded.output.isEmpty, "Output must decode cleanly")
            let probe = try run(engine.ffprobePath, ["-v", "error", "-show_entries", "stream=codec_type:format=duration", "-of", "json", output.path])
            let json = try JSONSerialization.jsonObject(with: Data(probe.output.utf8)) as! [String: Any]
            let streams = json["streams"] as! [[String: Any]]
            let duration = Double((json["format"] as! [String: Any])["duration"] as! String)!
            try require(streams.contains { ($0["codec_type"] as? String) == "audio" }, "Audio must be retained")
            try require(abs(duration - 20) < 0.2, "Video must not be truncated")
            print("PASS real video \(label): \(actual) bytes, \(duration)s, audio retained")
        }
        let generatedImage = try run(engine.ffmpegPath, ["-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=1600x900,noise=alls=30:allf=t", "-frames:v", "1", image.path])
        try require(generatedImage.status == 0, generatedImage.output)
        let realJPEG = folder.appendingPathComponent("real-image.jpg")
        let actualJPEG = try engine.compress(inputURL: image, outputURL: realJPEG, targetBytes: 100_000, run: run)
        try require(actualJPEG <= 100_000, "Real JPEG exceeded 100 KB")
        print("PASS real JPEG 100kb: \(actualJPEG) bytes")
        print("PASS decimal limits, rounding, invalid targets, JPEG search, video retries, and failure cleanup")
    }
}
