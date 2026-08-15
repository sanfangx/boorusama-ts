// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/services.dart' show rootBundle;

// Project imports:
import 'tag_translation_repo.dart';
import 'types.dart';

/// Thin proxy that delegates to [TagTranslationRepository].
///
/// Maintains the same static API surface so existing call sites
/// (`TagTranslation.translate(...)`, `TagTranslation.searchLocal(...)`)
/// require zero changes.
///
/// The underlying repository is set once during app initialization
/// via [setRepository]. Before the repository is set, all calls
/// return null/empty results gracefully.
class TagTranslation {
  TagTranslation._();

  static TagTranslationRepository? _repo;

  /// Set the backing repository. Called once during app initialization.
  static void setRepository(TagTranslationRepository repo) {
    _repo = repo;
  }

  /// Look up the Chinese translation for an English tag.
  static String? translate(String tag) {
    return _repo?.translate(tag);
  }

  /// Search for tags matching the query text (Chinese or English).
  static List<AutocompleteData> searchLocal(
    String queryText, {
    int skip = 0,
    int limit = 20,
  }) {
    return _repo?.searchLocal(queryText, skip: skip, limit: limit) ?? [];
  }

  /// Load CSV data from assets or file system.
  ///
  /// Used only during first-launch import. Returns the raw CSV string.
  static Future<String> loadCsvData() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return File('assets/danbooru-10w-zh_cn.csv').readAsString();
    } else {
      return rootBundle.loadString('assets/danbooru-10w-zh_cn.csv');
    }
  }
}
