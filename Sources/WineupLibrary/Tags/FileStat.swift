import Foundation

/// Identidade física do arquivo (inode, tamanho, mtime em ns), mesma fórmula do FileEnumerator.
struct FileStat: Equatable, Sendable {
    let inode: UInt64
    let size: Int64
    let mtimeNs: Int64

    static func of(_ url: URL) throws -> FileStat {
        var st = stat()
        guard stat(url.path, &st) == 0 else { throw TagWriterError.writeFailed }
        let ns = Int64(st.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(st.st_mtimespec.tv_nsec)
        return FileStat(inode: UInt64(st.st_ino), size: Int64(st.st_size), mtimeNs: ns)
    }
}
