// Dart imports:
// ignore_for_file: avoid_slow_async_io

// Dart imports:
import 'dart:async';
import 'dart:io';

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Project imports:
import 'app_file_system.dart';

const _kAppTemporaryDirectoryName = String.fromEnvironment('APP_NAME');

class IoFileSystem implements AppFileSystem {
  const IoFileSystem();

  static const MethodChannel _channel = MethodChannel('com.degenk.boorusama/filesystem');

  // Path resolution

  @override
  Future<void> excludeFromBackup(String path) async {
    if (kIsWeb) return;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        await _channel.invokeMethod('excludeFromBackup', {'path': path});
      } catch (e) {
        debugPrint('Failed to exclude from backup: $e');
      }
    }
  }

  @override
  Future<String> getAppStoragePath() async {
    if (kIsWeb) return '';

    final dir = defaultTargetPlatform == TargetPlatform.android
        ? await getApplicationDocumentsDirectory()
        : await getApplicationSupportDirectory();

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // 1. Try TrollStore sandbox-escape path
      final trollStoreDir = Directory('/var/mobile/Documents/BoorusamaData');
      bool hasTrollStorePrivilege = false;
      
      try {
        if (!trollStoreDir.existsSync()) {
          trollStoreDir.createSync(recursive: true);
        }
        final testFile = File(p.join(trollStoreDir.path, '.test_write'));
        testFile.writeAsStringSync('test');
        testFile.deleteSync();
        hasTrollStorePrivilege = true;
      } catch (e) {
        hasTrollStorePrivilege = false;
      }

      if (hasTrollStorePrivilege) {
        // Migrate from both NoBackup and root Application Support if needed
        final sources = [Directory(p.join(dir.path, 'NoBackup')), dir];
        
        for (final sourceDir in sources) {
          if (!sourceDir.existsSync()) continue;
          try {
            final files = sourceDir.listSync();
            for (final entity in files) {
              final name = p.basename(entity.path);
              if (name == 'NoBackup' || name == 'BoorusamaData') continue;
              
              if (entity is File && (name.endsWith('.hive') || name.endsWith('.lock') || name.endsWith('.hivec'))) {
                final dest = p.join(trollStoreDir.path, name);
                if (!File(dest).existsSync()) {
                  entity.copySync(dest);
                  entity.deleteSync();
                }
              } else if (entity is Directory && name == 'data') {
                final dest = p.join(trollStoreDir.path, name);
                if (!Directory(dest).existsSync()) {
                  try {
                    entity.renameSync(dest);
                  } catch (_) {}
                }
              }
            }
          } catch (e) {
            debugPrint('TrollStore migration error: $e');
          }
        }
        return trollStoreDir.path;
      }

      // 2. Fallback to NoBackup logic for standard App Store/Sandboxed users
      final noBackupDir = Directory(p.join(dir.path, 'NoBackup'));
      if (!noBackupDir.existsSync()) {
        noBackupDir.createSync(recursive: true);
        
        // Migrate existing files to prevent data loss
        try {
          final files = dir.listSync();
          for (final entity in files) {
            final name = p.basename(entity.path);
            if (name == 'NoBackup') continue;
            
            if (entity is File && (name.endsWith('.hive') || name.endsWith('.lock') || name.endsWith('.hivec'))) {
              entity.copySync(p.join(noBackupDir.path, name));
              entity.deleteSync();
            } else if (entity is Directory && name == 'data') {
              // The sqlite folder
              entity.renameSync(p.join(noBackupDir.path, name));
            }
          }
        } catch (e) {
          debugPrint('Migration error: $e');
        }
      }
      
      // Ensure it is excluded from backup
      await excludeFromBackup(noBackupDir.path);
      return noBackupDir.path;
    }

    return dir.path;
  }

  @override
  Future<String?> getTemporaryPath() async {
    if (kIsWeb) return null;

    try {
      return (await getApplicationCacheDirectory()).path;
    } catch (_) {
      // Fall back to system temp if the platform cannot provide an app cache dir.
    }

    final dir = await getTemporaryDirectory();
    final name = _kAppTemporaryDirectoryName.isNotEmpty
        ? _kAppTemporaryDirectoryName.replaceAll(' ', '_').toLowerCase()
        : 'boorusama';

    final appDirPath = p.join(dir.path, name);
    if (!directoryExistsSync(appDirPath)) {
      await createDirectory(appDirPath);
    }
    return appDirPath;
  }

  @override
  Future<String?> getDownloadPath() async {
    if (kIsWeb) return null;

    try {
      return switch (defaultTargetPlatform) {
        TargetPlatform.android => _androidDownloadPath(),
        TargetPlatform.iOS => (await getApplicationDocumentsDirectory()).path,
        TargetPlatform.windows ||
        TargetPlatform.linux ||
        TargetPlatform.macOS => (await getDownloadsDirectory())?.path,
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  static String? _androidDownloadPath() {
    const path = '/storage/emulated/0/Download';
    return Directory(path).existsSync() ? path : null;
  }

  // File operations

  @override
  Future<bool> fileExists(String path) => File(path).exists();

  @override
  bool fileExistsSync(String path) => File(path).existsSync();

  @override
  Future<Uint8List> readBytes(String path) => File(path).readAsBytes();

  @override
  Uint8List readBytesSync(String path) => File(path).readAsBytesSync();

  @override
  Future<void> writeBytes(String path, Uint8List bytes) =>
      File(path).writeAsBytes(bytes);

  @override
  Future<String> readString(String path) => File(path).readAsString();

  @override
  Future<void> writeString(String path, String content) =>
      File(path).writeAsString(content);

  @override
  Future<void> deleteFile(String path) => File(path).delete();

  @override
  Future<void> copyFile(String source, String destination) =>
      File(source).copy(destination);

  @override
  void copyFileSync(String source, String destination) =>
      File(source).copySync(destination);

  @override
  Future<void> renameFile(String source, String destination) =>
      File(source).rename(destination);

  @override
  Future<int> fileSize(String path) => File(path).length();

  @override
  int fileSizeSync(String path) => File(path).lengthSync();

  @override
  Future<DateTime> lastModified(String path) => File(path).lastModified();

  @override
  DateTime lastModifiedSync(String path) => File(path).lastModifiedSync();

  @override
  Stream<List<int>> openRead(String path, {int? start, int? end}) =>
      File(path).openRead(start, end);

  @override
  Future<StreamSink<List<int>>> openWrite(String path) async =>
      File(path).openWrite();

  // Temp directory

  @override
  Future<String> createTempDirectory(String prefix) async {
    final dir = await Directory.systemTemp.createTemp(prefix);
    return dir.path;
  }

  // Directory operations

  @override
  Future<bool> directoryExists(String path) => Directory(path).exists();

  @override
  bool directoryExistsSync(String path) => Directory(path).existsSync();

  @override
  Future<void> createDirectory(String path, {bool recursive = false}) =>
      Directory(path).create(recursive: recursive);

  @override
  Future<void> deleteDirectory(String path, {bool recursive = false}) =>
      Directory(path).delete(recursive: recursive);

  @override
  void deleteDirectorySync(String path, {bool recursive = false}) =>
      Directory(path).deleteSync(recursive: recursive);

  @override
  Future<List<FileSystemEntry>> listDirectory(
    String path, {
    bool recursive = false,
    bool followLinks = true,
  }) async {
    final entries = <FileSystemEntry>[];
    await for (final entity in Directory(path).list(
      recursive: recursive,
      followLinks: followLinks,
    )) {
      entries.add(_toEntry(entity));
    }
    return entries;
  }

  @override
  List<FileSystemEntry> listDirectorySync(
    String path, {
    bool recursive = false,
    bool followLinks = true,
  }) {
    return Directory(path)
        .listSync(recursive: recursive, followLinks: followLinks)
        .map(_toEntry)
        .toList();
  }

  @override
  Stream<FileSystemEntry> listDirectoryStream(
    String path, {
    bool recursive = false,
    bool followLinks = true,
  }) {
    return Directory(
      path,
    ).list(recursive: recursive, followLinks: followLinks).map(_toEntry);
  }

  static FileSystemEntry _toEntry(FileSystemEntity entity) {
    return FileSystemEntry(
      path: entity.path,
      type: entity is Directory
          ? FileSystemEntryType.directory
          : FileSystemEntryType.file,
    );
  }
}
