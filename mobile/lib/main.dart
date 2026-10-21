import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'core/auth_tokens.dart';
import 'core/device_id.dart';
import 'core/oidc_client.dart';
import 'core/secure_store.dart';
import 'features/auth/invite_repository.dart';
import 'features/auth/session_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  const store = PlatformSecureStore();
  final session = SessionController(oidc: AppAuthOidcClient(), tokens: TokenStore(store));
  final api = ApiClient(
    http: http.Client(),
    deviceId: DeviceIdStore(store),
    accessToken: session.accessToken,
  );
  session.api = api;

  runApp(
    ChangeNotifierProvider<SessionController>.value(
      value: session,
      child: PixorexApp(invites: InviteRepository(api), linkSource: AppLinksSource()),
    ),
  );
}
