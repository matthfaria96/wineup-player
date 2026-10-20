import GRDB

enum LibraryMigrations {
    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "library_root") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("uuid", .text).notNull().unique()
                t.column("path", .text).notNull().unique()
                t.column("volume_uuid", .text)
                t.column("online", .boolean).notNull().defaults(to: true)
                t.column("added_at", .datetime).notNull()
                t.column("last_scan_at", .datetime)
            }
            try db.create(table: "audio_file") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("root_id", .integer).references("library_root", onDelete: .restrict).notNull()
                t.column("path", .text).notNull().unique()
                t.column("volume_uuid", .text)
                t.column("inode", .integer)
                t.column("size", .integer).notNull()
                t.column("mtime_ns", .integer).notNull()
                t.column("content_hash", .blob)
                t.column("status", .text).notNull().defaults(to: "present")
                    .check { $0 == "present" || $0 == "missing" }
                t.column("missing_since", .datetime)
                t.column("last_seen_at", .datetime)
                t.column("format", .text)
                t.column("duration", .double)
                t.column("read_error", .text)
            }
            try db.create(index: "audio_file_volume_inode", on: "audio_file", columns: ["volume_uuid", "inode"])
            try db.create(index: "audio_file_root", on: "audio_file", columns: ["root_id"])
            try db.create(index: "audio_file_status", on: "audio_file", columns: ["status"])

            try db.create(table: "artist") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("sort_key", .text).notNull().unique()
            }
            try db.create(table: "release") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("album_artist_id", .integer).references("artist", onDelete: .restrict)
                t.column("year", .text)
                t.column("kind", .text).notNull().defaults(to: "unknown")
                    .check { ["album", "single", "ep", "compilation", "unknown"].contains($0) }
                t.column("kind_source", .text).notNull().defaults(to: "inferred")
                    .check { ["tag", "inferred", "user"].contains($0) }
                t.uniqueKey(["title", "album_artist_id"])
            }
            try db.create(table: "recording") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("artist_id", .integer).references("artist", onDelete: .restrict)
                t.column("duration", .double)
            }
            try db.create(table: "release_track") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("release_id", .integer).references("release", onDelete: .restrict)
                t.column("recording_id", .integer).references("recording", onDelete: .restrict).notNull()
                t.column("audio_file_id", .integer).references("audio_file", onDelete: .restrict).notNull().unique()
                t.column("disc_number", .integer)
                t.column("track_number", .integer)
                t.column("genre", .text)
            }
            try db.create(table: "artwork") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("audio_file_id", .integer).references("audio_file", onDelete: .restrict)
                t.column("release_id", .integer).references("release", onDelete: .restrict)
                t.column("source", .text).notNull()
                    .check { ["embedded", "folder", "release"].contains($0) }
                t.column("sha256", .text)
                t.column("byte_count", .integer)
                t.column("picture_type", .integer)
            }
            try db.create(table: "lyrics") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("recording_id", .integer).references("recording", onDelete: .restrict)
                t.column("audio_file_id", .integer).references("audio_file", onDelete: .restrict)
                t.column("source", .text).notNull()
                    .check { ["embedded", "sidecar"].contains($0) }
                t.column("synced", .boolean).notNull().defaults(to: false)
                t.column("text", .text)
            }
            try db.create(table: "journal") { t in
                t.primaryKey("id", .text)
                t.column("audio_file_id", .integer).references("audio_file", onDelete: .restrict)
                t.column("path", .text).notNull()
                t.column("backup_path", .text)
                t.column("diffs_json", .text).notNull()
                t.column("status", .text).notNull()
                    .check { ["applied", "undone", "failed"].contains($0) }
                t.column("after_inode", .integer)
                t.column("after_size", .integer)
                t.column("after_mtime_ns", .integer)
                t.column("created_at", .datetime).notNull()
                t.column("undone_at", .datetime)
            }
            try db.create(table: "tag_snapshot") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("journal_id", .text).notNull().references("journal", onDelete: .restrict)
                t.column("kind", .text).notNull().check { $0 == "before" || $0 == "after" }
                t.column("json", .text).notNull()
            }
            try db.create(table: "play_event") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("audio_file_id", .integer).references("audio_file", onDelete: .restrict).notNull()
                t.column("played_at", .datetime).notNull()
            }
            try db.create(table: "track_mark") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("audio_file_id", .integer).references("audio_file", onDelete: .restrict).notNull().unique()
                t.column("color", .text).notNull()
                    .check { ["green", "blue", "purple", "red", "orange", "yellow"].contains($0) }
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(table: "app_setting") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
            try db.create(table: "playlist") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("uuid", .text).notNull().unique()
                t.column("name", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(table: "playlist_item") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("playlist_id", .integer).references("playlist", onDelete: .restrict).notNull()
                t.column("audio_file_id", .integer).references("audio_file", onDelete: .restrict).notNull()
                t.column("position", .integer).notNull()
                t.uniqueKey(["playlist_id", "position"])
            }
            try db.execute(sql: """
                CREATE VIRTUAL TABLE track_fts USING fts5(
                    title, artist, album, genre,
                    tokenize='unicode61 remove_diacritics 2', prefix='2 3')
                """)
        }
        return m
    }
}
