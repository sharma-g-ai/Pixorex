/// A vessel that paint cans are stocked onto and unstocked from.
class Vessel {
  const Vessel({required this.id, required this.name});

  /// Stable id stored on every delivery note and check-out. Never reuse one.
  final String id;
  final String name;
}

/// The vessel list is fixed by the team for now. The names are placeholders
/// until the real list arrives; later the browser dashboard will manage it.
/// `vessel-1` must stay first: delivery notes saved before vessels existed
/// belong to it.
const seastockVessels = [
  Vessel(id: 'vessel-1', name: 'Vessel 1'),
  Vessel(id: 'vessel-2', name: 'Vessel 2'),
  Vessel(id: 'vessel-3', name: 'Vessel 3'),
];
