import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:technas_pay_flutter/technas_pay_flutter.dart';

const checkout = 'https://pay-api.technas.fr/checkout/pay_1';

/// Faux backend du partenaire : chaque relecture rend le statut suivant de [script].
class FakeBackend implements TechnasPayBackend {
  FakeBackend(this.script, {this.startStatus = 'pending', this.url = checkout});
  final List<String> script;
  final String startStatus;
  final String? url;
  int starts = 0;
  int reads = 0;
  final orders = <Map<String, Object?>>[];

  @override
  Future<TechnasPaymentState> startPayment(Map<String, Object?> order) async {
    starts++;
    orders.add(order);
    return TechnasPaymentState(id: 'pay_$starts', status: startStatus, reference: '42-$starts', checkoutUrl: url);
  }

  @override
  Future<TechnasPaymentState> readPayment(String paymentId) async {
    final status = reads < script.length ? script[reads] : script.last;
    reads++;
    if (status == 'network') throw TechnasBackendException('down');
    return TechnasPaymentState(id: paymentId, status: status, checkoutUrl: status == 'expired' ? null : url);
  }
}

Widget host(TechnasPaymentController c, {Locale locale = const Locale('fr')}) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('fr'), Locale('en'), Locale('de')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: TechnasPaymentView(controller: c, onClose: () {})),
    );

const fast = [Duration(seconds: 1)];

