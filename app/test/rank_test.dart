import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/models.dart';

void main() {
  test('a rank with a tier uses it as given', () {
    const r = Rank('Emerald', 4, null, 2600);
    expect(r.tierKey, 'Emerald');
    expect(r.divisionOrRating, 4);
  });

  test(
    'a rank with only a rating (borrowed from another role) still finds its tier',
    () {
      // Before: no tier, so no emblem; only the label “翡翠 4” was shown.
      const r = Rank(null, null, null, 2600);
      expect(r.tierKey, 'Emerald');
      expect(r.divisionOrRating, 4);
      expect(r.label, ratingLabel(2600));
    },
  );

  test('ratings on the ladder edges', () {
    expect(ratingTier(2000), ('Platinum', 5));
    expect(ratingTier(2499), ('Platinum', 1));
    expect(ratingTier(5000), ('Champion', 1));
    expect(ratingTier(499), isNull);
    expect(const Rank(null, null, null, null).tierKey, isNull);
  });
}
