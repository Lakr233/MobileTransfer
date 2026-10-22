# iTM

iTM (iOS TimeMachine) is a macOS app for backing up and restoring iOS devices. It is based on [MobileTransfer](https://github.com/Lakr233/MobileTransfer) by Lakr Aream.

Author: [@Sunbelife](https://weibo.com/x1nyang) · Sina Weibo.

## Features

- Back up and restore iOS device data.
- Choose a backup destination and set a backup password.
- Load a checkpoint for an incremental backup.
- Verify a backup and convert a BBackupp archive.

The experimental app backup and restore feature is currently broken because of an API change. Downgrade restore can damage a device; use it only after verifying the archive and target.

Existing `.mobiletransfer` archives remain supported. The extension stays the same to avoid breaking existing backups.

## Licensing

The MobileTransfer application code is licensed under MIT. Its original copyright and license are retained in [LICENSE](LICENSE). Third-party notices are bundled in `MobileTransfer/Resources/License.txt`.

The bundled `MobileInstall` command-line helper contains GPL-2.0-or-later code, and `MobileBackup` contains LGPL-2.1-or-later code. Private internal development does not require publication. Review the corresponding source and license obligations before distributing an app bundle outside the organization.

The Xcode project and scheme retain their upstream names for build compatibility; the macOS product name, icon, and bundle identifier are iTM.
