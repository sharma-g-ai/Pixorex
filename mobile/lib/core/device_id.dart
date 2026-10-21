import 'package:uuid/uuid.dart';

import 'secure_store.dart';

/// `X-Device-Id`: made once per install and kept (docs/mobile-api.md section 3).
class DeviceIdStore {
  DeviceIdStore(this._store);
  final SecureStore _store;
  static const _key = 'device_id';
  String? _cached;

  Future<String> get() async {
    if (_cached != null) return _cached!;
    var id = await _store.read(_key);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await _store.write(_key, id);
    }
    return _cached = id;
  }
}
