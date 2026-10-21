import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/models.dart';
import 'package:watch_overwatch/core/support.dart';

void main() {
  tearDown(() => rankNames = null);

  test('a rank with a tier uses it as given', () {
    const r = Rank('Emerald', 4, null, 2600);
    expect(r.tierKey(), 'Emerald');
    expect(r.divisionOrRating(), 4);
  });

  test(
    'a rank with only a rating (borrowed from another role) still finds its tier',
    () {
      // Before: no tier, so no emblem; only the label “翡翠 4” was shown.
      const r = Rank(null, null, null, 2600);
      expect(r.tierKey(), 'Emerald');
      expect(r.divisionOrRating(), 4);
      expect(r.label, ratingLabel(2600));
    },
  );

  test('ratings on the ladder edges', () {
    expect(ratingTier(2000), ('Platinum', 5));
    expect(ratingTier(2499), ('Platinum', 1));
    expect(ratingTier(5000), ('Champion', 1));
    expect(ratingTier(499), isNull);
    expect(const Rank(null, null, null, null).tierKey(), isNull);
  });

  test('the top normal tier is 英杰', () {
    expect(const Rank('Champion', 1, null, 4900).label, '英杰1');
    expect(ratingLabel(4600), '英杰4');
  });

  test('Stadium ranks use the Stadium ladder’s own names', () {
    expect(const Rank('Bronze', 2, null, null).labelOn(stadium: true), '菜鸟2');
    expect(const Rank('Platinum', 3, null, null).labelOn(stadium: true), '精英3');
    expect(const Rank('Master', 1, null, null).labelOn(stadium: true), '全明星1');
    expect(
      const Rank('Grandmaster', 1, null, null).labelOn(stadium: true),
      '传奇1',
    );
    // The same tier key on the normal ladder keeps its normal name.
    expect(const Rank('Platinum', 3, null, null).label, '白金3');
  });

  test('a Stadium rating is not turned into a tier on the normal scale', () {
    const r = Rank(null, null, null, 2600);
    expect(r.labelOn(stadium: true), '段位分 2600');
    expect(r.tierKey(stadium: true), isNull);
    expect(ratingLabel(2600, stadium: true), isNull);
  });

  test('names come from the catalog when it has them', () {
    final catalog = Catalog({
      'icons': {
        'rank_names': {'Champion': '英杰（目录）'},
        'rank_names_stadium': {'Gold': '斗士（目录）'},
      },
    });
    rankNames = catalog.rankName;
    expect(const Rank('Champion', 1, null, null).label, '英杰（目录）1');
    expect(const Rank('Gold', 2, null, null).labelOn(stadium: true), '斗士（目录）2');
    // A tier the catalog does not name falls back to the string table.
    expect(const Rank('Gold', 2, null, null).label, '黄金2');
  });

  test('Stadium upgrades are looked up by official id', () {
    final catalog = Catalog({
      'stadium_upgrades': {
        '0x0CC800000000099B': {
          'name': '邪恶飞翼',
          'icon': 'https://example.com/a.png',
          'desc': '[幽灵形态]激活时可以自由飞行，移动速度提高{20%}',
          'category': '生存',
          'level': '史诗',
        },
      },
    });
    const ref = EntityRef(
      'stadium_upgrade',
      '922337203685479835',
      null,
      '0x0CC800000000099B',
    );
    final u = catalog.stadiumUpgrade(ref)!;
    expect(u.name, '邪恶飞翼');
    expect(u.icon, 'https://example.com/a.png');
    expect(u.category, '生存');
    expect(u.rarity, '史诗');
    expect(u.plainText, '幽灵形态激活时可以自由飞行，移动速度提高20%');
    expect(
      catalog.stadiumUpgrade(
        const EntityRef('stadium_upgrade', '1', null, '0x0CC8000000000001'),
      ),
      isNull,
    );
  });
}
