//
//  TimeMachine.swift
//  TimeMachineEjector
//
//  Created by Wataru Nagasawa on 2021/10/12.
//

import Foundation
import os

enum TimeMachine {
    struct Destination: Decodable, Equatable {
        let id: String
        let name: String
        /// アンマウント中の宛先には MountPoint が無い。
        let mountPoint: String?
        let lastDestination: Int

        enum CodingKeys: String, CodingKey {
            case id = "ID"
            case name = "Name"
            case mountPoint = "MountPoint"
            case lastDestination = "LastDestination"
        }
    }

    struct Status: Equatable {
        let isRunning: Bool
        /// 0〜1 の割合。進捗が無いフェーズでは -1 になる。
        let percent: Double?

        var progress: Int? {
            guard let percent, (0...1).contains(percent) else {
                return nil
            }
            return Int((percent * 100).rounded(.down))
        }
    }

    /// Time Machine の自動バックアップの設定と、宛先に最後にバックアップした時刻。
    struct Schedule: Equatable {
        /// 頻度を変えていない（毎時）とき、設定に AutoBackupInterval が無い
        static let defaultInterval: TimeInterval = 3600

        let isAutomatic: Bool
        let interval: TimeInterval
        let lastBackupDate: Date?

        /// `lastAttempt` はこのアプリが前回バックアップを始めようとした時刻。
        /// マウントや開始に失敗しても、次の間隔までは繰り返さない。
        /// 最後のバックアップ時刻が分からないときは、設定を読めていない可能性があるので勝手に始めない。
        func isDue(at date: Date, lastAttempt: Date?) -> Bool {
            guard
                isAutomatic,
                let lastBackupDate
            else {
                return false
            }
            let base = max(lastBackupDate, lastAttempt ?? .distantPast)
            return base.addingTimeInterval(interval) <= date
        }
    }

    private struct DestinationList: Decodable {
        let destinations: [Destination]

        enum CodingKeys: String, CodingKey {
            case destinations = "Destinations"
        }
    }

    static func parseDestinations(_ data: Data) -> [Destination]? {
        try? PropertyListDecoder().decode(DestinationList.self, from: data).destinations
    }

    static func parseStatus(_ data: Data) -> Status? {
        try? PropertyListDecoder().decode(Status.self, from: data)
    }

    static func destinations() async -> [Destination]? {
        guard let result = await Command.tmutil("destinationinfo", "-X"), result.isSuccess else {
            return nil
        }
        return parseDestinations(result.output)
    }

    /// 宛先を複数登録しているときは、直近に使われたものを表示の対象にする。
    static func currentDestination() async -> Destination? {
        guard let destinations = await destinations() else {
            return nil
        }
        return destinations.first { $0.lastDestination == 1 } ?? destinations.first
    }

    static func status() async -> Status? {
        guard let result = await Command.tmutil("status", "-X"), result.isSuccess else {
            return nil
        }
        return parseStatus(result.output)
    }

    /// /Library/Preferences/com.apple.TimeMachine.plist はファイルとしては読めない（TCC）が、cfprefsd 経由なら一般ユーザーでも読める。
    /// SnapshotDates はディスクをアンマウントしていても残っている。
    static func schedule(for destinationID: String) -> Schedule {
        let defaults = UserDefaults(suiteName: "com.apple.TimeMachine")
        let interval = defaults?.double(forKey: "AutoBackupInterval") ?? 0
        let destination = (defaults?.array(forKey: "Destinations") as? [[String: Any]])?.first { $0["DestinationID"] as? String == destinationID }
        return Schedule(
            isAutomatic: defaults?.bool(forKey: "AutoBackup") ?? false,
            interval: interval > 0 ? interval : Schedule.defaultInterval,
            lastBackupDate: (destination?["SnapshotDates"] as? [Date])?.max()
        )
    }

    /// `isAutomatic` なら `--auto` で、システムのスケジュールのバックアップに近いモードで始める。
    /// その場合 backupd が状況（電源など）を見て始めないことがある。
    static func startBackup(isAutomatic: Bool) async {
        let result = isAutomatic ? await Command.tmutil("startbackup", "--auto") : await Command.tmutil("startbackup")
        guard let result, !result.isSuccess else { return }
        Logger.app.error("tmutil startbackup failed (\(result.exitStatus)): \(result.errorOutput, privacy: .public)")
    }
}

extension TimeMachine.Status: Decodable {
    private enum CodingKeys: String, CodingKey {
        case isRunning = "Running"
        case percent = "Percent"
        case progress = "Progress"
    }

    private enum ProgressKeys: String, CodingKey {
        case percent = "Percent"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isRunning = try container.decode(Bool.self, forKey: .isRunning)
        // コピー中の進み具合は Progress の中に入る。準備中などは最上位に -1 が入る
        let progress = try? container.nestedContainer(keyedBy: ProgressKeys.self, forKey: .progress)
        percent = try progress?.decodeIfPresent(Double.self, forKey: .percent) ?? container.decodeIfPresent(Double.self, forKey: .percent)
    }
}
