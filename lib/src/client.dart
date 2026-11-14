import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;

import 'errors.dart';
import 'models.dart';
import 'status.dart';
import 'webhooks.dart';

const _version = '0.2.0';
const defaultBaseUrl = 'https://pay-api.technas.fr';
const secretEnv = 'TECHNAS_PAY_SECRET';

final _secretRe = RegExp(r'^tps_(live|test)_([^.\s]+)\.([^.\s]+)$');

/// Vrai dans une app Flutter : le secret n'a rien à y faire.
const _inFlutterApp = bool.fromEnvironment('dart.library.ui');

class _Secret {
  _Secret(this.mode, this.apiKey, this.webhookSecret);
  final String mode;
  final String apiKey;
  final String webhookSecret;
}

void _positiveInt(num amount, [String name = 'amount']) {
  if (amount is! int || amount <= 0) {
    throw TechnasPayException('invalid_amount', '$name doit être un entier positif (5000 = 5 000 FCFA)');
  }
}

/// Client SERVEUR de Technas Pay (shelf, Dart Frog, serverpod…).
///
/// Jamais dans une app Flutter : le constructeur refuse, le secret y serait exposé. Dans une app,
/// importez `package:technas_pay/app.dart` et passez par votre backend.
class TechnasPay {
  /// [secret] : sinon lu dans `TECHNAS_PAY_SECRET` au premier appel.
  TechnasPay({
    String? secret,
    String baseUrl = defaultBaseUrl,
    http.Client? httpClient,
    this.webhookToleranceSeconds = defaultToleranceSeconds,
    String? defaultCurrency,
    Duration timeout = const Duration(seconds: 30),
  })  : _rawSecret = secret,
        _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _timeout = timeout,
        _defaultCurrency = (defaultCurrency?.trim().isEmpty ?? true) ? null : defaultCurrency!.trim().toUpperCase() {
    if (_inFlutterApp) {
      throw StateError('TechnasPay (avec secret) s\'utilise côté serveur uniquement. '
          'Dans une app Flutter, importez package:technas_pay/app.dart et appelez votre backend.');
    }
  }

  final String? _rawSecret;
  final String _baseUrl;
  final http.Client _http;
  final bool _ownsClient;
  final Duration _timeout;
  final String? _defaultCurrency;
  final int webhookToleranceSeconds;
  _Secret? _parsed;

  @override
  String toString() => 'TechnasPay(baseUrl: $_baseUrl)';

  _Secret get _secrets {
    if (_parsed != null) return _parsed!;
    final raw = _rawSecret ?? Platform.environment[secretEnv];
    final m = _secretRe.firstMatch(raw ?? '');
    // Le message ne cite jamais la valeur reçue : elle finirait dans des journaux.
    if (m == null) {
      throw TechnasPayException('invalid_secret', 'Secret Technas absent ou mal formé. Vérifiez la variable $secretEnv.');
    }
    return _parsed = _Secret(m.group(1)!, m.group(2)!, m.group(3)!);
  }

  /// Vrai avec un secret `tps_test_` : aucun argent ne circule.
  bool get testMode => _secrets.mode == 'test';

  void close() {
    if (_ownsClient) _http.close();
  }

