// Rejoue contract/app-contract.v1.json : le même fichier que le client Flutter et les SDK Node et
// Python. Puis l'adaptateur shelf monté sous un préfixe.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:technas_pay/shelf.dart';
import 'package:technas_pay/technas_pay.dart';
import 'package:test/test.dart';

const webhookSecret = 'ws_secret';
const secret = 'tps_test_pk_abc.$webhookSecret';

final contract = jsonDecode(File('contract/app-contract.v1.json').readAsStringSync()) as Map<String, dynamic>;
final cases = (contract['cases'] as List).cast<Map<String, dynamic>>();

class Gateway {
  Gateway(List responses) : queue = [...responses];
  final List queue;
  final calls = <Map<String, Object?>>[];

  MockClient get client => MockClient((r) async {
        calls.add({'method': r.method, 'path': r.url.path, 'body': r.body.isEmpty ? null : jsonDecode(r.body)});
        if (queue.isEmpty) fail('appel imprévu à la passerelle');
        final next = queue.removeAt(0) as Map;
        if (next['body'] == null) return http.Response('<html>panne</html>', next['status'] as int);
        return http.Response(jsonEncode(next['body']), next['status'] as int, headers: {'content-type': 'application/json'});
      });
}

AppOrder? _order(Map<String, dynamic> c, String id) {
  final o = (c['orders'] as Map)[id] as Map?;
  if (o == null) return null;
  return AppOrder(amount: o['amount'] as num, currency: o['currency'] as String?, customer: (o['customer'] as Map).cast<String, String>());
}

AppRoutes<String> routesFor(Map<String, dynamic> c, TechnasPay pay, {WebhookHandlers? webhooks}) => pay.appRoutes<String>(
      authorize: (_) async => c['user'] as String?,
      resolveOrder: (id, user) => user == c['user'] ? _order(c, id) : null,
      returnUrl: 'https://app.test/retour',
      webhooks: webhooks,
      card: ((c['options'] as Map?)?['card'] as bool?) ?? false,
      authorizeAdmin: c.containsKey('admin') ? (_) => c['admin'] : null,
    );

void main() {
  for (final c in cases) {
    test('contrat : ${c['name']}', () async {
      final gw = Gateway(c['gateway'] as List);
      final pay = TechnasPay(secret: secret, baseUrl: 'https://gw.test', httpClient: gw.client);
      final req = c['request'] as Map;
      final r = await routesFor(c, pay).handle(AppRequest(
        method: req['method'] as String,
        path: req['path'] as String,
        query: ((req['query'] as Map?) ?? {}).cast<String, String>(),
        rawBody: req.containsKey('body') ? jsonEncode(req['body']) : '',
      ));
      final expect_ = c['expect'] as Map;
      expect(r.status, expect_['status']);
      final body = jsonDecode(jsonEncode(r.body)) as Map;
      if (r.status >= 400) expect(body.remove('message'), isA<String>());
      expect(body, expect_['body']);
      final exp = c['expect_gateway'] as List;
      expect(gw.calls, hasLength(exp.length));
      for (var i = 0; i < exp.length; i++) {
        expect(gw.calls[i]['method'], exp[i]['method']);
        expect(gw.calls[i]['path'], exp[i]['path']);
        ((exp[i]['body_includes'] as Map?) ?? {}).forEach((k, v) => expect((gw.calls[i]['body'] as Map)[k], v, reason: '$k'));
      }
    });
  }

  test('webhook : signé → vos fonctions ; mauvaise signature → 400 ; non branché → 404', () async {
    final paid = <String>[];
    final c = {'user': 'u1', 'orders': <String, Object?>{}};
    final pay = TechnasPay(secret: secret);
    final routes = routesFor(c, pay, webhooks: WebhookHandlers(onCompleted: (e) => paid.add(e.payment!.reference)));
    final body = jsonEncode({
      'id': 'e1',
      'type': 'payment.completed',
      'created_at': 'x',
      'data': {'id': 'p', 'reference': '42-1', 'status': 'completed', 'amount': 1, 'currency': 'XOF'},
    });
    final ok = await routes
        .handle(AppRequest(method: 'POST', path: '/webhook', headers: {signatureHeader: sign(body, webhookSecret)}, rawBody: body));
    expect(ok.status, 200);
    expect(paid, ['42-1']);
    final bad = await routes.handle(AppRequest(method: 'POST', path: '/webhook', headers: {signatureHeader: 't=1,s=00'}, rawBody: body));
    expect(bad.status, 400);
    final none = await routesFor(c, pay).handle(AppRequest(method: 'POST', path: '/webhook', rawBody: body));
    expect(none.status, 404);
  });

  test('shelf : monté sous /api/technas-pay/, en-têtes passés à authorize', () async {
    final c = cases.first;
    final gw = Gateway(c['gateway'] as List);
    String? seen;
    final pay = TechnasPay(secret: secret, baseUrl: 'https://gw.test', httpClient: gw.client);
    final handler = technasPayShelfHandler(pay.appRoutes<String>(
      authorize: (req) {
        seen = req.headers['authorization'];
        return 'u1';
      },
      resolveOrder: (id, _) => _order(c, id),
    ));
    final res = await handler(shelf.Request(
      'POST',
      Uri.parse('http://x/api/technas-pay/payments'),
      handlerPath: '/api/technas-pay/',
      body: jsonEncode({'orderId': '42'}),
      headers: {'Authorization': 'Bearer jeton'},
    ));
    expect(res.statusCode, 200);
    expect(jsonDecode(await res.readAsString()), (c['expect'] as Map)['body']);
    expect(seen, 'Bearer jeton');
  });
}
