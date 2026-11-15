import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart' show Request;
import 'package:technas_pay/app.dart' as app;
import 'package:technas_pay/technas_pay.dart';
import 'package:test/test.dart';

import '../example/shelf_server.dart' as shelf_example;
import 'fake_gateway.dart';

const customer = {'email': 'awa@exemple.tg', 'name': 'Awa Mensah'};

void main() {
  late FakeGateway gw;
  late TechnasPay pay;

  setUp(() {
    gw = FakeGateway();
    pay = TechnasPay(secret: secret, baseUrl: '$base/', httpClient: gw.client);
  });

  Future<Payment> ask({String ref = 'cmd_1-1', int amount = 5000, Map<String, String> c = customer, String? currency}) =>
      pay.askForPayment(amount: amount, reference: ref, customer: c, returnUrl: 'https://p.test/merci', currency: currency);

  test('seule la clé API part, dans un en-tête', () async {
    final p = await ask();
    final r = gw.requests.last;
    expect(r.url.toString(), '$base/v1/payments');
    expect(r.headers['Authorization'], 'Bearer $apiKey');
    final all = '${r.url}${r.headers}${r.body}';
    expect(all.contains(webhookSecret), isFalse);
    expect(all.contains('tps_test_'), isFalse);
    final body = jsonDecode(r.body) as Map;
    expect(body.containsKey('currency'), isFalse);
    expect(body['return_url'], 'https://p.test/merci');
    expect(p.netAmount, 4900);
    expect(pay.toString().contains(apiKey), isFalse);
  });

  test('toAppJson ne rend à l\'app que le nécessaire', () async {
    final p = await ask();
    final j = p.toAppJson();
    expect(j.keys, unorderedEquals(['id', 'reference', 'status', 'checkout_url', 'amount', 'currency', 'expires_at', 'method']));
    expect(j['checkout_url'], p.checkoutUrl);
  });

  test('carte : devise obligatoire, décimales, method envoyée ; compte carte', () async {
    final seen = <Map>[];
    final card = TechnasPay(
      secret: secret,
      baseUrl: base,
      httpClient: MockClient((r) async {
        seen.add(r.body.isEmpty ? {} : jsonDecode(r.body) as Map);
        if (r.url.path == '/v1/payments') {
          return http.Response(
              jsonEncode({'id': 'c1', 'reference': 'r-card-1', 'amount': 12.5, 'currency': 'EUR', 'status': 'pending', 'method': 'card'}),
              201);
        }
        if (r.url.path == '/v1/card/account') return http.Response('{"status":"enabled","can_accept_payments":true}', 200);
        if (r.url.path == '/v1/card/dashboard-link') return http.Response('{"url":"https://dashboard.stripe.com/"}', 200);
        return http.Response('{"code":"card_account_not_ready","message":"m","account_status":"onboarding"}', 409);
      }),
    );
    expect(() => card.askForPayment(amount: 12.5, reference: 'r', customer: customer, returnUrl: 'https://p', method: 'card'),
        throwsA(isA<TechnasPayException>().having((e) => e.code, 'code', 'currency_required')));
    expect(() => card.askForPayment(amount: 12.5, reference: 'r', customer: customer, returnUrl: 'https://p'),
        throwsA(isA<TechnasPayException>().having((e) => e.code, 'code', 'invalid_amount')));
    final p = await card.askForPayment(
        amount: 12.5, reference: 'r-card-1', customer: customer, returnUrl: 'https://p', method: 'card', currency: 'eur');
    expect(p.method, 'card');
    expect(seen.last['method'], 'card');
    expect(seen.last['currency'], 'EUR');
    expect((await card.getCardAccount()).canAcceptPayments, isTrue);
    expect(await card.getCardDashboardLink(), 'https://dashboard.stripe.com/');
    await expectLater(card.startCardOnboarding(returnUrl: 'https://a', refreshUrl: 'https://b', country: 'fr'),
        throwsA(isA<TechnasPayException>().having((e) => e.accountStatus, 'accountStatus', 'onboarding')));
    expect(seen.last['country'], 'FR');
  });

  test('seuil d\'identité : GET /v1/account/kyc, clé en en-tête, tous les champs décodés', () async {
    final seen = <http.Request>[];
    Map<String, Object?> body = {
      'applies': true,
      'stage': 'soon',
      'level': 'none',
      'days_elapsed': 24,
      'warn_from_xof': 800000,
      'warn_from_date': '2026-12-01T00:00:00Z',
      'collected_xof': 820000,
      'threshold_xof': 1000000,
      'grace_days': 30,
      'first_collected_at': '2026-11-08T10:00:00Z',
      'deadline': '2026-12-08T10:00:00Z',
      'waiver_until': '2026-12-20T00:00:00Z',
      'blocked': false,
      'reason': null,
      'console_url': 'https://pay.technas.fr/console/identite',
    };
    final kyc = TechnasPay(
      secret: secret,
      baseUrl: base,
      httpClient: MockClient((r) async {
        seen.add(r);
        return http.Response(jsonEncode(body), 200);
      }),
    );
    final k = await kyc.getAccountKyc();
    expect(seen.single.method, 'GET');
    expect(seen.single.url.toString(), '$base/v1/account/kyc');
    expect(seen.single.headers['Authorization'], 'Bearer $apiKey');
    expect(k.applies, isTrue);
    expect(k.stage, 'soon');
    expect(k.level, 'none');
    expect(k.daysElapsed, 24);
    expect(k.warnFromXof, 800000);
    expect(k.warnFromDate, '2026-12-01T00:00:00Z');
    expect(k.collectedXof, 820000);
    expect(k.thresholdXof, 1000000);
    expect(k.graceDays, 30);
    expect(k.firstCollectedAt, '2026-11-08T10:00:00Z');
    expect(k.deadline, '2026-12-08T10:00:00Z');
    expect(k.waiverUntil, '2026-12-20T00:00:00Z');
    expect(k.blocked, isFalse);
    expect(k.reason, isNull);
    expect(k.consoleUrl, 'https://pay.technas.fr/console/identite');

    // Champs nuls et valeurs inconnues : gardés tels quels, jamais d'exception.
    body = {
      ...body,
      'applies': false,
      'stage': 'nouvelle_etape',
      'level': 'autre_niveau',
      'days_elapsed': null,
      'warn_from_date': null,
      'first_collected_at': null,
      'deadline': null,
      'waiver_until': null,
      'blocked': true,
      'reason': 'autre_raison',
    };
    final n = await kyc.getAccountKyc();
    expect(n.applies, isFalse);
    expect(n.stage, 'nouvelle_etape');
    expect(n.level, 'autre_niveau');
    expect(n.daysElapsed, isNull);
    expect(n.warnFromDate, isNull);
    expect(n.firstCollectedAt, isNull);
    expect(n.deadline, isNull);
    expect(n.waiverUntil, isNull);
    expect(n.blocked, isTrue);
    expect(n.reason, 'autre_raison');
  });

  test('409 kyc_required et contract_required : précisions lues, jamais rejouables', () async {
    var reply = {
      'code': 'kyc_required',
      'message': 'm',
      'details': {'console_url': 'https://pay.technas.fr/console/identite', 'reason': 'duration'},
    };
    final p = TechnasPay(secret: secret, baseUrl: base, httpClient: MockClient((_) async => http.Response(jsonEncode(reply), 409)));
    await expectLater(
        p.askForPayment(amount: 5000, reference: 'k-1', customer: customer, returnUrl: 'https://p'),
        throwsA(isA<TechnasPayException>()
            .having((e) => e.code, 'code', 'kyc_required')
            .having((e) => e.status, 'status', 409)
            .having((e) => e.consoleUrl, 'consoleUrl', 'https://pay.technas.fr/console/identite')
            .having((e) => e.reason, 'reason', 'duration')
            .having((e) => e.retryable, 'retryable', isFalse)));
    reply = {
      'code': 'contract_required',
      'message': 'm',
      'details': {'console_url': 'https://pay.technas.fr/console/contrat', 'version': '2026-11'},
    };
    await expectLater(
        p.askForPayment(amount: 5000, reference: 'k-2', customer: customer, returnUrl: 'https://p'),
        throwsA(isA<TechnasPayException>()
            .having((e) => e.code, 'code', 'contract_required')
            .having((e) => e.consoleUrl, 'consoleUrl', 'https://pay.technas.fr/console/contrat')
            .having((e) => e.version, 'version', '2026-11')
            .having((e) => e.retryable, 'retryable', isFalse)));
  });

  test('la devise suit le pays CFA, jamais hors zone', () async {
    await ask(ref: 'r-cm', c: {...customer, 'country': 'cm'});
    expect((jsonDecode(gw.requests.last.body) as Map)['currency'], 'XAF');
    await ask(ref: 'r-gh', c: {...customer, 'country': 'GH'});
    expect((jsonDecode(gw.requests.last.body) as Map).containsKey('currency'), isFalse);
  });

  test('montant invalide refusé avant tout appel', () {
    expect(() => ask(amount: 0), throwsA(isA<TechnasPayException>().having((e) => e.code, 'code', 'invalid_amount')));
    expect(gw.requests, isEmpty);
  });

  test('une référence = un essai', () async {
    final first = await ask();
    expect((await ask()).id, first.id);
    await expectLater(ask(amount: 9000), throwsA(isA<TechnasPayException>().having((e) => e.code, 'code', 'reference_conflict')));
    final failed = await pay.simulateTestPayment(first.id, 'failed');
    expect(isFinal(failed.status), isFalse);
    expect(canRetry(failed.status), isFalse);
    final expired = await pay.simulateTestPayment(first.id, 'expired');
    expect(canRetry(expired.status), isTrue);
    expect(expired.checkoutUrl, isNull);
    await expectLater(
        ask(),
        throwsA(
            isA<TechnasPayException>().having((e) => e.code, 'code', 'payment_expired').having((e) => e.retryable, 'retryable', isFalse)));
    expect((await ask(ref: retryReference('cmd_1', 2))).id, isNot(first.id));
  });

  test('le client change d\'offre ou revient plus tard : nouvel essai, jamais un refus', () async {
    final first = await ask(ref: retryReference('F', 1), amount: 5000);
    await pay.simulateTestPayment(first.id, 'expired');
    expect((await pay.getPayment(first.id)).status, 'expired');
    final second = await ask(ref: retryReference('F', 2), amount: 7500);
    expect(second.id, isNot(first.id));
    expect(second.status, 'pending');
    final sent = gw.requests
        .where((r) => r.method == 'POST' && r.url.path == '/v1/payments')
        .map((r) => jsonDecode(r.body) as Map)
        .map((b) => [b['reference'], b['amount']])
        .toList();
    expect(sent, [
      ['F-1', 5000],
      ['F-2', 7500],
    ]);
    await expectLater(
        ask(ref: 'F-1', amount: 7500),
        throwsA(isA<TechnasPayException>()
            .having((e) => e.code, 'code', 'reference_conflict')
            .having((e) => e.status, 'status', 409)
            .having((e) => e.retryable, 'retryable', isFalse)));
  });

  test('remboursement carte : `stripe` reçu est lu `card`, `card` reste `card`', () {
    Refund lire(String kind) => Refund.fromJson({
          'id': 're_1',
          'payment_id': 'pay_1',
          'payment_reference': 'cmd_1',
          'amount': 12.5,
          'currency': 'EUR',
          'status': 'completed',
          'kind': kind,
        });
    expect(lire('stripe').kind, 'card');
    expect(lire('card').kind, 'card');
    expect(lire('external').kind, 'external');
  });

  test('paiement, remboursements, plafond, solde', () async {
    final p = await ask(amount: 10000);
    await expectLater(pay.refund(p.id), throwsA(isA<TechnasPayException>().having((e) => e.code, 'code', 'payment_not_refundable')));
    expect((await pay.simulateTestPayment(p.id, 'completed')).status, 'completed');
    expect((await pay.getPaymentByReference(p.reference)).id, p.id);
    await expectLater(
        pay.refund(p.id),
        throwsA(isA<TechnasPayException>()
            .having((e) => e.code, 'code', 'insufficient_balance')
            .having((e) => e.missingAmount, 'missing', 300)));
    final part = await pay.refund(p.id, amount: 3000, fees: 'customer', reference: 'decision-1');
    expect(part.sentAmount, 2900);
    final ext = await pay.recordExternalRefund(p.id, amount: 2000, method: ' Flooz ');
    expect(ext.kind, 'external');
    expect(ext.method, 'Flooz');
    await expectLater(
        pay.refund(p.id, amount: 6000), throwsA(isA<TechnasPayException>().having((e) => e.refundableAmount, 'refundable', 5000)));
    expect((await pay.getPayment(p.id)).refundedAmount, 5000);
    expect(() => pay.refund('p', fees: 'moi'), throwsA(isA<TechnasPayException>()));
  });

  test('change hors zone : risque accepté explicitement, converted fermé', () async {
    final fx = await pay.getFxMode();
    expect(fx.availableModes, ['none', 'local']);
    expect(fx.countries.first.reason, 'no_payout_number');
    await expectLater(
        pay.setFxMode(mode: 'local'), throwsA(isA<TechnasPayException>().having((e) => e.risk, 'risk', 'Vous portez le change.')));
    await expectLater(pay.setFxMode(mode: 'converted', acceptRisk: true),
        throwsA(isA<TechnasPayException>().having((e) => e.code, 'code', 'fx_mode_unavailable')));
    expect((await pay.setFxMode(mode: 'local', acceptRisk: true)).mode, 'local');
  });

  test('le reste de la surface', () async {
    await ask(ref: 'a-1');
    await ask(ref: 'b-1');
    final page = await pay.listTransactions(limit: 1, status: 'pending');
    expect(page.items, hasLength(1));
    expect(page.nextCursor, 'suite');
    expect(gw.requests.last.url.query, 'limit=1&status=pending');
    expect((await pay.getBalance()).first.currency, 'XOF');
    expect((await pay.getSettlements()).first.fee, 150);
    expect((await pay.getPayoutNetworks('TG')).first.code, 'moov_tg');
    final state = await pay.setPayoutDestination(
        const PayoutDestination(country: 'TG', network: 'moov_tg', phone: '+22890000000', beneficiaryName: 'Blexima'));
    expect(state.destinations.first.pending!.status, 'awaiting_confirmation');
    expect((await pay.getPayoutDestination()).destinations.first.current, isNull);
    expect((await pay.topUpBalance(amount: 20000, currency: 'XOF')).checkoutUrl, endsWith('/top_1'));
    final rules = await pay.setCountryRules(excluded: ['NG']);
    expect(rules.allowed, isNull);
    expect(rules.excluded, ['NG']);
  });

  test('identifiant échappé dans le chemin', () async {
    await expectLater(pay.getPayment('../balance'), throwsA(isA<TechnasPayException>()));
    expect(gw.requests.last.url.path, '/v1/payments/..%2Fbalance');
  });

  test('réseau et 5xx : rejouables ; secret mal formé : ne fuit pas', () async {
    final down = TechnasPay(secret: secret, httpClient: MockClient((_) => throw http.ClientException('réseau')));
    await expectLater(down.getBalance(),
        throwsA(isA<TechnasPayException>().having((e) => e.code, 'code', 'network_error').having((e) => e.retryable, 'r', isTrue)));
    final html = TechnasPay(secret: secret, httpClient: MockClient((_) async => http.Response('<html>', 503)));
    await expectLater(html.getBalance(),
        throwsA(isA<TechnasPayException>().having((e) => e.status, 'status', 503).having((e) => e.retryable, 'r', isTrue)));
    final bad = TechnasPay(secret: 'mon-secret-en-clair');
    await expectLater(
        bad.getBalance(),
        throwsA(isA<TechnasPayException>()
            .having((e) => e.code, 'code', 'invalid_secret')
            .having((e) => e.toString().contains('mon-secret'), 'fuite', isFalse)));
  });

  test('outils de test refusés avec un secret réel', () {
    final live = TechnasPay(secret: secret.replaceFirst('tps_test_', 'tps_live_'));
    expect(() => live.simulateTestPayment('p', 'completed'), throwsA(isA<TechnasPayException>().having((e) => e.code, 'c', 'test_only')));
    expect(() => live.createTestWebhook('payment.completed', reference: 'r', amount: 1, currency: 'XOF'),
        throwsA(isA<TechnasPayException>().having((e) => e.code, 'c', 'test_only')));
  });

  group('webhooks', () {
    final event = jsonEncode({
      'id': 'evt_1',
      'type': 'payment.completed',
      'created_at': 'x',
      'data': {
        'id': 'pay_1',
        'reference': 'cmd_1-1',
        'status': 'completed',
        'amount': 5000,
        'currency': 'XOF',
        'commission': 100,
        'net_amount': 4900
      },
    });

    test('valide : la bonne fonction est appelée', () async {
      TechnasPayEvent? got;
      final r = await pay.handleWebhook(event, sign(event, webhookSecret), WebhookHandlers(onCompleted: (e) => got = e));
      expect(r.status, 200);
      expect(r.jsonBody, '{"received":true}');
      expect(got!.payment!.netAmount, 4900);
    });

    for (final (name, signature) in [
      ('absente', null),
      ('mal formée', "n'importe quoi"),
      ('mauvais secret', sign(event, 'autre')),
      ('trop ancienne', sign(event, webhookSecret, timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 3600)),
    ]) {
      test('signature $name : 400, aucune fonction appelée', () async {
        final r = await pay.handleWebhook(event, signature, WebhookHandlers(onCompleted: (_) => fail('appelée')));
        expect(r.status, 400);
      });
    }

    test('corps modifié : refusé ; fonction qui échoue : remonte', () async {
      expect(() => pay.verifyWebhook(event.replaceFirst('5000', '9'), sign(event, webhookSecret)),
          throwsA(isA<WebhookVerificationException>()));
      await expectLater(
          pay.handleWebhook(event, sign(event, webhookSecret), WebhookHandlers(onCompleted: (_) => throw StateError('base en panne'))),
          throwsStateError);
    });

    test('familles d\'événements et type inconnu', () async {
      final seen = <String>[];
      final h = WebhookHandlers(
        onRefund: (e) => seen.add('refund:${e.refund!.status}'),
        onPayoutDestination: (e) => seen.add('dest:${e.destination!.status}'),
        onTopUp: (e) => seen.add('topup:${e.data['amount']}'),
        onFxModeUpdated: (e) => seen.add('fx:${e.data['previous_mode']}'),
        onExpired: (e) => seen.add('expired:${e.payment!.reference}'),
        onBalanceConverted: (e) => seen.add('conv:${e.data['credited_amount']}'),
      );
      for (final (type, data) in [
        ('refund.failed', {'id': 're', 'payment_id': 'p', 'payment_reference': 'r', 'amount': 1, 'currency': 'XOF', 'status': 'failed'}),
        (
          'payout_destination.updated',
          {'currency': 'XOF', 'country': 'TG', 'network': 'moov_tg', 'phone': '+228', 'beneficiary_name': 'B', 'status': 'active'}
        ),
        ('balance.topped_up', {'id': 't', 'amount': 5, 'currency': 'XOF'}),
        ('fx_mode.updated', {'mode': 'local', 'previous_mode': 'none'}),
        ('payment.expired', {'id': 'p', 'reference': 'r-1', 'status': 'expired', 'amount': 1, 'currency': 'XOF'}),
        ('balance.converted', {'credited_amount': 441}),
        ('nouveau.type', {'k': 1}),
      ]) {
        final body = jsonEncode({'id': 'e', 'type': type, 'created_at': 'x', 'data': data});
        expect((await pay.handleWebhook(body, sign(body, webhookSecret), h)).status, 200);
      }
      expect(seen, ['refund:failed', 'dest:active', 'topup:5', 'fx:none', 'expired:r-1', 'conv:441']);
    });

    test('account.kyc_required signé : onKycRequired, contenu typé', () async {
      final body = jsonEncode({
        'id': 'evt_kyc',
        'type': 'account.kyc_required',
        'created_at': 'x',
        'data': {
          'reason': 'amount_80',
          'collected_xof': 810000,
          'threshold_xof': 1000000,
          'deadline': '2026-12-08T10:00:00Z',
          'blocked': false,
          'console_url': 'https://pay.technas.fr/console/identite',
        },
      });
      TechnasPayEvent? got;
      final r = await pay.handleWebhook(
          body, sign(body, webhookSecret), WebhookHandlers(onKycRequired: (e) => got = e, onCompleted: (_) => fail('appelée')));
      expect(r.status, 200);
      final k = got!.kycRequired!;
      expect(got!.type, 'account.kyc_required');
      expect(k.reason, 'amount_80');
      expect(k.collectedXof, 810000);
      expect(k.thresholdXof, 1000000);
      expect(k.deadline, '2026-12-08T10:00:00Z');
      expect(k.blocked, isFalse);
      expect(k.consoleUrl, 'https://pay.technas.fr/console/identite');
      expect(got!.payment, isNull);
      // Avis ancien, sans l'état du compte : les nouveaux champs sont nuls.
      expect(k.stage, isNull);
      expect(k.blockReason, isNull);
      expect(k.daysElapsed, isNull);
      expect(k.graceDays, isNull);
      expect(k.firstCollectedAt, isNull);
    });

    test('account.kyc_required porte l\'état du compte', () async {
      final body = jsonEncode({
        'id': 'evt_kyc2',
        'type': 'account.kyc_required',
        'created_at': 'x',
        'data': {
          'reason': 'blocked',
          'collected_xof': 1000000,
          'threshold_xof': 1000000,
          'deadline': null,
          'blocked': true,
          'console_url': 'https://pay.technas.fr/console/identite',
          'stage': 'blocked',
          'block_reason': 'duration',
          'days_elapsed': 31,
          'grace_days': 30,
          'first_collected_at': '2026-10-15T09:00:00Z',
        },
      });
      final k = pay.verifyWebhook(body, sign(body, webhookSecret)).kycRequired!;
      expect(k.reason, 'blocked');
      expect(k.stage, 'blocked');
      expect(k.blockReason, 'duration');
      expect(k.daysElapsed, 31);
      expect(k.graceDays, 30);
      expect(k.firstCollectedAt, '2026-10-15T09:00:00Z');
    });

    test('createTestWebhook passe la vérification', () async {
      final hook = pay.createTestWebhook('payment.completed', reference: 'cmd_9-1', amount: 5000, currency: 'XOF', commission: 100);
      TechnasPayEvent? got;
      await pay.handleWebhook(hook.body, hook.headers[signatureHeader], WebhookHandlers(onCompleted: (e) => got = e));
      expect(got!.payment!.netAmount, 4900);
    });
  });

  test('exemple shelf : webhook de test signé, puis 400 sans signature', () async {
    final hook = shelf_example.pay.createTestWebhook('payment.completed', reference: '42-1', amount: 5000, currency: 'XOF');
    final ok = await shelf_example.router(Request('POST', Uri.parse('http://x/api/technas-pay'), body: hook.body, headers: hook.headers));
    expect(ok.statusCode, 200);
    expect(shelf_example.orders['42']!['paid'], isTrue);
    final expired = shelf_example.pay.createTestWebhook('payment.expired', reference: '42-1', amount: 5000, currency: 'XOF');
    await shelf_example.router(Request('POST', Uri.parse('http://x/api/technas-pay'), body: expired.body, headers: expired.headers));
    expect(shelf_example.orders['42']!['attempt'], 2);
    final bad = await shelf_example.router(Request('POST', Uri.parse('http://x/api/technas-pay'), body: hook.body));
    expect(bad.statusCode, 400);
  }, testOn: 'vm');

  group('app.dart (sans secret)', () {
    test('isTechnasCheckoutUrl n\'accepte que les pages Technas en https', () {
      expect(app.isTechnasCheckoutUrl('https://pay-api.technas.fr/checkout/pay_1'), isTrue);
      expect(app.isTechnasCheckoutUrl('https://pay-api.technas.fr/test-checkout/pay_1'), isTrue);
      expect(app.isTechnasCheckoutUrl('http://pay-api.technas.fr/checkout/pay_1'), isFalse);
      expect(app.isTechnasCheckoutUrl('https://pay-api.technas.fr.evil.example/checkout/x'), isFalse);
      expect(app.isTechnasCheckoutUrl('https://user@pay-api.technas.fr/checkout/x'), isFalse);
      expect(app.isTechnasCheckoutUrl('https://pay-api.technas.fr/v1/balance'), isFalse);
      expect(app.isTechnasCheckoutUrl(null), isFalse);
    });

    test('règles de statut et de référence', () {
      expect(app.canRetry('expired'), isTrue);
      expect(app.canRetry('failed'), isFalse);
      expect(app.isFinal('amount_mismatch'), isTrue);
      expect(app.retryReference(42, 3), '42-3');
      expect(() => app.retryReference('x', 0), throwsArgumentError);
      expect(app.currencyForCountry(' tg '), 'XOF');
    });
  });
}
