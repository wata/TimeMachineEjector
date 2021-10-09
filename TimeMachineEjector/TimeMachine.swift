//
//  TimeMachine.swift
//  TimeMachineEjector
//
//  Created by Wataru Nagasawa on 2021/10/12.
//

import Foundation

struct TimeMachine {
    struct Root: Decodable {
        let destinations: [Destination]

        enum CodingKeys: String, CodingKey {
            case destinations = "Destinations"
        }
    }

    struct Destination: Decodable {
        let id: String
        let name: String
        let kind: String
        let mountPoint: String
        let lastDestination: Int

        enum CodingKeys: String, CodingKey {
            case id = "ID"
            case name = "Name"
            case kind = "Kind"
            case mountPoint = "MountPoint"
            case lastDestination = "LastDestination"
        }
    }

    static func lastDestination() -> Destination? {
        destinations()?.first { $0.lastDestination == 1 }
    }

    static func destinations() -> [Destination]? {
        guard
            let output = tmutil(args: ["destinationinfo", "-X"]),
            let data = output.data(using: .utf8),
            let result = try? PropertyListDecoder().decode(Root.self, from: data)
        else { return nil }
        return result.destinations
    }
}

private func tmutil(args: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
    process.arguments = args
    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    do {
        try process.run()
    } catch let error {
        print(error.localizedDescription)
    }
    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    if let text = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
        return text
    } else {
        return nil
    }
}