void main() {
  late List<Uri> opened;
  Future<bool> launcher(Uri uri) async {
    opened.add(uri);
    return true;
  }

  setUp(() => opened = []);

  testWidgets('ouvre la page Technas, attend, puis « Paiement reçu » sur un statut relu', (tester) async {
    final backend = FakeBackend(['pending', 'completed']);
    final c = TechnasPaymentController(backend: backend, order: {'orderId': '42'}, launcher: launcher, rhythm: fast);
    await tester.pumpWidget(host(c));
    await c.start();
    await tester.pump();
    expect(opened.single.toString(), checkout);
    expect(find.byKey(const ValueKey('technas-pay-waiting')), findsOneWidget);
    expect(backend.orders.single, {'orderId': '42'}); // jamais de montant envoyé par l'app
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(c.phase, TechnasPaymentPhase.paid);
    await tester.pump();
    expect(find.text('Paiement reçu'), findsOneWidget);
    final readsAtEnd = backend.reads;
    await tester.pump(const Duration(seconds: 30));
    expect(backend.reads, readsAtEnd, reason: 'plus aucune relecture après un statut final');
    c.dispose();
  });

  testWidgets('failed n\'est pas définitif : on continue de relire, et completed peut suivre', (tester) async {
    final backend = FakeBackend(['failed', 'failed', 'completed']);
    final c = TechnasPaymentController(backend: backend, order: {}, launcher: launcher, rhythm: fast);
    await tester.pumpWidget(host(c));
    await c.start();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(c.phase, TechnasPaymentPhase.failed);
    expect(find.text('Rouvrir la page'), findsOneWidget);
    expect(find.text('Payer à nouveau'), findsNothing, reason: 'jamais de nouvel essai sur failed');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(c.phase, TechnasPaymentPhase.paid);
    c.dispose();
  });

  testWidgets('expired : « Payer à nouveau » demande un NOUVEL essai au backend', (tester) async {
    final backend = FakeBackend(['expired']);
    final c = TechnasPaymentController(backend: backend, order: {'orderId': '42'}, launcher: launcher, rhythm: fast);
    await tester.pumpWidget(host(c));
    await c.start();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(c.phase, TechnasPaymentPhase.expired);
    expect(c.state!.checkoutUrl, isNull);
    await tester.tap(find.text('Payer à nouveau'));
    await tester.pump();
    expect(backend.starts, 2);
    expect(c.state!.reference, '42-2');
    c.dispose();
  });

  testWidgets('relecture impossible : on n\'affirme rien ; au-delà du délai, « Vérification en cours »', (tester) async {
    final backend = FakeBackend(['network']);
    final c = TechnasPaymentController(backend: backend, order: {}, launcher: launcher, rhythm: fast, deadline: const Duration(seconds: 3));
    await tester.pumpWidget(host(c));
    await c.start();
    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(c.phase, TechnasPaymentPhase.waiting);
    await tester.pump(const Duration(seconds: 1));
    expect(c.phase, TechnasPaymentPhase.stillChecking);
    await tester.pump();
    expect(find.text('Vérifier maintenant'), findsOneWidget);
    c.dispose();
  });

  testWidgets('retour dans l\'app : relecture immédiate', (tester) async {
    final backend = FakeBackend(['pending', 'completed']);
    final c = TechnasPaymentController(backend: backend, order: {}, launcher: launcher, rhythm: const [Duration(minutes: 5)]);
    await tester.pumpWidget(host(c));
    await c.start();
    await tester.pump();
    expect(backend.reads, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(backend.reads, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(c.phase, TechnasPaymentPhase.paid);
    c.dispose();
  });

  testWidgets('un lien qui n\'est pas une page Technas n\'est jamais ouvert', (tester) async {
    final backend = FakeBackend(['pending'], url: 'https://pay-api.technas.fr.evil.example/checkout/x');
    final c = TechnasPaymentController(backend: backend, order: {}, launcher: launcher, rhythm: fast);
    await tester.pumpWidget(host(c));
    await c.start();
    await tester.pump();
    expect(opened, isEmpty);
    expect(c.phase, TechnasPaymentPhase.untrustedLink);
    c.dispose();
  });

  testWidgets('création refusée : erreur et « Réessayer »', (tester) async {
    final c = TechnasPaymentController(backend: _Failing(), order: {}, launcher: launcher);
    await tester.pumpWidget(host(c));
    await c.start();
    await tester.pump();
    expect(c.phase, TechnasPaymentPhase.error);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.text('Commande déjà payée'), findsOneWidget, reason: 'un refus 4xx montre le message du backend');
    c.dispose();
  });

  testWidgets('les textes suivent la langue de l\'app, anglais par défaut', (tester) async {
    final c = TechnasPaymentController(backend: FakeBackend(['completed'], startStatus: 'completed'), order: {}, launcher: launcher);
    await tester.pumpWidget(host(c, locale: const Locale('de')));
    await c.start();
    await tester.pump();
    expect(find.text('Zahlung erhalten'), findsOneWidget);
    for (final t in TechnasPayTexts.byLanguage.values) {
      expect(t.paidTitle, isNotEmpty);
    }
    expect(TechnasPayTexts.byLanguage.keys, containsAll(['fr', 'en', 'pt', 'es', 'de', 'it']));
    c.dispose();
  });

  testWidgets('showTechnasPayment rend l\'état final à la fermeture', (tester) async {
    TechnasPaymentState? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showTechnasPayment(context,
              backend: FakeBackend(['completed'], startStatus: 'completed'), order: {}, launcher: launcher),
          child: const Text('payer'),
        ),
      ),
    ));
    await tester.tap(find.text('payer'));
    await tester.pumpAndSettle();
    expect(find.text('Payment received'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(result!.isPaid, isTrue);
  });

  group('TechnasPayHttpBackend (contrat par défaut)', () {
    test('POST /technas-pay/payments puis GET /technas-pay/payments/{id}, en-têtes de VOTRE session', () async {
      final seen = <http.Request>[];
      final client = MockClient((r) async {
        seen.add(r);
        final payment = {
          'id': 'pay 1',
          'status': r.method == 'POST' ? 'pending' : 'completed',
          'checkout_url': checkout,
          'amount': 5000,
          'currency': 'XOF'
        };
        return http.Response(jsonEncode({'payment': payment}), 200, headers: {'content-type': 'application/json'});
      });
      final backend = TechnasPayHttpBackend(
          baseUrl: 'https://api.partenaire.test/', client: client, headers: () async => {'Authorization': 'Bearer session-user'});
      final started = await backend.startPayment({'orderId': '42'});
      expect(started.checkoutUrl, checkout);
      expect(seen.first.url.toString(), 'https://api.partenaire.test/technas-pay/payments');
      expect(jsonDecode(seen.first.body), {'orderId': '42'});
      expect(seen.first.headers['Authorization'], 'Bearer session-user');
      final read = await backend.readPayment(started.id);
      expect(read.isPaid, isTrue);
      expect(seen.last.url.path, '/technas-pay/payments/pay%201');
    });

    test('erreurs : 4xx non rejouable avec le message, réseau rejouable', () async {
      final refused = TechnasPayHttpBackend(
          baseUrl: 'https://x',
          client: MockClient((_) async => http.Response('{"code":"already_paid","message":"Déjà payée"}', 409,
              headers: {'content-type': 'application/json; charset=utf-8'})));
      await expectLater(
          refused.startPayment({}),
          throwsA(isA<TechnasBackendException>()
              .having((e) => e.retryable, 'retryable', isFalse)
              .having((e) => e.code, 'code', 'already_paid')));
      final down = TechnasPayHttpBackend(baseUrl: 'https://x', client: MockClient((_) => throw http.ClientException('x')));
      await expectLater(down.readPayment('p'), throwsA(isA<TechnasBackendException>().having((e) => e.retryable, 'r', isTrue)));
    });

    test('accepte camelCase et réponse non enveloppée', () {
      final s = TechnasPaymentState.fromJson({'id': 'p', 'status': 'expired', 'checkoutUrl': null, 'expiresAt': '2026-11-14T10:00:00Z'});
      expect(s.canRetry, isTrue);
      expect(s.expiresAt, isNotNull);
      expect(() => TechnasPaymentState.fromJson({'status': 'x'}), throwsFormatException);
    });
  });
}

class _Failing implements TechnasPayBackend {
  @override
  Future<TechnasPaymentState> startPayment(Map<String, Object?> order) async =>
      throw TechnasBackendException('Commande déjà payée', status: 409);
  @override
  Future<TechnasPaymentState> readPayment(String paymentId) async => throw UnimplementedError();
}
