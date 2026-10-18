# You Don't Need That

Personal macOS disk cleaner. One screen: where your space went, drill in, yeet to Trash.

## Install on another Mac (macOS 14+)

1. Download `YouDontNeedThat-<version>.zip` from the latest release on this (private) repo.
2. Unzip, drag `YouDontNeedThat.app` to `/Applications`, open it.
3. When Mail Attachments / iOS Backups show **Needs Full Disk Access**, click **Grant Full Disk Access**,
   add the app in System Settings › Privacy & Security › Full Disk Access, then **Rescan**.

Update: download the new zip and replace the app. The Full Disk Access grant survives.

## Develop

```sh
brew install xcodegen
xcodegen generate                       # never hand-edit the .xcodeproj
open YouDontNeedThat.xcodeproj          # or:
xcodebuild -scheme YouDontNeedThat -destination 'platform=macOS' test
```

Run with `--fake` as a launch argument to use the mockup data instead of scanning.

## Release

One-time setup on the building Mac:

1. Xcode › Settings › Accounts › team V3CD35TG78 › Manage Certificates › + › **Developer ID Application**.
2. Make an app-specific password at appleid.apple.com, then
   `xcrun notarytool store-credentials ydnt --apple-id <apple-id-email> --team-id V3CD35TG78 --password <app-specific>`.
3. `gh repo create <you>/ydnt --private --source . --push` (once).

Then per release: bump `MARKETING_VERSION` in `project.yml` and run `Scripts/release.sh`.
