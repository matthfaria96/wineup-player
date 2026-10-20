import GRDB

enum LibraryMigrations {
    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { _ in }
        return m
    }
}
