# BBSTool for macOS

macOS port of the Bafang Configuration Tool V2.0 (Delphi 7, originally by Bafang, reworked by Stefan Penov — penoff.wordpress.com).

## Layout

- `Sources/BafangProtocol` – packet building, block decoding/encoding, response framing. No I/O.
- `Tests/BafangProtocolTests` – unit tests (swift-testing).

## Build and test

`xcode-select` points at the Command Line Tools, so select Xcode-beta per command:

```sh
DEVELOPER_DIR=~/Downloads/Xcode-beta.app/Contents/Developer swift test
```
