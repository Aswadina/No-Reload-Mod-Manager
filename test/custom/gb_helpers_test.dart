import 'package:flutter_test/flutter_test.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_helpers.dart';

void main() {
  group('pageWindow', () {
    test('few pages show them all', () {
      expect(pageWindow(1, 1), [1]);
      expect(pageWindow(2, 5), [1, 2, 3, 4, 5]);
      expect(pageWindow(1, 0), <int?>[]);
    });

    test('first page, many pages', () {
      expect(pageWindow(1, 663), [1, 2, 3, null, 663]);
    });

    test('middle page keeps neighbours, first and last', () {
      expect(pageWindow(300, 663), [1, null, 299, 300, 301, null, 663]);
    });

    test('a gap of exactly one page shows that page instead of dots', () {
      expect(pageWindow(4, 10), [1, 2, 3, 4, 5, null, 10]);
      expect(pageWindow(7, 10), [1, null, 6, 7, 8, 9, 10]);
    });

    test('last page', () {
      expect(pageWindow(663, 663), [1, null, 661, 662, 663]);
    });
  });

  test('ageLabel', () {
    final now = DateTime.utc(2026, 11, 19, 12);
    int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch ~/ 1000;
    expect(ageLabel(ago(const Duration(hours: 5)), now: now), 'today');
    expect(ageLabel(ago(const Duration(days: 1, hours: 1)), now: now), '1d ago');
    expect(ageLabel(ago(const Duration(days: 12)), now: now), '12d ago');
    expect(ageLabel(ago(const Duration(days: 75)), now: now), '2mo ago');
    expect(ageLabel(ago(const Duration(days: 800)), now: now), '2y ago');
    expect(ageLabel(null, now: now), '');
    // A date in the future (clock skew) must not show a negative age.
    expect(ageLabel(ago(const Duration(days: -3)), now: now), 'today');
  });

  test('formatCount', () {
    expect(formatCount(0), '0');
    expect(formatCount(999), '999');
    expect(formatCount(1000), '1k');
    expect(formatCount(1234), '1.2k');
    expect(formatCount(15400), '15k');
    expect(formatCount(2500000), '2.5M');
  });

  test('searchTermForGroup trims descriptions off a group name', () {
    expect(searchTermForGroup('Raiden Shogun'), 'Raiden Shogun');
    expect(searchTermForGroup('Mavuika - Nord Express'), 'Mavuika');
    expect(searchTermForGroup('Hu Tao (old)'), 'Hu Tao');
    expect(searchTermForGroup('  [WIP] Furina '), 'Furina');
    expect(searchTermForGroup('group_12'), 'group_12');
  });

  group('suggestGroups', () {
    const raiden = GbGroupCandidate(path: 'g1', name: 'Raiden Shogun', isUi: false);
    const hutao = GbGroupCandidate(path: 'g2', name: 'Hu Tao', isUi: false);
    const ui = GbGroupCandidate(path: 'g3', name: 'Interface', isUi: true);
    const all = [hutao, raiden, ui];

    test('name match is suggested with a reason', () {
      final s = suggestGroups(
        modName: 'Raiden Shogun - Elegant Outfit',
        categoryName: 'Skins',
        tags: const [],
        groups: all,
      );
      expect(s.first.group.path, 'g1');
      expect(s.first.reason, contains('Raiden'));
    });

    test('character tag matches too', () {
      final s = suggestGroups(
        modName: 'Winter outfit',
        categoryName: 'Skins',
        tags: const ['Character: Hu Tao'],
        groups: all,
      );
      expect(s.first.group.path, 'g2');
    });

    test('UI category suggests a UI group', () {
      final s = suggestGroups(
        modName: 'Clean minimap',
        categoryName: 'UI',
        tags: const [],
        groups: all,
      );
      expect(s.single.group.path, 'g3');
      expect(s.single.reason, contains('UI'));
    });

    test('no match suggests nothing', () {
      expect(
        suggestGroups(
          modName: 'Something else',
          categoryName: 'Skins',
          tags: const [],
          groups: all,
        ),
        isEmpty,
      );
    });

    test('short or generic words do not cause false matches', () {
      const generic = GbGroupCandidate(path: 'g9', name: 'The Mod Skin', isUi: false);
      expect(
        suggestGroups(
          modName: 'The best mod skin ever',
          categoryName: 'Skins',
          tags: const [],
          groups: const [generic],
        ),
        isEmpty,
      );
    });
  });
}
