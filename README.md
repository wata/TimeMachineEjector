# TimeMachineEjector

<img src="assets/icon.png" width="128" height="128" alt="TimeMachineEjector icon">

A simple Mac menu bar app that automatically ejects your Time Machine backup disk when a backup finishes.

If you leave an external backup disk connected, you have to remember to eject it before unplugging. TimeMachineEjector watches Time Machine and ejects the disk once the backup and its cleanup are done, so you can unplug it any time.

**[Download the latest version](https://github.com/wata/TimeMachineEjector/releases/latest)** — signed and notarized, with automatic updates.

No more of this:

<img src="screenshots/disk-not-ejected.png" width="354" alt="Disk Not Ejected Properly notification">

The disk stays connected while ejected. Choose **Back Up Now** from the menu bar to mount it and start a backup; it is ejected again when the backup finishes.

![Screenshot 1](screenshots/screenshot-1.png)

## Features

- **Ejects after the backup is really done**: it waits until Time Machine reports it is no longer running, so the cleanup after the copy isn't cut short.
- **Back Up Now from the menu bar**: mounts the ejected disk and starts a backup.
- **Status at a glance**: the menu shows whether the disk is connected, ejected, or backing up, with progress.
- **Disable** it from the menu when you want to keep the disk mounted.
- Launch at Login, and automatic updates.

## Requirements

macOS 13 or later.

## Usage

Download the latest pre-built application binary from Releases page and move it to `/Applications`. TimeMachineEjector checks for updates automatically, and you can also choose Check for Updates... from its menu.

Open it once and turn on Launch at Login from the menu bar icon. There is nothing else to set up; it works with the backup disk you already use in Time Machine.

The disk is unmounted, not powered off, so it can be mounted again for the next backup. Other volumes on the same disk are unmounted too, just like ejecting it in Finder.

## Development

- `./scripts/install.sh` builds a Release build and replaces `/Applications/TimeMachineEjector.app` with it (`--no-launch` to skip launching).
- `./scripts/release.sh <version> [--notes <file>]` bumps the version, builds a zip, updates `appcast.xml`, and publishes a GitHub Release. Use `--no-publish` to stop before committing.

## License

MIT
