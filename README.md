# BBSTool for macOS

macOS port of the Bafang Configuration Tool V2.0 (Delphi 7, originally by Bafang, reworked by Stefan Penov — penoff.wordpress.com).

## Layout

- `Sources/BafangProtocol` – packet building, block decoding/encoding, response framing. No I/O.
- `Sources/BafangSerial` – raw serial port (1200 8N1, no flow control), port listing, and `ControllerLink` for request/response exchanges. Read-only for now.
- `Sources/bbstool` – command-line tool for testing against a controller.
- `Tests/` – unit tests (swift-testing). `BafangSerialTests` drive `ControllerLink` against a simulated controller on a pseudo-terminal.

## Build and test

`xcode-select` points at the Command Line Tools, so select Xcode-beta per command:

```sh
export DEVELOPER_DIR=~/Downloads/Xcode-beta.app/Contents/Developer
swift test
swift build -c release   # produces .build/release/bbstool
```

## bbstool

```sh
bbstool ports                   # list serial ports, marking USB adapters
bbstool info [port] [--trace]   # connect and show controller info
bbstool read [port] [--trace]   # connect and read all three settings blocks
```

`bbstool` never writes to the controller. With no port given it uses the only USB serial adapter present.
`--trace` prints every byte sent and received; `--reopen` closes and reopens the port between requests
as the original tool did; `--timeout <ms>` and `--attempts <n>` adjust the connect behaviour.
