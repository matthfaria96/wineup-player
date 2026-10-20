import Foundation

public struct EnumeratedFile: Sendable, Hashable {
    public let path: String
    public let inode: UInt64
    public let size: Int64
    public let mtimeNs: Int64
}

/// Enumeração rápida via fts (só stat; não segue symlinks).
public enum FileEnumerator {
    public static func enumerate(root: URL, isCancelled: () -> Bool) throws -> [EnumeratedFile] {
        let rootPath = root.path
        var result: [EnumeratedFile] = []
        let cPath = strdup(rootPath)
        defer { free(cPath) }
        var paths: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR, nil) else {
            throw LibraryError.rootNotReadable
        }
        defer { fts_close(fts) }
        var visited = 0
        while let entry = fts_read(fts) {
            visited += 1
            if visited % 1000 == 0, isCancelled() { throw CancellationError() }
            let info = Int32(entry.pointee.fts_info)
            if info == FTS_D {
                // Pastas ocultas não são exploradas.
                if entry.pointee.fts_level > 0, let name = entry.pointee.fts_name_string, name.hasPrefix(".") {
                    fts_set(fts, entry, FTS_SKIP)
                }
                continue
            }
            guard info == FTS_F, let st = entry.pointee.fts_statp?.pointee else { continue }
            let path = String(cString: entry.pointee.fts_path)
            let name = (path as NSString).lastPathComponent
            guard !name.hasPrefix("."),
                  TagReader.audioExtensions.contains((name as NSString).pathExtension.lowercased())
            else { continue }
            let ns = Int64(st.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(st.st_mtimespec.tv_nsec)
            result.append(EnumeratedFile(path: path, inode: UInt64(st.st_ino), size: Int64(st.st_size), mtimeNs: ns))
        }
        return result
    }
}

private extension FTSENT {
    var fts_name_string: String? {
        withUnsafePointer(to: self) { p in
            let base = UnsafeRawPointer(p).advanced(by: MemoryLayout<FTSENT>.offset(of: \FTSENT.fts_name)!)
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
    }
}
