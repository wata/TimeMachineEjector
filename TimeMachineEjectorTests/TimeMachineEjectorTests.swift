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

    func testBackingUpStartsAtZeroPercent() {
        let starting = TimeMachine.Status(isRunning: true, percent: -1)
        let status = BackupDiskStatus(destination: destination, status: starting, volume: mounted, didFailToEject: false)
        XCTAssertEqual(status.title(destinationName: "Backup"), "Backup: Backing Up… 0%")
    }

    func testBackingUpKeepsLastProgressWithoutProgress() {
        let thinning = TimeMachine.Status(isRunning: true, percent: -1)
        let status = BackupDiskStatus(destination: destination, status: thinning, volume: mounted, didFailToEject: false, lastProgress: 100)
        XCTAssertEqual(status.title(destinationName: "Backup"), "Backup: Backing Up… 100%")
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

    func testSymbolShowsBackupInProgress() {
        let busy: [BackupDiskStatus] = [.startingBackup, .backingUp(progress: 0), .backingUp(progress: 100)]
        let others: [BackupDiskStatus] = [.noDestination, .connected, .ejected, .ejectFailed, .notConnected]
        for status in busy {
            XCTAssertEqual(status.symbolName, "externaldrive.fill.badge.timemachine", "\(status)")
        }
        for status in others {
            XCTAssertEqual(status.symbolName, "externaldrive.fill", "\(status)")
        }
    }

    func testLatestBackupTitle() {
        let locale = Locale(identifier: "en_US_POSIX")
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(BackupDiskStatus.latestBackupTitle(Date(timeIntervalSince1970: 1_000_000), locale: locale, timeZone: utc), "Latest Backup: Jan 12, 1970 at 1:46\u{202F}PM")
        XCTAssertTrue(BackupDiskStatus.latestBackupTitle(.now, locale: locale).hasPrefix("Latest Backup: Today"))
    }

    // MARK: - Schedule

    private let lastBackup = Date(timeIntervalSince1970: 1_000_000)

    func testScheduledBackupIsDueAfterInterval() {
        let schedule = TimeMachine.Schedule(isAutomatic: true, interval: 3600, lastBackupDate: lastBackup)
        XCTAssertFalse(schedule.isDue(at: lastBackup.addingTimeInterval(3599), lastAttempt: nil))
        XCTAssertTrue(schedule.isDue(at: lastBackup.addingTimeInterval(3600), lastAttempt: nil))
    }

    func testScheduledBackupFollowsInterval() {
        let daily = TimeMachine.Schedule(isAutomatic: true, interval: 86400, lastBackupDate: lastBackup)
        XCTAssertFalse(daily.isDue(at: lastBackup.addingTimeInterval(3600 * 23), lastAttempt: nil))
        XCTAssertTrue(daily.isDue(at: lastBackup.addingTimeInterval(86400), lastAttempt: nil))
    }

    func testScheduledBackupIsNotDueWhenAutomaticBackupsAreOff() {
        let schedule = TimeMachine.Schedule(isAutomatic: false, interval: 3600, lastBackupDate: lastBackup)
        XCTAssertFalse(schedule.isDue(at: lastBackup.addingTimeInterval(86400), lastAttempt: nil))
    }

    func testScheduledBackupIsNotDueWithoutLastBackup() {
        let schedule = TimeMachine.Schedule(isAutomatic: true, interval: 3600, lastBackupDate: nil)
        XCTAssertFalse(schedule.isDue(at: lastBackup, lastAttempt: nil))
    }

    func testScheduledBackupWaitsAnIntervalAfterLastAttempt() {
        let schedule = TimeMachine.Schedule(isAutomatic: true, interval: 3600, lastBackupDate: lastBackup)
        let attempt = lastBackup.addingTimeInterval(3600 * 5)
        XCTAssertFalse(schedule.isDue(at: attempt.addingTimeInterval(3599), lastAttempt: attempt))
        XCTAssertTrue(schedule.isDue(at: attempt.addingTimeInterval(3600), lastAttempt: attempt))
    }

    func testScheduledBackupIgnoresAttemptBeforeLastBackup() {
        let schedule = TimeMachine.Schedule(isAutomatic: true, interval: 3600, lastBackupDate: lastBackup)
        XCTAssertTrue(schedule.isDue(at: lastBackup.addingTimeInterval(3600), lastAttempt: lastBackup.addingTimeInterval(-60)))
    }

    private func plist(_ body: String) -> Data {
        Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>\(body)</dict></plist>
            """.utf8)
    }
}
