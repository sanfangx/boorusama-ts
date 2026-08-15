// Package imports:
import 'package:path/path.dart' show join;
import 'package:sqlite3/sqlite3.dart';

// Project imports:
import '../filesystem.dart';
import '../loggers/logger.dart';

/// Global registry of all open SQLite databases.
/// Used to checkpoint WAL on app backgrounding to prevent 0xdead10cc.
final List<Database> _openDatabases = [];

/// Checkpoint all open databases to flush WAL and release file locks.
/// Call this when the app enters background to prevent iOS 0xdead10cc kills.
void checkpointAllDatabases() {
  for (final db in _openDatabases) {
    try {
      db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {
      // Database may already be closed, ignore errors
    }
  }
}

mixin DatabaseUtilsMixin {
  Database get db;

  void transaction(void Function() action) {
    db.execute('BEGIN TRANSACTION');
    try {
      action();
      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }
}

Future<Database?> createDb({
  required AppFileSystem fs,
  required String folderPath,
  required String name,
  Logger? logger,
}) async {
  try {
    await fs.createDirectory(folderPath, recursive: true);

    final db = sqlite3.open(join(folderPath, name));

    // Enable WAL mode to minimize file lock duration.
    // This prevents iOS 0xdead10cc (deadlock kill) when app is suspended
    // while SQLite holds a file lock.
    db.execute('PRAGMA journal_mode=WAL');

    _openDatabases.add(db);

    return db;
  } on Exception catch (e) {
    logger?.error(
      name,
      'Failed to initialize SQLite database: $e',
    );
    return null;
  }
}

