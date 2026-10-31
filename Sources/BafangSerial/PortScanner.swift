import Foundation

public enum PortScanner {
    /// Callout devices (`/dev/cu.*`), excluding the built-in ones that are never a controller.
    public static func availablePorts() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return names
            .filter { $0.hasPrefix("cu.") && !ignored.contains($0) }
            .sorted()
            .map { "/dev/" + $0 }
    }

    /// Ports whose names match common USB serial adapters (FTDI, CH340, PL2303, CP210x, CDC).
    public static func likelyAdapters() -> [String] {
        availablePorts().filter { path in
            usbMarkers.contains { path.localizedCaseInsensitiveContains($0) }
        }
    }

    private static let ignored: Set<String> = ["cu.Bluetooth-Incoming-Port", "cu.debug-console"]
    private static let usbMarkers = ["usbserial", "usbmodem", "SLAB_USBtoUART", "wchusbserial", "PL2303"]
}
