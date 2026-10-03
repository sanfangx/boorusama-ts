import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:boorusama/core/tags/autocompletes/tag_translation_repo.dart';
import 'package:boorusama/core/tags/autocompletes/translation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late TagTranslationRepository repo;

  setUp(() {
    // Use in-memory SQLite for tests
    db = sqlite3.openInMemory();
    repo = TagTranslationRepository(db: db)..initialize();

    // Import from the actual CSV file
    final csvData = File('assets/danbooru-10w-zh_cn.csv').readAsStringSync();
    repo.importFromCsv(csvData);

    TagTranslation.setRepository(repo);
  });

  tearDown(() {
    db.close();
  });

  group('TagTranslation', () {
    test('loads assets and translates tags correctly', () {
      print('Value for 1girl: ${TagTranslation.translate('1girl')}');
      print('Value for solo: ${TagTranslation.translate('solo')}');
      print('Value for highres: ${TagTranslation.translate('highres')}');

      // Basic tags translation checks
      expect(TagTranslation.translate('1girl'), '单人女性');
      expect(TagTranslation.translate('solo'), '单人');
      expect(TagTranslation.translate('highres'), '高分辨率');
    });

    test('translates with underscore/space normalization', () {
      // Tags stored as underscored should be found with spaces and vice versa
      expect(TagTranslation.translate('long_hair'), isNotNull);
      expect(TagTranslation.translate('long hair'), isNotNull);
      expect(
        TagTranslation.translate('long_hair'),
        TagTranslation.translate('long hair'),
      );
    });

    test('searchLocal matches English with relevance sorting', () {
      final matches = TagTranslation.searchLocal('cat');
      expect(matches.isNotEmpty, true);

      // Matches starting with "cat" (Bucket A) or word boundary (Bucket B) should rank first
      final firstMatchEn = matches.first.value.toLowerCase();
      expect(
        firstMatchEn.startsWith('cat') ||
            firstMatchEn.contains('_cat') ||
            firstMatchEn.contains(' cat'),
        true,
      );

      // Verify that substring matches like "application" do not rank higher than prefix matches
      final applicationIndex = matches.indexWhere(
        (e) => e.value == 'application',
      );
      final catIndex = matches.indexWhere((e) => e.value == 'cat');

      if (applicationIndex != -1 && catIndex != -1) {
        expect(catIndex < applicationIndex, true);
      }
    });

    test('searchLocal matches Chinese queries', () {
      final matches = TagTranslation.searchLocal('单人');
      expect(matches.isNotEmpty, true);
      expect(matches.any((e) => e.value == 'solo'), true);
    });

    test('searchLocal supports pagination', () {
      final page1 = TagTranslation.searchLocal('girl', limit: 5);
      final page2 = TagTranslation.searchLocal('girl', skip: 5, limit: 5);

      expect(page1.length, 5);
      expect(page2.isNotEmpty, true);
      // Pages should not overlap
      final page1Values = page1.map((e) => e.value).toSet();
      final page2Values = page2.map((e) => e.value).toSet();
      expect(page1Values.intersection(page2Values).isEmpty, true);
    });

    test('translate returns null for unknown tags', () {
      expect(TagTranslation.translate('zzznonexistent_tag_12345'), isNull);
    });

    test(
      'needsImport returns false after successful import with current version',
      () {
        expect(repo.needsImport, false);
        expect(db.userVersion, TagTranslationRepository.currentVersion);
      },
    );

    test(
      'needsImport detects outdated database version and updates correctly',
      () {
        // Simulate an older database version (version 0 or 1)
        db.userVersion = 0;
        expect(repo.needsImport, true);

        // Clear and re-import
        repo.clearAndImportFromCsv('test_tag,测试标签\n1girl,单人女性');
        expect(repo.needsImport, false);
        expect(db.userVersion, TagTranslationRepository.currentVersion);
        expect(repo.translate('test_tag'), '测试标签');
        expect(repo.translate('1girl'), '单人女性');
      },
    );
  });
}
