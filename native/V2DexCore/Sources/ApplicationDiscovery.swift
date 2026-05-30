import AppKit
import Foundation

public enum ApplicationDiscovery {
    public static func discover(limit: Int = 200) -> [AppRouteRule] {
        var rulesByBundleID: [String: AppRouteRule] = [:]

        for app in NSWorkspace.shared.runningApplications {
            guard !app.isTerminated, app.activationPolicy != .prohibited else {
                continue
            }

            let bundleID = app.bundleIdentifier ?? app.executableURL?.lastPathComponent ?? app.localizedName ?? "pid-\(app.processIdentifier)"
            let name = app.localizedName ?? app.executableURL?.deletingPathExtension().lastPathComponent ?? bundleID
            let executable = app.executableURL?.deletingPathExtension().lastPathComponent ?? name

            rulesByBundleID[bundleID] = AppRouteRule(
                bundleId: bundleID,
                name: name,
                processName: executable,
                enabled: false
            )
        }

        return Array(rulesByBundleID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }.prefix(limit))
    }

    public static func pngIconBase64(for bundleId: String) -> String? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        guard let tiff = icon.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        return png.base64EncodedString()
    }
}