  Future<T> _call<T>(String method, String path, T Function(Object? data) parse, [Json? body]) async {
    final headers = {
      'Authorization': 'Bearer ${_secrets.apiKey}',
      'User-Agent': 'technas-pay-dart/$_version',
      if (body != null) 'Content-Type': 'application/json',
    };
    final request = http.Request(method, Uri.parse('$_baseUrl$path'))..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request).timeout(_timeout));
    } catch (_) {
      throw TechnasPayException('network_error', 'Service de paiement injoignable');
    }
    Object? data;
    try {
      data = response.body.isEmpty ? null : jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      data = null;
    }
    if (response.statusCode >= 400) throw TechnasPayException.fromResponse(response.statusCode, data);
    return parse(data);
  }

  static String _seg(String s) => Uri.encodeComponent(s);
  static String _query(Map<String, Object?> q) {
    final entries = q.entries.where((e) => e.value != null);
    if (entries.isEmpty) return '';
    return '?${entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent('${e.value}')}').join('&')}';
  }

  /// Crée la demande de paiement ; redirigez ensuite le client vers `checkoutUrl`.
  ///
  /// [amount] : entier en F CFA (5000 = 5 000 FCFA, jamais × 100), calculé côté serveur.
  /// [reference] : UNE RÉFÉRENCE = UN ESSAI (`retryReference(orderId, attempt)`).
  /// [customer] : `{'email', 'name', 'phone'?, 'country'?}`, de vrais champs du client.
  /// Ne passez pas [currency] en zone franc CFA : elle suit le pays du client.
  Future<Payment> askForPayment({
    required int amount,
    required String reference,
    required Map<String, String> customer,
    required String returnUrl,
    String? currency,
    String? description,
    Json? metadata,
    List<String>? allowedCountries,
    List<String>? excludedCountries,
    bool askCountry = false,
  }) {
    _positiveInt(amount);
    var resolved = currency?.trim().toUpperCase();
    if (resolved == null || resolved.isEmpty) {
      final country = customer['country']?.trim();
      resolved = (country != null && country.isNotEmpty) ? currencyForCountry(country) : _defaultCurrency;
    }
    return _call('POST', '/v1/payments', (d) => Payment.fromJson(d as Json), {
      'amount': amount,
      if (resolved != null) 'currency': resolved,
      'reference': reference,
      'customer': customer,
      'return_url': returnUrl,
      if (description != null) 'description': description,
      'metadata': metadata ?? <String, dynamic>{},
      if (allowedCountries != null) 'allowed_countries': allowedCountries,
      if (excludedCountries != null) 'excluded_countries': excludedCountries,
      if (askCountry) 'ask_country': true,
    });
  }

  Future<Payment> getPayment(String id) => _call('GET', '/v1/payments/${_seg(id)}', (d) => Payment.fromJson(d as Json));

  /// Pour rattraper un webhook manqué.
  Future<Payment> getPaymentByReference(String reference) =>
      _call('GET', '/v1/payments${_query({'reference': reference})}', (d) => Payment.fromJson(d as Json));

  /// Vos paiements, du plus récent au plus ancien, par pages.
  Future<TransactionPage> listTransactions({int? limit, String? status, String? cursor}) => _call(
        'GET',
        '/v1/transactions${_query({'limit': limit, 'status': status, 'cursor': cursor})}',
        (d) {
          final j = d as Json;
          return TransactionPage(
            ((j['items'] as List?) ?? const []).map((p) => Payment.fromJson((p as Map).cast())).toList(),
            j['next_cursor'] as String?,
          );
        },
      );

  /// Rembourse un paiement `completed`, au numéro qui a payé. Sans [amount] : tout ce qui reste.
  /// [fees] : `partner` (défaut, le client reçoit tout) ou `customer`. Réservé à un administrateur.
  Future<Refund> refund(String paymentId, {int? amount, String fees = 'partner', String? reference}) {
    if (amount != null) _positiveInt(amount);
    if (fees != 'partner' && fees != 'customer') {
      throw TechnasPayException('invalid_request', 'fees vaut "partner" ou "customer"');
    }
    return _call('POST', '/v1/payments/${_seg(paymentId)}/refunds', (d) => Refund.fromJson(d as Json), {
      if (amount != null) 'amount': amount,
      'fees': fees,
      if (reference != null && reference.isNotEmpty) 'reference': reference,
    });
  }

  /// Enregistre un remboursement fait HORS Technas (Flooz, espèces…). Aucun argent ne bouge.
  Future<Refund> recordExternalRefund(String paymentId,
      {required int amount, required String method, String? note, String? recordedBy, String? reference}) {
    _positiveInt(amount);
    if (method.trim().isEmpty) throw TechnasPayException('invalid_request', 'method est obligatoire : "Flooz", "Espèces"…');
    return _call('POST', '/v1/payments/${_seg(paymentId)}/external-refunds', (d) => Refund.fromJson(d as Json), {
      'amount': amount,
      'method': method.trim(),
      if (note != null && note.isNotEmpty) 'note': note,
      if (recordedBy != null && recordedBy.isNotEmpty) 'recorded_by': recordedBy,
      if (reference != null && reference.isNotEmpty) 'reference': reference,
    });
  }

  Future<Refund> getRefund(String id) => _call('GET', '/v1/refunds/${_seg(id)}', (d) => Refund.fromJson(d as Json));

  /// Recharge votre solde : ouvrez `checkoutUrl`. Crédit : webhook `balance.topped_up`.
  Future<TopUp> topUpBalance({required int amount, required String currency, String? returnUrl}) {
    _positiveInt(amount);
    return _call('POST', '/v1/balance/top-ups', (d) => TopUp.fromJson(d as Json), {
      'amount': amount,
      'currency': currency,
      if (returnUrl != null) 'return_url': returnUrl,
    });
  }

  /// Votre option hors zone CFA, ses risques (`risks`), les pays ouverts.
  Future<FxMode> getFxMode() => _call('GET', '/v1/fx', (d) => FxMode.fromJson(d as Json));

  /// N'appelez avec `acceptRisk: true` qu'APRÈS avoir montré `getFxMode().risks[mode]` à
  /// l'utilisateur et obtenu son accord explicite. `converted` lève `fx_mode_unavailable`.
  Future<FxMode> setFxMode({required String mode, bool acceptRisk = false, num? markupPct, String? homeCurrency}) {
    if (!const {'none', 'local', 'converted'}.contains(mode)) {
      throw TechnasPayException('invalid_request', 'mode vaut "none", "local" ou "converted"');
    }
    return _call('PUT', '/v1/fx', (d) => FxMode.fromJson(d as Json), {
      'mode': mode,
      'accept_risk': acceptRisk,
      if (markupPct != null) 'markup_pct': markupPct,
      if (homeCurrency != null) 'home_currency': homeCurrency,
    });
  }

  /// Où vous vendez : pays autorisés (`null` : tous) et exclus. Codes ISO.
  Future<CountryRules> setCountryRules({List<String>? allowed, List<String> excluded = const []}) =>
      _call('PUT', '/v1/country-rules', CountryRules.fromJson, {'allowed': allowed, 'excluded': excluded});

  /// Ce que Technas vous doit, par devise.
  Future<List<Balance>> getBalance() => _call(
      'GET', '/v1/balance', (d) => ((d as List?) ?? const []).map((r) => Balance(r['currency'] as String, r['amount'] as num)).toList());

  Future<List<Settlement>> getSettlements() =>
      _call('GET', '/v1/settlements', (d) => ((d as List?) ?? const []).map((r) => Settlement.fromJson((r as Map).cast())).toList());

  Future<List<PayoutNetwork>> getPayoutNetworks(String country) => _call(
      'GET',
      '/v1/payout-networks${_query({'country': country})}',
      (d) => ((d as List?) ?? const [])
          .map((r) => PayoutNetwork(r['code'] as String, r['name'] as String, r['currency'] as String?))
          .toList());

  Future<PayoutDestinationState> getPayoutDestination() => _call('GET', '/v1/payout-destination', PayoutDestinationState.fromJson);

  /// Rien ne change avant le clic du responsable du compte dans l'e-mail reçu. Réservé à un administrateur.
  Future<PayoutDestinationState> setPayoutDestination(PayoutDestination destination) =>
      _call('PUT', '/v1/payout-destination', PayoutDestinationState.fromJson, destination.toJson());

  /// Mode test : `completed`, `failed` (pas définitif) ou `expired` (définitif), sans navigateur.
  Future<Payment> simulateTestPayment(String paymentId, String outcome) async {
    if (_secrets.mode != 'test') throw TechnasPayException('test_only', 'simulateTestPayment exige un secret tps_test_');
    if (!const {'completed', 'failed', 'expired'}.contains(outcome)) {
      throw TechnasPayException('invalid_outcome', 'outcome : completed, failed ou expired');
    }
    // Un paiement réussi renvoie vers votre returnUrl : on ne la suit pas.
    final request = http.Request('POST', Uri.parse('$_baseUrl/test-checkout/${_seg(paymentId)}/$outcome'))
      ..followRedirects = false
      ..headers['User-Agent'] = 'technas-pay-dart/$_version';
    http.StreamedResponse response;
    try {
      response = await _http.send(request).timeout(_timeout);
      await response.stream.drain<void>();
    } catch (_) {
      throw TechnasPayException('network_error', 'Service de paiement injoignable');
    }
    if (response.statusCode == 404) throw TechnasPayException('payment_not_found', 'Paiement de test introuvable', status: 404);
    return getPayment(paymentId);
  }

  // --- Webhooks ---------------------------------------------------------------------------

  /// Vérifie la signature sur le corps BRUT et rend l'événement. Lève [WebhookVerificationException].
  TechnasPayEvent verifyWebhook(String rawBody, String? signature) =>
      verifySignature(rawBody, signature, _secrets.webhookSecret, toleranceSeconds: webhookToleranceSeconds);

  /// Vérifie, appelle la bonne fonction et rend la réponse : 400 si la signature est refusée
  /// (aucune fonction appelée), 200 sinon. Une exception de vos fonctions REMONTE : répondez 500.
  Future<WebhookResult> handleWebhook(String rawBody, String? signature, WebhookHandlers handlers) async {
    final TechnasPayEvent event;
    try {
      event = verifyWebhook(rawBody, signature);
    } on WebhookVerificationException {
      return WebhookResult(400, {'error': 'invalid_signature'});
    }
    await handlers.forType(event.type)?.call(event);
    return WebhookResult(200, {'received': true}, event);
  }

  /// Webhook `payment.*` signé, pour tester votre route : `(body, headers)`. Secret test seulement.
  ({String body, Map<String, String> headers}) createTestWebhook(String type,
      {required String reference, required num amount, required String currency, num commission = 0, Json? metadata}) {
    if (_secrets.mode != 'test') throw TechnasPayException('test_only', 'createTestWebhook exige un secret tps_test_');
    if (!const {'payment.completed', 'payment.failed', 'payment.expired'}.contains(type)) {
      throw TechnasPayException('invalid_request', 'type : payment.completed, payment.failed ou payment.expired');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final completed = type == 'payment.completed';
    final expired = type == 'payment.expired';
    final body = jsonEncode({
      'id': 'evt_test_${DateTime.now().microsecondsSinceEpoch}',
      'type': type,
      'created_at': now,
      'data': {
        'id': 'pay_test_${DateTime.now().microsecondsSinceEpoch}',
        'reference': reference,
        'status': completed ? 'completed' : (expired ? 'expired' : 'failed'),
        'amount': amount,
        'currency': currency,
        'commission': commission,
        'net_amount': amount - commission,
        'metadata': metadata ?? <String, dynamic>{},
        'completed_at': completed ? now : null,
        'expires_at': now,
        'expired_at': expired ? now : null,
      },
    });
    return (body: body, headers: {'content-type': 'application/json', signatureHeader: sign(body, _secrets.webhookSecret)});
  }
}
