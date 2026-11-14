/// Les routes toutes faites de Technas Pay pour un serveur shelf (et Dart Frog, par
/// `fromShelfHandler`).
///
/// ```dart
/// final routes = pay.appRoutes<MonUser>(authorize: ..., resolveOrder: ...);
/// final router = Router()..mount('/api/technas-pay/', technasPayShelfHandler(routes));
/// ```
library;

import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'src/app_routes.dart';

export 'src/app_routes.dart';

/// Un [Handler] shelf pour [routes]. Montez-le sous un préfixe (`/api/technas-pay/`) :
/// `request.url` y est relatif, c'est le chemin que lit le contrat.
Handler technasPayShelfHandler(AppRoutes routes) {
  return (Request request) async {
    final r = await routes.handle(AppRequest(
      method: request.method,
      path: '/${request.url.path}',
      query: request.url.queryParameters,
      headers: {for (final e in request.headers.entries) e.key.toLowerCase(): e.value},
      rawBody: request.method == 'GET' ? '' : await request.readAsString(),
      original: request,
    ));
    return Response(r.status, body: jsonEncode(r.body), headers: {'content-type': 'application/json'});
  };
}
