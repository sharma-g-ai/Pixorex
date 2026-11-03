import 'package:flutter_test/flutter_test.dart';
import 'package:pixorex_mobile/core/secure_store.dart';
import 'package:pixorex_mobile/features/scan/capture_models.dart';
import 'package:pixorex_mobile/features/scan/location_pick.dart';

const facility = LocationLevel(levelId: 'L1', name: 'Facility', order: 1, requirement: 'required');
const building = LocationLevel(levelId: 'L2', name: 'Building', order: 2, requirement: 'required');
const shop = LocationLevel(levelId: 'L3', name: 'Shop', order: 3, requirement: 'optional');
const bin = LocationLevel(levelId: 'L4', name: 'Bin', order: 4, requirement: 'required');
const subBin = LocationLevel(levelId: 'L5', name: 'Sub-bin', order: 5, requirement: 'optional');

LocationNode n(String id, LocationLevel l, [List<LocationNode> children = const []]) =>
    LocationNode(nodeId: id, levelId: l.levelId, name: id, children: children);

/// Plant 04 › Building C › Paint Shop › Bin 05 (A, B) / Bin 07 (B)
///                       › Bin 09 (no shop, no sub-bins)
final tree = LocationTree(levels: const [facility, building, shop, bin, subBin], roots: [
  n('Plant 04', facility, [
    n('Building C', building, [
      n('Paint Shop', shop, [
        n('Bin 05', bin, [n('A', subBin), n('B', subBin)]),
        n('Bin 07', bin, [n('B7', subBin)]),
      ]),
      n('Bin 09', bin),
    ]),
  ]),
]);

void main() {
  group('LocationPick', () {
    test('GIVEN one facility WHEN starting fresh THEN it is picked and the building is next', () {
      final p = LocationPick.start(tree);
      expect(p.nodeIds, ['Plant 04']);
      expect(p.nextLevel, building);
      expect(p.isComplete, isFalse);
    });

    test('GIVEN a building WHEN listing options THEN shops and bins that skip the optional shop', () {
      final p = LocationPick.start(tree).choose(tree.roots.single.children.single);
      expect(p.optionsAt(shop).map((x) => x.name), ['Paint Shop']);
      expect(p.optionsAt(bin).map((x) => x.name), ['Bin 09']);
      expect(p.nextLevel, shop);
    });

    test('GIVEN a bin under the shop WHEN picked THEN complete, sub-bin still offered', () {
      var p = LocationPick.start(tree);
      p = p.choose(p.optionsAt(building).single);
      p = p.choose(p.optionsAt(shop).single);
      p = p.choose(p.optionsAt(bin).first);
      expect(p.isComplete, isTrue);
      expect(p.nextLevel, subBin);
      p = p.choose(p.optionsAt(subBin).first);
      expect(p.title, 'Bin 05 · A');
      expect(p.context, 'Plant 04 › Building C › Paint Shop');
      expect(p.nextLevel, isNull);
    });

    test('GIVEN a bin with no shop WHEN picked THEN complete and the shop row stays empty', () {
      var p = LocationPick.start(tree);
      p = p.choose(p.optionsAt(building).single);
      p = p.choose(p.optionsAt(bin).single);
      expect(p.isComplete, isTrue);
      expect(p.nodeAt(shop), isNull);
      expect(p.title, 'Bin 09');
    });

    test('GIVEN a full pick WHEN a higher level changes THEN lower picks are cleared', () {
      var p = LocationPick.start(tree, remembered: ['Plant 04', 'Building C', 'Paint Shop', 'Bin 05', 'A']);
      expect(p.title, 'Bin 05 · A');
      p = p.choose(p.optionsAt(bin)[1]);
      expect(p.nodeIds, ['Plant 04', 'Building C', 'Paint Shop', 'Bin 07']);
      expect(p.nodeAt(subBin), isNull);
    });

    test('GIVEN a remembered path no longer in the tree WHEN starting THEN start at the facility', () {
      final p = LocationPick.start(tree, remembered: ['Plant 04', 'Building X']);
      expect(p.nodeIds, ['Plant 04']);
    });

    test('GIVEN several top nodes WHEN starting fresh THEN nothing is picked yet', () {
      final two = LocationTree(levels: tree.levels, roots: [n('Plant 04', facility), n('Plant 05', facility)]);
      final p = LocationPick.start(two);
      expect(p.chain, isEmpty);
      expect(p.optionsAt(facility), hasLength(2));
    });
  });

  group('LastLocationStore', () {
    test('GIVEN a saved location WHEN read THEN ids and time come back per unit', () async {
      final store = LastLocationStore(MemorySecureStore());
      await store.save('b1', ['Plant 04', 'Bin 09'], DateTime.utc(2026, 11, 3, 9));
      final back = await store.read('b1');
      expect(back?.nodeIds, ['Plant 04', 'Bin 09']);
      expect(back?.usedAt, DateTime.utc(2026, 11, 3, 9));
      expect(await store.read('b2'), isNull);
    });

    test('GIVEN corrupt data WHEN read THEN it is dropped, not thrown', () async {
      final mem = MemorySecureStore()..values['last_location.b1'] = 'nope';
      expect(await LastLocationStore(mem).read('b1'), isNull);
      expect(mem.values, isEmpty);
    });
  });
}
