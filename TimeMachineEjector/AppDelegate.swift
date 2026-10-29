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
final class AppDelegate: NSObject, NSApplicationDelegate {
    // backupd が始めなかったときに「Starting Backup…」のまま残らないよう、この時間で諦める
    private static let backupStartTimeout: TimeInterval = 60

    private let backupMonitor = BackupMonitor()
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    private lazy var statusItem: NSStatusItem = {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // SF Symbols はメニューバーの標準の大きさで描かれ、ライト/ダークにも追従する
        statusItem.button?.image = NSImage(systemSymbolName: "eject.fill", accessibilityDescription: "TimeMachineEjector")
        return statusItem
    }()
    private lazy var diskItem = makeMenuItem(title: diskStatus.title(destinationName: nil), selector: nil)
    private var destination: TimeMachine.Destination?
    private var diskStatus = BackupDiskStatus.noDestination
    private var didFailToEject = false
    // Back Up Now を押した時刻。backupd が Running になるまでの数秒、Ejected などのままに見えないよう「Starting Backup…」を出す
    private var backupRequestedAt: Date?

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
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? ""
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        menu.addItem(makeMenuItem(title: "Disable", selector: #selector(AppDelegate.toggleDisable(_:)), isOn: Settings.isDisabled))
        menu.addItem(.separator())
        menu.addItem(diskItem)
        menu.addItem(makeMenuItem(title: "Back Up Now", selector: #selector(AppDelegate.backUpNow(_:))))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "Check for Updates...", selector: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), target: updaterController))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "Launch at Login", selector: #selector(AppDelegate.toggleLaunchAtLogin(_:)), isOn: Settings.isLaunchAtLoginEnabled))
        menu.addItem(makeMenuItem(title: "About \(name) \(version)", selector: #selector(AppDelegate.openGitHub(_:))))
        menu.addItem(makeMenuItem(title: "Quit", selector: #selector(AppDelegate.quit(_:))))
        statusItem.menu = menu
    }

    private func makeMenuItem(title: String, selector: Selector?, target: AnyObject? = nil, isOn: Bool? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
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
            backupRequestedAt = nil
        }
        let isStartingBackup = backupRequestedAt.map { Date.now.timeIntervalSince($0) < Self.backupStartTimeout } ?? false
        self.destination = destination
        diskStatus = BackupDiskStatus(destination: destination, status: status, volume: volume, didFailToEject: didFailToEject, isStartingBackup: isStartingBackup)
        diskItem.title = diskStatus.title(destinationName: destination?.name)
        // 開いているメニューの Back Up Now の有効/無効を、更新後の状態で検証し直す
        statusItem.menu?.update()
    }

    private func volume(of destination: TimeMachine.Destination?) async -> Disk.Info? {
        guard let destination else { return nil }
        if let mountPoint = destination.mountPoint, let info = await Disk.info(for: mountPoint) {
            if let uuid = info.volumeUUID, Settings.volumeUUIDs[destination.id] != uuid {
                Settings.volumeUUIDs[destination.id] = uuid
            }
            return info
        }
        guard let uuid = Settings.volumeUUIDs[destination.id] else { return nil }
        return await Disk.info(for: uuid)
    }

    private func eject(_ path: String) async {
        guard !Settings.isDisabled else { return }
        // アンマウントすると UUID が取れなくなるので、先に宛先の UUID を覚えさせておく
        await refresh()
        guard let volume = await Disk.info(for: path), volume.isMounted else {
            Logger.app.info("\(path, privacy: .public) is already unmounted")
            return
        }
        let wholeDisk = await Disk.physicalWholeDisk(of: volume)
        let isEjected = await Disk.unmountDisk(wholeDisk)
        didFailToEject = !isEjected
        if isEjected {
            Logger.app.info("Ejected \(wholeDisk, privacy: .public) (\(path, privacy: .public))")
        } else {
            Logger.app.error("Couldn't eject \(wholeDisk, privacy: .public) (\(path, privacy: .public))")
        }
        await refresh()
    }

    private func startBackup() async {
        guard let destination, diskStatus.canStartBackup else { return }
        let needsMount = diskStatus == .ejected
        backupRequestedAt = .now
        await refresh()
        if needsMount {
            guard let uuid = Settings.volumeUUIDs[destination.id], await Disk.mount(uuid) else {
                Logger.app.error("Couldn't mount \(destination.name, privacy: .public) before backing up")
                backupRequestedAt = nil
                await refresh()
                return
            }
        }
        Logger.app.info("Starting backup to \(destination.name, privacy: .public)")
        didFailToEject = false
        await TimeMachine.startBackup()
        await refresh()
    }

    @objc private func toggleDisable(_ sender: NSMenuItem) {
        Settings.isDisabled.toggle()
        Settings.isDisabled ? backupMonitor.stop() : start()
        sender.state = Settings.isDisabled ? .on : .off
    }

    @objc private func backUpNow(_ sender: NSMenuItem) {
        Task { [weak self] in
            guard let self else { return }
            await startBackup()
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
    func menuNeedsUpdate(_ menu: NSMenu) {
        Task { [weak self] in
            guard let self else { return }
            await refresh()
        }
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(AppDelegate.backUpNow(_:)) else { return true }
        return diskStatus.canStartBackup
    }
}
