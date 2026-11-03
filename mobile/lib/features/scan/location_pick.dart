import 'dart:convert';

import '../../core/secure_store.dart';
import 'capture_models.dart';

/// The technician's walk down the published tree (design 41-45). Rules follow the API:
/// a node's children may skip optional levels but never a required one, and a location
/// is complete once it reaches the deepest required level.
class LocationPick {
  LocationPick(this.tree, [List<LocationNode> chain = const []]) : chain = List.unmodifiable(chain);

  /// Starts at the facility when the unit has one top node ("Facility comes from your
  /// business unit"), or at [remembered] node ids when they are still in the tree.
  factory LocationPick.start(LocationTree tree, {List<String>? remembered}) {
    final path = remembered == null ? null : _pathOf(tree.roots, remembered);
    if (path != null) return LocationPick(tree, path);
    return LocationPick(tree, tree.roots.length == 1 ? [tree.roots.single] : const []);
  }

  /// Starts at [nodeId] (a retake keeps the old scan's place), if it is still published.
  factory LocationPick.at(LocationTree tree, String nodeId) {
    final path = _pathTo(tree.roots, nodeId);
    return path == null ? LocationPick.start(tree) : LocationPick(tree, path);
  }

  final LocationTree tree;

  /// Picked nodes, top first; each is a child of the one before.
  final List<LocationNode> chain;

  int _order(String levelId) => tree.levels.firstWhere((l) => l.levelId == levelId).order;

  LocationNode? nodeAt(LocationLevel level) => chain.where((n) => n.levelId == level.levelId).firstOrNull;

  /// Nodes that can be picked at [level] under what is picked above it.
  List<LocationNode> optionsAt(LocationLevel level) {
    final above = chain.where((n) => _order(n.levelId) < level.order).lastOrNull;
    final pool = above == null ? tree.roots : above.children;
    return pool.where((n) => n.levelId == level.levelId).toList();
  }

  /// Picks [node] and clears everything below it (a lower pick may no longer fit).
  LocationPick choose(LocationNode node) =>
      LocationPick(tree, [...chain.where((n) => _order(n.levelId) < _order(node.levelId)), node]);

  int get _deepestRequired =>
      tree.levels.where((l) => l.requirement == 'required').map((l) => l.order).fold(0, (a, b) => a > b ? a : b);

  bool get isComplete => chain.isNotEmpty && _order(chain.last.levelId) >= _deepestRequired;

  /// The next level to pick, top first, or null when nothing is left to pick.
  LocationLevel? get nextLevel => tree.levels.where((l) => nodeAt(l) == null && optionsAt(l).isNotEmpty).firstOrNull;

  /// "Bin 07 · B": the picks from the deepest required level down.
  String get title => chain.where((n) => _order(n.levelId) >= _deepestRequired).map((n) => n.name).join(' · ');

  /// "Plant 04 › Building C › Paint Shop": the picks above [title].
  String get context => chain.where((n) => _order(n.levelId) < _deepestRequired).map((n) => n.name).join(' › ');

  List<String> get nodeIds => chain.map((n) => n.nodeId).toList();

  static List<LocationNode>? _pathTo(List<LocationNode> nodes, String id) {
    for (final n in nodes) {
      if (n.nodeId == id) return [n];
      final below = _pathTo(n.children, id);
      if (below != null) return [n, ...below];
    }
    return null;
  }

  static List<LocationNode>? _pathOf(List<LocationNode> nodes, List<String> ids) {
    if (ids.isEmpty) return null;
    final head = nodes.where((n) => n.nodeId == ids.first).firstOrNull;
    if (head == null) return null;
    if (ids.length == 1) return [head];
    final rest = _pathOf(head.children, ids.sublist(1));
    return rest == null ? null : [head, ...rest];
  }
}

/// Last location used in each unit, kept on the phone ("we remember it for next time").
class LastLocationStore {
  LastLocationStore(this._store);
  final SecureStore _store;

  String _key(String buId) => 'last_location.$buId';

  Future<LastLocation?> read(String buId) async {
    final raw = await _store.read(_key(buId));
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return LastLocation(
        (j['node_ids'] as List).cast<String>(),
        DateTime.parse(j['used_at'] as String),
      );
    } catch (_) {
      await _store.delete(_key(buId));
      return null;
    }
  }

  Future<void> save(String buId, List<String> nodeIds, DateTime usedAt) => _store.write(
        _key(buId),
        jsonEncode({'node_ids': nodeIds, 'used_at': usedAt.toUtc().toIso8601String()}),
      );
}

class LastLocation {
  const LastLocation(this.nodeIds, this.usedAt);
  final List<String> nodeIds;
  final DateTime usedAt;
}
