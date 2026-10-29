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
            guard let percent, (0...1).contains(percent) else { return nil }
            return Int((percent * 100).rounded(.down))
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
        guard let result = await Command.tmutil("destinationinfo", "-X"), result.isSuccess else { return nil }
        return parseDestinations(result.output)
    }

    /// 宛先を複数登録しているときは、直近に使われたものを表示の対象にする。
    static func currentDestination() async -> Destination? {
        guard let destinations = await destinations() else { return nil }
        return destinations.first { $0.lastDestination == 1 } ?? destinations.first
    }

    static func status() async -> Status? {
        guard let result = await Command.tmutil("status", "-X"), result.isSuccess else { return nil }
        return parseStatus(result.output)
    }

    static func startBackup() async {
        guard let result = await Command.tmutil("startbackup"), !result.isSuccess else { return }
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
