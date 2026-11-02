//
//  AppDelegate.swift
//  TimeMachineEjector
//
//  Created by Wataru Nagasawa on 2021/10/04.
//

import Cocoa
import os
import Sparkle

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // backupd が始めなかったときに「Starting Backup…」のまま残らないよう、この時間で諦める
    private static let backupStartTimeout: TimeInterval = 60
    // メニューを開いたままでも進捗が止まって見えないよう、開いている間はこの間隔で読み直す
    private static let menuRefreshInterval: Duration = .seconds(1)
    // 予定の時刻を数分過ぎても構わないので、diskutil や tmutil を頻繁に叩かない間隔にする
    private static let scheduleCheckInterval: Duration = .seconds(5 * 60)
    // メニューを閉じていても、バックアップが終わったらアイコンを取り出しに戻せるよう、その間だけこの間隔で読み直す
    private static let backupRefreshInterval: Duration = .seconds(15)

    private let backupMonitor = BackupMonitor()
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    private lazy var statusItem: NSStatusItem = {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = makeStatusImage()
        return statusItem
    }()
    private lazy var diskItem = makeMenuItem(title: diskStatus.title(destinationName: nil), selector: nil)
    private lazy var latestBackupItem: NSMenuItem = {
        let item = makeMenuItem(title: "", selector: nil)
        item.isHidden = true
        return item
    }()
    private var destination: TimeMachine.Destination?
    private var diskStatus = BackupDiskStatus.noDestination
    private var didFailToEject = false
    // Back Up Now かスケジュールでバックアップを始めた時刻。backupd が Running になるまでの数秒、Ejected などのままに見えないよう「Starting Backup…」を出す
    private var backupRequestDate: Date?
    private var menuRefreshTask: Task<Void, Never>?
    private var backupRefreshTask: Task<Void, Never>?
    // スケジュールでバックアップを始めようとした時刻。マウントや開始に失敗しても次の間隔まで繰り返さない
    private var scheduledBackupAttemptDate: Date?
    private var scheduleTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupMenu()
        start()
    }

    private func start() {
        Task { [weak self] in
            guard let self else { return }
            await refresh()
        }

        guard !Settings.isDisabled else { return }

        backupMonitor.start { [weak self] path in
            guard let self else { return }
            await eject(path)
        }
        startSchedule()
    }

    private func stop() {
        backupMonitor.stop()
        stopSchedule()
    }

    private func startSchedule() {
        stopSchedule()
        // ユニットテストはこのアプリをホストにして起動するので、テストのたびに実機のディスクをマウントしてバックアップを始めないようにする
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        scheduleTask = Task { [weak self] in
            var trigger = "launch"
            while !Task.isCancelled {
                guard let self else { return }
                await startScheduledBackupIfDue(trigger: trigger)
                try? await Task.sleep(for: Self.scheduleCheckInterval)
                trigger = "timer"
            }
        }
        // スリープ中に予定の時刻を過ぎていることが多いので、次の確認を待たずに見る
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { [weak self] in
                guard let self else { return }
                await startScheduledBackupIfDue(trigger: "wake")
            }
        }
    }

    private func stopSchedule() {
        scheduleTask?.cancel()
        scheduleTask = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? ""
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        menu.addItem(makeMenuItem(title: "Disable", selector: #selector(AppDelegate.toggleDisable(_:)), isOn: Settings.isDisabled))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "Back Up Now", selector: #selector(AppDelegate.backUpNow(_:))))
        // 無効になった Back Up Now と灰色の状態表示が見分けにくいので、状態表示を Back Up Now の説明として字下げして下に並べる
        diskItem.indentationLevel = 2
        latestBackupItem.indentationLevel = 2
        menu.addItem(diskItem)
        menu.addItem(latestBackupItem)
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "Launch at Login", selector: #selector(AppDelegate.toggleLaunchAtLogin(_:)), isOn: Settings.isLaunchAtLoginEnabled))
        menu.addItem(makeMenuItem(title: "Check for Updates…", selector: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), target: updaterController))
        menu.addItem(makeMenuItem(title: "About \(name) \(version)", selector: #selector(AppDelegate.openGitHub(_:))))
        menu.addItem(makeMenuItem(title: "Quit \(name)", selector: #selector(AppDelegate.quit(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func makeMenuItem(title: String, selector: Selector?, target: AnyObject? = nil, isOn: Bool? = nil, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: keyEquivalent)
        item.target = target
        if let isOn {
            item.state = isOn ? .on : .off
        }
        return item
    }

    private func refresh() async {
        let destination = await TimeMachine.currentDestination()
        let status = await TimeMachine.status()
        let volume = await volume(of: destination)
        // マウントされていなければ失敗はもう解消している（手動で取り出した、抜いた等）
        if volume?.isMounted != true {
            didFailToEject = false
        }
        if status?.isRunning == true {
            backupRequestDate = nil
        }
        let isStartingBackup = backupRequestDate.map { Date.now.timeIntervalSince($0) < Self.backupStartTimeout } ?? false
        self.destination = destination
        diskStatus = BackupDiskStatus(destination: destination, status: status, volume: volume, didFailToEject: didFailToEject, isStartingBackup: isStartingBackup, lastProgress: diskStatus.progress)
        diskItem.title = diskStatus.title(destinationName: destination?.name)
        let latestBackupDate = destination.flatMap { TimeMachine.schedule(for: $0.id).lastBackupDate }
        latestBackupItem.title = latestBackupDate.map { BackupDiskStatus.latestBackupTitle($0) } ?? ""
        latestBackupItem.isHidden = latestBackupDate == nil
        statusItem.button?.image = makeStatusImage()
        refreshUntilBackupFinishes()
        // 開いているメニューの Back Up Now の有効/無効を、更新後の状態で検証し直す
        statusItem.menu?.update()
    }

    /// SF Symbols はメニューバーの標準の大きさで描かれ、ライト/ダークにも追従する
    private func makeStatusImage() -> NSImage? {
        NSImage(systemSymbolName: diskStatus.symbolName, accessibilityDescription: "TimeMachineEjector: \(diskStatus.title(destinationName: destination?.name))")
    }

    /// 普段はメニューを開いたときやスケジュールの確認でしか読み直さないので、
    /// バックアップ中だけはメニューを閉じていても読み直し、終わったらアイコンを戻す。
    private func refreshUntilBackupFinishes() {
        guard diskStatus.isBackupInProgress, backupRefreshTask == nil else { return }
        backupRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.backupRefreshInterval)
                guard let self else { return }
                await refresh()
                guard diskStatus.isBackupInProgress else { break }
            }
            self?.backupRefreshTask = nil
        }
    }

    private func volume(of destination: TimeMachine.Destination?) async -> Disk.Info? {
        guard let destination else {
            return nil
        }
        if let mountPoint = destination.mountPoint, let info = await Disk.info(for: mountPoint) {
            if let uuid = info.volumeUUID, Settings.volumeUUIDs[destination.id] != uuid {
                Settings.volumeUUIDs[destination.id] = uuid
            }
            return info
        }
        guard let uuid = Settings.volumeUUIDs[destination.id] else {
            return nil
        }
        return await Disk.info(for: uuid)
    }

    private func eject(_ path: String) async {
        guard !Settings.isDisabled else { return }
        // アンマウントすると UUID が取れなくなるので、先に宛先の UUID を覚えさせておく
        await refresh()
        guard let volume = await Disk.info(for: path), volume.isMounted else {
            Logger.app.notice("\(path, privacy: .public) is already unmounted")
            return
        }
        let wholeDisk = await Disk.physicalWholeDisk(of: volume)
        let isEjected = await Disk.unmountDisk(wholeDisk)
        didFailToEject = !isEjected
        if isEjected {
            Logger.app.notice("Ejected \(wholeDisk, privacy: .public) (\(path, privacy: .public))")
        } else {
            Logger.app.error("Couldn't eject \(wholeDisk, privacy: .public) (\(path, privacy: .public))")
        }
        await refresh()
    }

    private func startBackup(isAutomatic: Bool) async {
        guard let destination, diskStatus.canStartBackup else { return }
        let needsMount = diskStatus == .ejected
        backupRequestDate = .now
        await refresh()
        if needsMount {
            guard let uuid = Settings.volumeUUIDs[destination.id], await Disk.mount(uuid) else {
                Logger.app.error("Couldn't mount \(destination.name, privacy: .public) before backing up")
                backupRequestDate = nil
                await refresh()
                return
            }
        }
        Logger.app.notice("Starting backup to \(destination.name, privacy: .public)")
        didFailToEject = false
        await TimeMachine.startBackup(isAutomatic: isAutomatic)
        await refresh()
    }

    /// 取り出したディスクを Time Machine は自分でマウントしないので、スケジュールのバックアップが飛ばされ続ける。
    /// Time Machine の設定の頻度で予定の時刻を過ぎたら、Back Up Now と同じようにマウントして始める。
    /// 実機でスリープ復帰後に始まらない理由を後から `log show` で追えるよう、この経路は info/debug ではなく保存される notice で残す。
    /// `trigger` は確認のきっかけ（launch / timer / wake）。
    private func startScheduledBackupIfDue(trigger: String) async {
        guard !Settings.isDisabled else {
            Logger.app.notice("Scheduled backup check (\(trigger, privacy: .public)) skipped: disabled")
            return
        }
        await refresh()
        // バックアップ中・開始待ち・未接続・マウント中（Time Machine が自分で始める）は対象外
        guard let destination, diskStatus == .ejected else {
            Logger.app.notice("Scheduled backup check (\(trigger, privacy: .public)) skipped: disk status is \(String(describing: self.diskStatus), privacy: .public)")
            return
        }
        let schedule = TimeMachine.schedule(for: destination.id)
        let lastBackup = schedule.lastBackupDate?.description ?? "unknown"
        let lastAttempt = scheduledBackupAttemptDate?.description ?? "none"
        guard schedule.isDue(at: .now, lastAttempt: scheduledBackupAttemptDate) else {
            Logger.app.notice("Scheduled backup check (\(trigger, privacy: .public)): not due (automatic: \(schedule.isAutomatic), interval: \(schedule.interval)s, last backup: \(lastBackup, privacy: .public), last attempt: \(lastAttempt, privacy: .public))")
            return
        }
        Logger.app.notice("Scheduled backup check (\(trigger, privacy: .public)): due (interval: \(schedule.interval)s, last backup: \(lastBackup, privacy: .public), last attempt: \(lastAttempt, privacy: .public))")
        scheduledBackupAttemptDate = .now
        await startBackup(isAutomatic: true)
        Logger.app.notice("Scheduled backup requested. Disk status is \(String(describing: self.diskStatus), privacy: .public)")
        // --auto では backupd が状況を見て始めないことがあり、そのままだと次のスケジュールまでマウントしたままになる。
        // 開始を待つのと同じ時間だけ待って、始まっていなければ取り出し直す
        try? await Task.sleep(for: .seconds(Self.backupStartTimeout))
        await refresh()
        guard diskStatus == .connected, let mountPoint = self.destination?.mountPoint else {
            Logger.app.notice("Scheduled backup started or disk is no longer idle. Disk status is \(String(describing: self.diskStatus), privacy: .public)")
            return
        }
        Logger.app.notice("Scheduled backup didn't start. Ejecting \(mountPoint, privacy: .public) again.")
        await eject(mountPoint)
        Logger.app.notice("Re-eject finished. Disk status is \(String(describing: self.diskStatus), privacy: .public)")
    }

    @objc private func toggleDisable(_ sender: NSMenuItem) {
        Settings.isDisabled.toggle()
        Settings.isDisabled ? stop() : start()
        sender.state = Settings.isDisabled ? .on : .off
    }

    @objc private func backUpNow(_ sender: NSMenuItem) {
        Task { [weak self] in
            guard let self else { return }
            await startBackup(isAutomatic: false)
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        Settings.isLaunchAtLoginEnabled.toggle()
        sender.state = Settings.isLaunchAtLoginEnabled ? .on : .off
    }

    @objc private func openGitHub(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(URL(string: "https://github.com/wata/TimeMachineEjector")!)
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(self)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        menuRefreshTask?.cancel()
        menuRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await refresh()
                try? await Task.sleep(for: Self.menuRefreshInterval)
            }
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        menuRefreshTask?.cancel()
        menuRefreshTask = nil
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(AppDelegate.backUpNow(_:)) else {
            return true
        }
        return diskStatus.canStartBackup
    }
}
