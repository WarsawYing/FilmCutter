# Install FilmCutter 1.01 Beta

1. Download the release ZIP from the [1.01 Beta release page](https://github.com/WarsawYing/FilmCutter/releases/tag/v1.0.1-beta.1).
2. Unzip `FilmCutter-1.01-Beta-macOS-Apple-Silicon.zip`.
3. Double-click `安装 FilmCutter.command`.
4. FilmCutter is installed to `~/Applications/FilmCutter.app` and launched.
5. On the first launch, if macOS blocks the ad-hoc-signed Beta, right-click the
   app and choose **Open**, or approve it in **Privacy & Security**.

The installer is offline. It does not run pip, install Python, remove quarantine
or bypass Gatekeeper.

## Upgrade

Run the installer from the new ZIP. It displays the installed and incoming
versions before asking for confirmation. The old app is kept as a hidden backup
during installation; a failed copy or signature check automatically restores it.

## Verify the download

From Terminal, run:

```sh
shasum -a 256 FilmCutter-1.01-Beta-macOS-Apple-Silicon.zip
```

The output must match [`SHA256SUMS`](SHA256SUMS).
