/// Pulls the invite token out of a link that opened the app.
///
/// PROVISIONAL: how the invite link opens the app is not decided yet
/// (docs/handover.md section 2). Until it is, the app accepts
/// `pixorex://activate#token=...` (the same fragment form as the web link,
/// D-11) and `pixorex://activate?token=...`. Update with the agreed format.
String? parseInviteToken(Uri uri) {
  if (uri.host != 'activate' && !uri.path.contains('activate')) return null;
  final fromFragment = uri.fragment.isEmpty ? null : Uri.splitQueryString(uri.fragment)['token'];
  final token = fromFragment ?? uri.queryParameters['token'];
  return (token == null || token.isEmpty) ? null : token;
}
