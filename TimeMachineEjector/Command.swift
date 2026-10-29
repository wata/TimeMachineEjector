//
//  Command.swift
//  TimeMachineEjector
//

import Foundation
import os

struct CommandResult {
    let exitStatus: Int32
    let output: Data
    let errorOutput: String

    var isSuccess: Bool { exitStatus == 0 }
}

enum Command {
    static func tmutil(_ arguments: String...) async -> CommandResult? {
        await run("/usr/bin/tmutil", arguments)
    }

    static func diskutil(_ arguments: String...) async -> CommandResult? {
        await run("/usr/sbin/diskutil", arguments)
    }

    /// Process の終了待ちでメインスレッドを止めないよう、専用のキューで実行して結果だけを返す。
    private static func run(_ path: String, _ arguments: [String]) async -> CommandResult? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                do {
                    try process.run()
                } catch {
                    Logger.app.error("Failed to run \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                    return
                }
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let result = CommandResult(
                    exitStatus: process.terminationStatus,
                    output: outputData,
                    errorOutput: String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                )
                continuation.resume(returning: result)
            }
        }
    }
}

extension Logger {
    static let app = Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.wata.TimeMachineEjector", category: "app")
}
