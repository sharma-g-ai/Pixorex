/// What the technician picks before capturing: equipment types (contract 2.10) and the
/// published location tree (contract 2.9).
library;

/// One field of an equipment type (contract 2.10 with `include=fields`).
class TypeField {
  const TypeField({
    required this.fieldKey,
    required this.label,
    required this.dataType,
    required this.isRequired,
    required this.isCritical,
    this.options,
  });
  final String fieldKey;
  final String label;
  final String dataType;
  final bool isRequired;
  final bool isCritical;
  final List<String>? options;

  factory TypeField.fromJson(Map<String, dynamic> j) => TypeField(
        fieldKey: j['field_key'] as String,
        label: j['label'] as String,
        dataType: j['data_type'] as String,
        isRequired: j['is_required'] as bool,
        isCritical: j['is_critical'] as bool,
        options: (j['options'] as List?)?.map((e) => e.toString()).toList(),
      );
}

class EquipmentType {
  const EquipmentType({required this.typeId, required this.name, this.fields = const []});
  final String typeId;
  final String name;
  final List<TypeField> fields;

  factory EquipmentType.fromJson(Map<String, dynamic> j) => EquipmentType(
        typeId: j['type_id'] as String,
        name: j['name'] as String,
        fields: ((j['fields'] as List?) ?? const [])
            .map((e) => TypeField.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// A node of the published location tree (`tree_snapshot`).
class LocationNode {
  const LocationNode({required this.nodeId, required this.levelId, required this.name, this.children = const []});
  final String nodeId;
  final String levelId;
  final String name;
  final List<LocationNode> children;

  factory LocationNode.fromJson(Map<String, dynamic> j) => LocationNode(
        nodeId: j['node_id'] as String,
        levelId: j['level_id'] as String,
        name: j['name'] as String,
        children: _nodes(j['children']),
      );
}

class LocationLevel {
  const LocationLevel({required this.levelId, required this.name, required this.order, required this.requirement});
  final String levelId;
  final String name;
  final int order;

  /// `required`, `optional` or `off` (an `off` level holds no nodes).
  final String requirement;

  bool get isOptional => requirement == 'optional';

  factory LocationLevel.fromJson(Map<String, dynamic> j) => LocationLevel(
        levelId: j['level_id'] as String,
        name: j['level_name'] as String,
        order: j['level_order'] as int,
        requirement: j['requirement'] as String,
      );
}

class LocationTree {
  const LocationTree({required this.levels, required this.roots});

  /// Levels in use, top first.
  final List<LocationLevel> levels;
  final List<LocationNode> roots;

  factory LocationTree.fromJson(Map<String, dynamic> j) {
    final snapshot = (j['tree_snapshot'] as Map<String, dynamic>?) ?? const {};
    return LocationTree(
      levels: (j['levels'] as List)
          .map((e) => LocationLevel.fromJson(e as Map<String, dynamic>))
          .where((l) => l.requirement != 'off')
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order)),
      roots: _nodes(snapshot['nodes']),
    );
  }
}

List<LocationNode> _nodes(Object? raw) =>
    ((raw as List?) ?? const []).map((e) => LocationNode.fromJson(e as Map<String, dynamic>)).toList();
