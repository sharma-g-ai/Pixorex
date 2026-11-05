import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/ppg_session_controller.dart';

/// Route name of the Delivery notes hub, so finished flows can return to it.
const ppgHubRouteName = '/ppg/delivery-notes';

/// Pushes a PPG screen with the shared session controller in scope.
Future<T?> ppgPush<T>(
  BuildContext context,
  PpgSessionController controller,
  Widget screen, {
  bool replace = false,
}) {
  final route = MaterialPageRoute<T>(
    builder: (_) =>
        ChangeNotifierProvider.value(value: controller, child: screen),
  );
  return replace
      ? Navigator.of(context).pushReplacement<T, void>(route)
      : Navigator.of(context).push<T>(route);
}

/// Returns to the Delivery notes hub (or the first route if it is absent).
void ppgPopToHub(BuildContext context) {
  Navigator.of(context).popUntil(
    (route) => route.settings.name == ppgHubRouteName || route.isFirst,
  );
}
