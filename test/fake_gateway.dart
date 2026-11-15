// Faux serveur de la passerelle, en mémoire (MockClient) : une référence = un essai,
// authentification par en-tête, plafond de remboursement, option de change.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const apiKey = 'pk_abc-DEF_123';
const webhookSecret = 'ws_webhook-secret_456';
const secret = 'tps_test_$apiKey.$webhookSecret';
const base = 'https://gw.test';
const risks = {'none': 'Rien.', 'local': 'Vous portez le change.', 'converted': 'Fermé.', 'markup': 'Supplément.'};

http.Response _err(int status, String code, [Map<String, Object?> extra = const {}]) =>
    http.Response(jsonEncode({'code': code, 'message': code, ...extra}), status, headers: {'content-type': 'application/json'});
http.Response _ok(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

class FakeGateway {
  final payments = <String, Map<String, dynamic>>{};
  final requests = <http.Request>[];
  var balance = 0;
  var fxMode = 'none';

  MockClient get client => MockClient(handle);

  Future<http.Response> handle(http.Request r) async {
    requests.add(r);
    final path = r.url.path;
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isNotEmpty && parts[0] == 'test-checkout') {
      final p = payments[parts[1]];
      if (p == null) return http.Response('', 404);
      p['status'] = parts[2];
      if (parts[2] == 'expired') p['checkout_url'] = null;
      if (parts[2] == 'completed') {
        p['currency'] ??= 'XOF';
        balance += p['net_amount'] as int;
        return http.Response('', 303, headers: {'location': 'https://partenaire.test/merci'});
      }
      return http.Response('ok', 200);
    }
    if (r.headers['Authorization'] != 'Bearer $apiKey') return _err(401, 'invalid_api_key');
    final body = r.body.isEmpty ? null : jsonDecode(r.body) as Map<String, dynamic>;
    final q = r.url.queryParameters;
    if (r.method == 'POST' && path == '/v1/payments') {
      final existing = payments.values.where((p) => p['reference'] == body!['reference']).firstOrNull;
      if (existing != null) {
        if (existing['amount'] != body!['amount']) return _err(409, 'reference_conflict');
        if (existing['status'] == 'expired') return _err(409, 'payment_expired');
        return _ok(existing);
      }
      final id = 'pay_${payments.length + 1}';
      final amount = body!['amount'] as int;
      final p = <String, dynamic>{
        'id': id,
        'reference': body['reference'],
        'amount': amount,
        'currency': body['currency'],
        'commission': amount * 2 ~/ 100,
        'net_amount': amount - amount * 2 ~/ 100,
        'status': 'pending',
        'checkout_url': '$base/test-checkout/$id',
        'metadata': body['metadata'],
        'test_mode': true,
        'created_at': '2026-11-14T10:00:00Z',
        'refunded_amount': 0,
      };
      payments[id] = p;
      return _ok(p, 201);
    }
    if (r.method == 'GET' && path == '/v1/payments') {
      final p = payments.values.where((p) => p['reference'] == q['reference']).firstOrNull;
      return p == null ? _err(404, 'payment_not_found') : _ok(p);
    }
    if (parts.length == 3 && parts[1] == 'payments' && r.method == 'GET') {
      final p = payments[parts[2]];
      return p == null ? _err(404, 'payment_not_found') : _ok(p);
    }
    if (parts.length == 4 && parts[1] == 'payments' && r.method == 'POST') {
      final p = payments[parts[2]];
      if (p == null) return _err(404, 'payment_not_found');
      if (p['status'] != 'completed') return _err(409, 'payment_not_refundable');
      final external = parts[3] == 'external-refunds';
      final remaining = (p['amount'] as int) - (p['refunded_amount'] as int);
      final amount = (body!['amount'] as int?) ?? remaining;
      if (amount > remaining) return _err(409, 'refund_exceeds_payment', {'refundable_amount': remaining});
      final fee = external ? 0 : 100;
      final debit = external ? 0 : (body['fees'] == 'customer' ? amount : amount + fee);
      if (debit > balance) return _err(409, 'insufficient_balance', {'missing_amount': debit - balance, 'currency': 'XOF'});
      balance -= debit;
      p['refunded_amount'] = (p['refunded_amount'] as int) + amount;
      return _ok({
        'id': 're_${p['refunded_amount']}',
        'payment_id': p['id'],
        'payment_reference': p['reference'],
        'amount': amount,
        'sent_amount': body['fees'] == 'customer' ? amount - fee : amount,
        'fee': fee,
        'fees': body['fees'] ?? 'partner',
        'balance_debit': debit,
        'currency': 'XOF',
        'status': 'completed',
        'kind': external ? 'external' : 'payout',
        'method': body['method'],
        'created_at': 'x',
      }, 201);
    }
    if (path == '/v1/fx') {
      if (r.method == 'PUT') {
        if (body!['mode'] == 'converted') return _err(409, 'fx_mode_unavailable');
        if (body['mode'] != 'none' && body['accept_risk'] != true) return _err(409, 'risk_not_accepted', {'risk': risks[body['mode']]});
        fxMode = body['mode'] as String;
      }
      return _ok({
        'mode': fxMode,
        'available_modes': ['none', 'local'],
        'home_currency': 'XOF',
        'risks': risks,
        'risk_version': '2026-11',
        'country_rules': {'allowed': null, 'excluded': []},
        'countries': [
          {'country': 'GH', 'name': 'Ghana', 'currency': 'GHS', 'available': false, 'reason': 'no_payout_number', 'rate': 0.0222}
        ],
      });
    }
    if (path == '/v1/balance') {
      return _ok([
        {'currency': 'XOF', 'amount': balance}
      ]);
    }
    if (path == '/v1/settlements') {
      return _ok([
        {'id': 's1', 'amount': 10000, 'fee': 150, 'currency': 'XOF', 'status': 'completed'}
      ]);
    }
    if (path == '/v1/payout-networks') {
      return _ok(q['country'] == 'TG'
          ? [
              {'code': 'moov_tg', 'name': 'Moov Togo', 'currency': 'XOF'}
            ]
          : []);
    }
    if (path == '/v1/payout-destination') {
      return _ok({
        'destinations': [
          {
            'currency': 'XOF',
            'current': null,
            'pending': r.method == 'PUT' ? {...body!, 'currency': 'XOF', 'status': 'awaiting_confirmation'} : null
          }
        ]
      });
    }
    if (path == '/v1/country-rules') return _ok(body!);
    if (path == '/v1/balance/top-ups') {
      return _ok({
        'id': 'top_1',
        'amount': body!['amount'],
        'currency': body['currency'],
        'status': 'pending',
        'checkout_url': '$base/checkout/top_1',
        'test_mode': true
      }, 201);
    }
    if (path == '/v1/transactions') {
      final items = payments.values.toList();
      final limit = int.parse(q['limit'] ?? '50');
      return _ok({'items': items.take(limit).toList(), 'next_cursor': items.length > limit ? 'suite' : null});
    }
    return _err(404, 'not_found');
  }
}
