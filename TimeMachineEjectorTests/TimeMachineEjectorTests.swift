//
//  TimeMachineEjectorTests.swift
//  TimeMachineEjectorTests
//
//  Created by Wataru Nagasawa on 2021/10/04.
//

import XCTest
@testable import TimeMachineEjector

final class TimeMachineEjectorTests: XCTestCase {
    private let destination = TimeMachine.Destination(id: "11111111-2222-3333-4444-555555555555", name: "Backup", mountPoint: "/Volumes/Backup", lastDestination: 1)
    private let idle = TimeMachine.Status(isRunning: false, percent: -1)
    private let mounted = Disk.Info(parentWholeDisk: "disk7", volumeUUID: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", mountPoint: "/Volumes/Backup", physicalStores: nil)
    private let unmounted = Disk.Info(parentWholeDisk: "disk7", volumeUUID: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", mountPoint: "", physicalStores: nil)

    // MARK: - Parsing (macOS 27.0.1 の実出力から)

    func testParseIdleStatus() throws {
        let status = try XCTUnwrap(TimeMachine.parseStatus(plist("""
            <key>ClientID</key><string>com.apple.backupd</string>
            <key>Percent</key><real>-1</real>
            <key>Running</key><false/>
            """)))
        XCTAssertFalse(status.isRunning)
        XCTAssertNil(status.progress)
    }

    func testParseRunningStatus() throws {
        let status = try XCTUnwrap(TimeMachine.parseStatus(plist("""
            <key>BackupPhase</key><string>Copying</string>
            <key>DestinationMountPoint</key><string>/Volumes/Backup</string>
            <key>Percent</key><real>0.4987</real>
            <key>Running</key><true/>
            """)))
        XCTAssertTrue(status.isRunning)
        XCTAssertEqual(status.progress, 49)
    }

    func testParseCopyingStatusWithNestedProgress() throws {
        let status = try XCTUnwrap(TimeMachine.parseStatus(plist("""
            <key>BackupPhase</key><string>Copying</string>
            <key>DestinationMountPoint</key><string>/Volumes/Backup</string>
            <key>FractionOfProgressBar</key><real>0.9</real>
            <key>Progress</key>
            <dict>
                <key>Percent</key><real>0.17074666863682705</real>
                <key>TimeRemaining</key><real>281.47056357079657</real>
            </dict>
            <key>Running</key><true/>
            """)))
        XCTAssertTrue(status.isRunning)
        XCTAssertEqual(status.progress, 17)
    }

    func testParseDestinations() throws {
        let destinations = try XCTUnwrap(TimeMachine.parseDestinations(plist("""
            <key>Destinations</key>
            <array>
                <dict>
                    <key>Kind</key><string>Local</string>
                    <key>ID</key><string>11111111-2222-3333-4444-555555555555</string>
                    <key>Name</key><string>Backup</string>
                    <key>LastDestination</key><integer>1</integer>
                    <key>MountPoint</key><string>/Volumes/Backup</string>
                </dict>
                <dict>
                    <key>Kind</key><string>Local</string>
                    <key>ID</key><string>00000000-0000-0000-0000-000000000000</string>
                    <key>Name</key><string>Other</string>
                    <key>LastDestination</key><integer>0</integer>
                </dict>
            </array>
            """)))
        XCTAssertEqual(destinations.first, destination)
        XCTAssertNil(destinations.last?.mountPoint)
    }

    func testParseDiskInfo() throws {
        let info = try XCTUnwrap(Disk.parseInfo(plist("""
            <key>DeviceIdentifier</key><string>disk7s2</string>
            <key>ParentWholeDisk</key><string>disk7</string>
            <key>VolumeUUID</key><string>AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE</string>
            <key>MountPoint</key><string>/Volumes/Backup</string>
            <key>APFSPhysicalStores</key>
            <array><dict><key>APFSPhysicalStore</key><string>disk6s2</string></dict></array>
            """)))
        XCTAssertEqual(info.volumeUUID, "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        XCTAssertEqual(info.physicalStores?.first?.deviceIdentifier, "disk6s2")
        XCTAssertTrue(info.isMounted)
    }

    func testParseDiskInfoError() {
        XCTAssertNil(Disk.parseInfo(plist("""
            <key>Error</key><true/>
            <key>ErrorMessage</key><string>Could not find disk: 00000000-0000-0000-0000-000000000000</string>
            <key>ExitCode</key><integer>1</integer>
            """)))
    }

    // MARK: - Status

    func testNoDestination() {
        let status = BackupDiskStatus(destination: nil, status: idle, volume: mounted, didFailToEject: false)
        XCTAssertEqual(status, .noDestination)
        XCTAssertEqual(status.title(destinationName: nil), "No Backup Disk")
        XCTAssertFalse(status.canStartBackup)
    }

    func testBackingUp() {
        let running = TimeMachine.Status(isRunning: true, percent: 0.49)
        let status = BackupDiskStatus(destination: destination, status: running, volume: mounted, didFailToEject: false)
        XCTAssertEqual(status.title(destinationName: "Backup"), "Backup: Backing Up… 49%")
        XCTAssertFalse(status.canStartBackup)
    }

    func testBackingUpWithoutProgress() {
        let starting = TimeMachine.Status(isRunning: true, percent: -1)
        let status = BackupDiskStatus(destination: destination, status: starting, volume: mounted, didFailToEject: false)
        XCTAssertEqual(status.title(destinationName: "Backup"), "Backup: Backing Up…")
    }

    func testStartingBackupWhileStillEjected() {
        let status = BackupDiskStatus(destination: destination, status: idle, volume: unmounted, didFailToEject: false, isStartingBackup: true)
        XCTAssertEqual(status.title(destinationName: "Backup"), "Backup: Starting Backup…")
        XCTAssertFalse(status.canStartBackup)
    }

    func testConnected() {
        let status = BackupDiskStatus(destination: destination, status: idle, volume: mounted, didFailToEject: false)
        XCTAssertEqual(status.title(destinationName: "Backup"), "Backup: Connected")
        XCTAssertTrue(status.canStartBackup)
    }

    func testEjected() {
        let status = BackupDiskStatus(destination: destination, status: idle, volume: unmounted, didFailToEject: false)
        XCTAssertEqual(status.title(destinationName: "Backup"), "Backup: Ejected")
        XCTAssertTrue(status.canStartBackup)
    }

    func testEjectFailed() {
        let status = BackupDiskStatus(destination: destination, status: idle, volume: mounted, didFailToEject: true)
        XCTAssertEqual(status.title(destinationName: "Backup"), "Backup: Couldn't Eject")
        XCTAssertTrue(status.canStartBackup)
    }

    func testNotConnected() {
        let status = BackupDiskStatus(destination: destination, status: idle, volume: nil, didFailToEject: false)
        XCTAssertEqual(status.title(destinationName: "Backup"), "Backup: Not Connected")
        XCTAssertFalse(status.canStartBackup)
    }

    private func plist(_ body: String) -> Data {
        Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>\(body)</dict></plist>
            """.utf8)
    }
}
