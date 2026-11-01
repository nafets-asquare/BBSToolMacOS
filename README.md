# BBSTool for macOS

macOS port of the Bafang Configuration Tool V2.0 (Delphi 7, originally by Bafang, reworked by Stefan Penov — penoff.wordpress.com, https://penoff.me/2016/01/13/e-bike-conversion-software/)

## Layout

- `Sources/BafangProtocol` – packet building, block decoding/encoding, response framing. No I/O.
- `Sources/BafangSerial` – raw serial port (1200 8N1, no flow control), port listing, `ControllerLink` for single request/response exchanges, and `ControllerSession`, an actor that validates writes against the connected controller and verifies them by reading back.
- `Sources/BBSToolApp` – the SwiftUI app: connection, controller info, Basic / Pedal Assist / Throttle tabs, and a Guide tab explaining each setting (rewritten from Karl Gesslein's "A Hacker's Guide To Programming The BBS02 & BBSHD").
- `Sources/bbstool` – command-line tool for testing against a controller.
- `original/` – the original Delphi 7 source of the Windows tool, for reference and credit.
- `Resources/` – app icon from the original tool, plus its two profiles (`Profiles/`), added to the bundle by `scripts/build-app.sh`.

## Profiles

The app opens and saves the original tool's `.el` profiles (File > Open Profile…, Save Profile, Save Profile As…),
so profiles move freely between this app and the Windows tool. Double-clicking a `.el` file in Finder opens it in BBSTool. New profiles are saved in `~/Documents/BBSTool Profiles`
by default. One addition: a wheel diameter the Windows tool cannot show (e.g. 26.5") is saved as the nearest size
plus an extra `WDCODE` key with the exact value, which the Windows tool ignores.
- `Tests/` – unit tests (swift-testing). `BafangSerialTests` drive `ControllerLink` against a simulated controller on a pseudo-terminal.

## Build and test

Requires Xcode 27.2 or later (Swift 6.4).

```sh
swift test
swift build -c release   # produces .build/release/bbstool
scripts/build-app.sh     # produces .build/app/BBSTool.app (signed ad hoc)
```

To work on the app in Xcode, open `Package.swift` and run the `BBSToolApp` scheme.

## Release

`scripts/release.sh` builds a universal app, signs it with the Developer ID Application certificate
(hardened runtime), notarizes and staples it, and packages it as a signed, notarized and stapled
`.build/release-dmg/BBSTool-<version>.dmg`:

```sh
VERSION=1.0.0 scripts/release.sh
```

Notarization credentials must be stored once in the keychain under the profile `BBSTool`, e.g. with an
App Store Connect API key (`xcrun notarytool store-credentials BBSTool --key … --key-id … --issuer …`).
`NOTARIZE=0` signs without notarizing.

## bbstool

```sh
bbstool ports                   # list serial ports, marking USB adapters
bbstool info [port] [--trace]   # connect and show controller info
bbstool read [port] [--trace]   # connect and read all three settings blocks
bbstool rewrite throttle [port] # write a block's current values back unchanged, then verify
```

`rewrite` (block `basic`, `pas` or `throttle`) is the only command that writes, and it only writes back
what it just read, after asking for confirmation. With no port given, the only USB serial adapter present is used.
`--trace` prints every byte sent and received; `--reopen` closes and reopens the port between requests
as the original tool did; `--timeout <ms>` and `--attempts <n>` adjust the connect behaviour.
