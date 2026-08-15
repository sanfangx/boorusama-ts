// Package imports:
import 'package:sqlite3/sqlite3.dart';

// Project imports:
import '../../../foundation/database/utils.dart';
import 'types.dart';

/// SQLite-backed tag translation repository.
///
/// Stores ~317K en→zh tag translations in a SQLite database on disk
/// instead of holding them all in Dart heap memory (~200MB).
/// Queries use indexed lookups (<1ms) with negligible memory footprint.
class TagTranslationRepository with DatabaseUtilsMixin {
  TagTranslationRepository({required this.db});

  @override
  final Database db;

  void initialize() {
    _createTableIfNotExists();
  }

  void _createTableIfNotExists() {
    db
      ..execute('''
        CREATE TABLE IF NOT EXISTS tag_translations (
          id INTEGER PRIMARY KEY,
          en TEXT NOT NULL,
          zh TEXT NOT NULL
        )
      ''')
      ..execute('''
        CREATE INDEX IF NOT EXISTS idx_tag_trans_en
        ON tag_translations (en COLLATE NOCASE)
      ''')
      ..execute('''
        CREATE INDEX IF NOT EXISTS idx_tag_trans_en_normalized
        ON tag_translations (REPLACE(LOWER(en), ' ', '_'))
      ''');
  }

  /// Returns true if the translations table is empty (needs import).
  bool get isEmpty {
    final result = db.select(
      'SELECT COUNT(*) as c FROM tag_translations',
    );
    return (result.first['c'] as int) == 0;
  }

