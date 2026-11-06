import AppKit

/// Remembers icons applied with the Auto tone, and swaps each one when the Mac changes mode.
@MainActor
final class AutoIconKeeper {
    private struct Entry: Codable {
        let id: UUID
        let bookmark: Data
        var showsDark: Bool
    }

    nonisolated static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Icon Mixer/Auto Icons")
    }

    private let store: IconStoring
    private let folder: URL
    private let settleTime: Duration
    private var entries: [Entry]
    private var isSyncing = false

    init(store: IconStoring, folder: URL, settleTime: Duration) {
        self.store = store
        self.folder = folder
        self.settleTime = settleTime
        let saved = try? Data(contentsOf: folder.appendingPathComponent("index.json"))
        self.entries = saved.flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    var hasIcons: Bool { !entries.isEmpty }

    func keep(_ target: URL, light: CGImage, dark: CGImage, showsDark: Bool) throws {
        remove(target)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let entry = Entry(id: UUID(), bookmark: try target.bookmarkData(), showsDark: showsDark)
        try png(light).write(to: file(for: entry, dark: false))
        try png(dark).write(to: file(for: entry, dark: true))
        entries.append(entry)
        try save()
    }

    func remove(_ target: URL) {
        let path = target.resolvingSymlinksInPath().path
        let matching = entries.filter { resolve($0)?.path == path }
        guard !matching.isEmpty else { return }
        matching.forEach(deleteFiles)
        entries.removeAll { entry in matching.contains { $0.id == entry.id } }
        try? save()
    }

    /// Brings every kept icon in line with the mode. An icon that's gone, or was removed, stops being kept.
    func sync(isDark: Bool) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        for entry in entries {
            guard let target = resolve(entry), store.hasCustomIcon(at: target) else {
                deleteFiles(entry)
                entries.removeAll { $0.id == entry.id }
                continue
            }
            guard entry.showsDark != isDark,
                  let icon = NSImage(contentsOf: file(for: entry, dark: isDark)) else { continue }
            let previous = NSImage(contentsOf: file(for: entry, dark: !isDark))
            guard await store.replaceIcon(at: target, with: icon, previous: previous, settleTime: settleTime),
                  let index = entries.firstIndex(where: { $0.id == entry.id }) else { continue }
            entries[index].showsDark = isDark
        }
        try? save()
    }

    private func resolve(_ entry: Entry) -> URL? {
        var isStale = false
        // Normalised the same way as dropped files, or /private/tmp and /tmp count as different places.
        return (try? URL(resolvingBookmarkData: entry.bookmark, bookmarkDataIsStale: &isStale))?.resolvingSymlinksInPath()
    }

    private func file(for entry: Entry, dark: Bool) -> URL {
        folder.appendingPathComponent("\(entry.id.uuidString)-\(dark ? "dark" : "light").png")
    }

    private func png(_ image: CGImage) throws -> Data {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    private func deleteFiles(_ entry: Entry) {
        try? FileManager.default.removeItem(at: file(for: entry, dark: false))
        try? FileManager.default.removeItem(at: file(for: entry, dark: true))
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: folder.appendingPathComponent("index.json"))
    }
}
