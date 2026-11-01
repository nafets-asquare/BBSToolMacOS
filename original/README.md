# Original Windows source

Delphi 7 source of the **Bafang Configuration Tool V2.0** for Windows, which this macOS app is ported from.
It is included for reference and credit; nothing here is built or used by the macOS app.

- Originally developed by Bafang (www.szbaf.com) and released with its source code.
- Reworked and released as V2.0 by Stefan Penov (penoff.wordpress.com), who asks that the information
  about his work be kept with the files when redistributing; see the header of `Main.pas`.
- `SPComm component/` is the third-party serial port component the tool was built with.
- Compiled units (`.dcu`), IDE diagram files (`.ddp`) and the Windows executable are left out.

Where the macOS app deliberately behaves differently from this code (checksums, flow control, write-error
mapping, value validation), the reasons are noted in the Swift sources and in the release notes.
