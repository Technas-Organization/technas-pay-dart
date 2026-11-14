// Le client rejoue contract/app-contract.v1.json, le même fichier que les SDK serveur Node,
// Python et Dart : pour chaque cas, le serveur rend la réponse attendue, et le client doit
// envoyer la bonne requête et lire la réponse comme prévu.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:technas_pay_flutter/technas_pay_flutter.dart';

final contract = jsonDecode(File('../contract/app-contract.v1.json').readAsStringSync()) as Map<String, dynamic>;
final cases = (contract['cases'] as List).cast<Map<String, dynamic>>();

void main() {
  for (final c in cases) {
    final req = c['request'] as Map;
    final path = req['path'] as String;
    final method = req['method'] as String;
    // Le client n'appelle que les routes du contrat (pas de route inconnue côté app).
    if (!(path == '/methods' || path.startsWith('/payments') || path.startsWith('/card/'))) continue;

    test('contrat (client) : ${c['name']}', () async {
      final expected = c['expect'] as Map;
      late http.Request sent;
      final client = TechnasPayClient(
        baseUrl: 'https://api.partenaire.test/api/technas-pay/',
        headers: () async => {'Authorization': 'Bearer session'},
        client: MockClient((r) async {
          sent = r;
          return http.Response(jsonEncode(expected['body']), expected['status'] as int,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );
      final status = expected['status'] as int;
      final body = expected['body'] as Map;

      Future<Object> call() async {
        if (path == '/methods') return client.methods((req['query'] as Map)['orderId'] as String);
        if (path == '/card/account') return client.cardAccount();
        if (path == '/card/onboarding') {
          final b = req['body'] as Map;
          return client.startCardOnboarding(
              returnUrl: b['returnUrl'] as String, refreshUrl: b['refreshUrl'] as String, country: b['country'] as String?);
        }
        if (method == 'POST') return client.startPayment((req['body'] as Map).cast<String, Object?>());
        return client.readPayment(path.substring('/payments/'.length));
      }

      if (status >= 400) {
        await expectLater(
            call(),
            throwsA(isA<TechnasBackendException>()
                .having((e) => e.status, 'status', status)
                .having((e) => e.code, 'code', body['code'])
                .having((e) => e.retryable, 'retryable', body['retryable'])));
      } else {
        final result = await call();
        if (result is TechnasPaymentState) {
          final p = body['payment'] as Map;
          expect(result.id, p['id']);
          expect(result.reference, p['reference']);
          expect(result.status, p['status']);
          expect(result.checkoutUrl, p['checkout_url']);
          expect(result.amount, p['amount']);
          expect(result.currency, p['currency']);
          expect(result.expiresAt, p['expires_at'] == null ? null : DateTime.parse(p['expires_at'] as String));
          expect(result.method, p['method']);
        } else if (result is TechnasCardAccount || result is TechnasCardOnboarding) {
          final account = result is TechnasCardOnboarding ? result.account : result as TechnasCardAccount;
          final a = (body['account'] as Map);
          expect(account.status, a['status']);
          expect(account.canAcceptPayments, a['can_accept_payments']);
          if (result is TechnasCardOnboarding) {
            expect(result.url, body['url']);
            expect(result.kind, body['kind']);
          }
        } else {
          final m = result as TechnasPayMethods;
          expect(m.amount, body['amount']);
          expect(m.methods.map((x) => [x.method, x.available, x.reason]).toList(),
              (body['methods'] as List).map((x) => [x['method'], x['available'], x['reason']]).toList());
          expect(m.available.map((x) => x.method),
              (body['methods'] as List).where((x) => x['available'] == true).map((x) => x['method']).toList());
        }
      }

      // La requête envoyée est celle du contrat, avec la session de l'utilisateur.
      expect(sent.method, method);
      expect(sent.url.path, '/api/technas-pay$path');
      if (req['query'] != null) expect(sent.url.queryParameters, (req['query'] as Map).cast<String, String>());
      if (req['body'] != null) expect(jsonDecode(sent.body), req['body']);
      expect(sent.headers['Authorization'], 'Bearer session');
    });
  }

  test('l\'ancien TechnasPayHttpBackend garde ses chemins /technas-pay/payments', () async {
    late Uri seen;
    final backend = TechnasPayHttpBackend(
      baseUrl: 'https://x.test/',
      client: MockClient((r) async {
        seen = r.url;
        return http.Response('{"payment":{"id":"p","status":"pending"}}', 200);
      }),
    );
    await backend.startPayment({'orderId': '1'});
    expect(seen.path, '/technas-pay/payments');
  });
}
