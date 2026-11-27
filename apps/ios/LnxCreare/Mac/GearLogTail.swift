#if os(macOS)
import Foundation
import Observation

// ~/Library/Logs/lnx-server.log の末尾を追いかける。
@MainActor
@Observable
final class GearLogTail {
    let logURL: URL
    private(set) var lines: [GearLogLine] = []
    var following = true
    let limit = 3000

    private var offset: UInt64 = 0
    private var fileInode: UInt64?
    private var hasInitialRead = false
    private var splitter = GearLineSplitter()
    private var nextID = 0
    private var timer: Timer?

    init(logURL: URL = BundledServer.logURL) {
        self.logURL = logURL
    }

    func start() {
        guard timer == nil else { return }
        read(initial: !hasInitialRead)
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.read(initial: false) }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func clear() {
        lines.removeAll()
    }

    private func read(initial: Bool) {
        guard FileManager.default.fileExists(atPath: logURL.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path)
        else { return }
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value
        let rotated = inode != nil && fileInode != nil && inode != fileInode
        var skippedPartialFirstLine = false
        if initial || rotated || size < offset {
            fileInode = inode
            hasInitialRead = true
            if initial && size > 262_144 {
                offset = size - 262_144
                skippedPartialFirstLine = true
            } else {
                offset = 0
            }
            splitter.reset()
            lines.removeAll()
        } else {
            fileInode = inode
        }
        guard size > offset, let handle = try? FileHandle(forReadingFrom: logURL) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        guard var data = try? handle.readToEnd(), !data.isEmpty else { return }
        offset += UInt64(data.count)
        if skippedPartialFirstLine {
            if let firstNewline = data.firstIndex(of: 0x0A) {
                data = Data(data[data.index(after: firstNewline)...])
            } else {
                return
            }
        }
        let raw = splitter.push(data)
        var added: [GearLogLine] = []
        for r in raw {
            nextID += 1
            if let l = parseGearLogLine(r, id: nextID) {
                added.append(l)
            }
        }
        guard !added.isEmpty else { return }
        lines.append(contentsOf: added)
        if lines.count > limit {
            lines.removeFirst(lines.count - limit)
        }
    }
}
#endif