  /// Bulk-import translations from CSV data.
  ///
  /// CSV format: `en_tag,中文翻译` (one per line, no header).
  /// Uses a single transaction for performance (~2-3 seconds for 317K rows).
  void importFromCsv(String csvData) {
    final lines = csvData.split('\n');
    final stmt = db.prepare(
      'INSERT INTO tag_translations (en, zh) VALUES (?, ?)',
    );

    db.execute('BEGIN TRANSACTION');
    try {
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final commaIndex = line.indexOf(',');
        if (commaIndex == -1) continue;

        final en = line.substring(0, commaIndex).trim();
        final zh = line.substring(commaIndex + 1).trim();
        if (en.isNotEmpty && zh.isNotEmpty) {
          stmt.execute([en, zh]);
        }
      }
      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      stmt.close();
    }
  }

  /// Look up the Chinese translation for an English tag.
  ///
  /// Handles normalization (underscores ↔ spaces, case-insensitive).
  /// Returns null if no translation is found.
  String? translate(String tag) {
    final query = tag.trim().toLowerCase();
    if (query.isEmpty) return null;

    // Try exact match first (case-insensitive via COLLATE NOCASE index)
    var result = db.select(
      'SELECT zh FROM tag_translations WHERE en = ? COLLATE NOCASE LIMIT 1',
      [query],
    );
    if (result.isNotEmpty) return result.first['zh'] as String;

    // Try with underscores replaced by spaces
    final withSpaces = query.replaceAll('_', ' ');
    if (withSpaces != query) {
      result = db.select(
        'SELECT zh FROM tag_translations WHERE en = ? COLLATE NOCASE LIMIT 1',
        [withSpaces],
      );
      if (result.isNotEmpty) return result.first['zh'] as String;
    }

    // Try with spaces replaced by underscores
    final withUnderscores = query.replaceAll(' ', '_');
    if (withUnderscores != query && withUnderscores != withSpaces) {
      result = db.select(
        'SELECT zh FROM tag_translations WHERE en = ? COLLATE NOCASE LIMIT 1',
        [withUnderscores],
      );
      if (result.isNotEmpty) return result.first['zh'] as String;
    }

    return null;
  }

  /// Search for tags matching the query text.
  ///
  /// If the query contains Chinese characters, searches the `zh` column.
  /// Otherwise, searches the `en` column with relevance-based ordering:
  /// prefix matches first, then word-boundary matches, then substring matches.
  List<AutocompleteData> searchLocal(
    String queryText, {
    int skip = 0,
    int limit = 20,
  }) {
    final cleanQuery = queryText.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];

    final hasChinese = RegExp(r'[\u4e00-\u9fa5]').hasMatch(cleanQuery);

    if (hasChinese) {
      return _searchChinese(cleanQuery, skip: skip, limit: limit);
    } else {
      return _searchEnglish(cleanQuery, skip: skip, limit: limit);
    }
  }

  List<AutocompleteData> _searchChinese(
    String query, {
    required int skip,
    required int limit,
  }) {
    final result = db.select(
      '''
      SELECT en FROM tag_translations
      WHERE zh LIKE ?
      LIMIT ? OFFSET ?
      ''',
      ['%$query%', limit, skip],
    );

    return result
        .map(
          (row) => AutocompleteData(
            label: row['en'] as String,
            value: row['en'] as String,
            category: 'general',
          ),
        )
        .toList();
  }

  List<AutocompleteData> _searchEnglish(
    String query, {
    required int skip,
    required int limit,
  }) {
    // Use UNION ALL to maintain relevance ordering:
    // Bucket A: starts with query (highest relevance)
    // Bucket B: word boundary match (medium relevance)
    // Bucket C: substring match (lowest relevance, requires 3+ chars)
    final sql = query.length > 2
        ? r'''
      SELECT en, 0 as rank FROM tag_translations
        WHERE LOWER(en) LIKE ? ESCAPE '\'
      UNION ALL
      SELECT en, 1 as rank FROM tag_translations
        WHERE (LOWER(en) LIKE ? ESCAPE '\' OR LOWER(en) LIKE ? ESCAPE '\')
        AND LOWER(en) NOT LIKE ? ESCAPE '\'
      UNION ALL
      SELECT en, 2 as rank FROM tag_translations
        WHERE LOWER(en) LIKE ? ESCAPE '\'
        AND LOWER(en) NOT LIKE ? ESCAPE '\'
        AND LOWER(en) NOT LIKE ? ESCAPE '\'
        AND LOWER(en) NOT LIKE ? ESCAPE '\'
      ORDER BY rank, en
      LIMIT ? OFFSET ?
      '''
        : r'''
      SELECT en, 0 as rank FROM tag_translations
        WHERE LOWER(en) LIKE ? ESCAPE '\'
      UNION ALL
      SELECT en, 1 as rank FROM tag_translations
        WHERE (LOWER(en) LIKE ? ESCAPE '\' OR LOWER(en) LIKE ? ESCAPE '\')
        AND LOWER(en) NOT LIKE ? ESCAPE '\'
      ORDER BY rank, en
      LIMIT ? OFFSET ?
      ''';

    final escapedQuery = _escapeLike(query);
    final params = query.length > 2
        ? [
            '$escapedQuery%', // Bucket A: starts with
            '%\\_$escapedQuery%', // Bucket B: after underscore
            '% $escapedQuery%', // Bucket B: after space
            '$escapedQuery%', // Bucket B: exclude prefix matches
            '%$escapedQuery%', // Bucket C: contains
            '$escapedQuery%', // Bucket C: exclude prefix
            '%\\_$escapedQuery%', // Bucket C: exclude word boundary _
            '% $escapedQuery%', // Bucket C: exclude word boundary space
            limit,
            skip,
          ]
        : [
            '$escapedQuery%', // Bucket A: starts with
            '%\\_$escapedQuery%', // Bucket B: after underscore
            '% $escapedQuery%', // Bucket B: after space
            '$escapedQuery%', // Bucket B: exclude prefix matches
            limit,
            skip,
          ];

    final result = db.select(sql, params);

    return result
        .map(
          (row) => AutocompleteData(
            label: row['en'] as String,
            value: row['en'] as String,
            category: 'general',
          ),
        )
        .toList();
  }

  /// Escape special LIKE pattern characters.
  String _escapeLike(String input) {
    return input
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }
}
