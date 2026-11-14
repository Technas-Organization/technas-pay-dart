import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:technas_pay/app.dart' as tp;

/// Ce que l'app sait d'un paiement : uniquement ce que VOTRE backend lui renvoie.
///
/// Aucun secret, aucune commission, aucune donnée d'un autre client : le backend ne
/// transmet que ces champs (`toAppJson` / `to_app_json` dans les SDK serveur Technas Pay).
class TechnasPaymentState {
  const TechnasPaymentState({
    required this.id,
    required this.status,
    this.reference,
    this.checkoutUrl,
    this.amount,
    this.currency,
    this.expiresAt,
    this.method = 'mobile_money',
  });

  /// Lit `{id, status, reference, checkout_url, amount, currency, expires_at}` (snake_case ou
  /// camelCase), éventuellement enveloppé dans `{"payment": {...}}`.
  factory TechnasPaymentState.fromJson(Map<String, dynamic> raw) {
    final j = raw['payment'] is Map ? (raw['payment'] as Map).cast<String, dynamic>() : raw;
    Object? pick(String snake, String camel) => j[snake] ?? j[camel];
    final id = pick('id', 'id');
    final status = pick('status', 'status');
    if (id is! String || status is! String) {
      throw const FormatException('Réponse du backend : `id` et `status` sont obligatoires');
    }
    final expires = pick('expires_at', 'expiresAt');
    return TechnasPaymentState(
      id: id,
      status: status,
      reference: pick('reference', 'reference') as String?,
      checkoutUrl: pick('checkout_url', 'checkoutUrl') as String?,
      amount: pick('amount', 'amount') as num?,
      currency: pick('currency', 'currency') as String?,
      expiresAt: expires is String ? DateTime.tryParse(expires) : null,
      method: (pick('method', 'method') as String?) ?? 'mobile_money',
    );
  }

  final String id;

  /// `pending`, `completed`, `failed` (PAS définitif), `expired` (définitif), `amount_mismatch`…
  final String status;
  final String? reference;

  /// `null` après expiration : ne jamais rouvrir un ancien lien.
  final String? checkoutUrl;
  final num? amount;
  final String? currency;
  final DateTime? expiresAt;

  /// `mobile_money` ou `card`.
  final String method;

  bool get isFinal => tp.isFinal(status);
  bool get canRetry => tp.canRetry(status);
  bool get isPaid => status == tp.PaymentStatus.completed;

  TechnasPaymentState copyWith({String? status, String? checkoutUrl}) => TechnasPaymentState(
        id: id,
        status: status ?? this.status,
        reference: reference,
        checkoutUrl: checkoutUrl ?? this.checkoutUrl,
        amount: amount,
        currency: currency,
        expiresAt: expiresAt,
        method: method,
      );
}

/// Les seules choses que l'app demande — à VOTRE backend, jamais à Technas.
///
/// Votre backend tient le secret Technas Pay, crée le paiement (`askForPayment`), garde
/// `payment.id` sur la commande et reçoit le webhook. L'app ne fait qu'afficher.
abstract class TechnasPayBackend {
  /// Crée (ou reprend) le paiement de cette commande et rend son état, avec `checkoutUrl`.
  ///
  /// [order] : ce dont VOTRE backend a besoin pour retrouver la commande (son identifiant).
  /// Jamais le montant : il le calcule lui-même. Après `expired`, le backend crée un NOUVEL
  /// essai (nouvelle référence `orderId-tentative`).
  Future<TechnasPaymentState> startPayment(Map<String, Object?> order);

  /// Relit l'état du paiement (le backend le tient du webhook, ou le relit chez Technas).
  Future<TechnasPaymentState> readPayment(String paymentId);
}

/// Erreur de dialogue avec VOTRE backend (réseau, 4xx, 5xx, réponse illisible).
class TechnasBackendException implements Exception {
  TechnasBackendException(this.message, {this.status = 0, this.code, bool? retryable}) : _retryable = retryable;
  final String message;
  final int status;

  /// Le code du contrat (`unauthorized`, `order_not_found`, `payment_expired`…), ou `null`.
  final String? code;
  final bool? _retryable;

  /// Vrai si relire ou refaire plus tard a du sens : ce que dit le serveur (`retryable`), sinon
  /// réseau, 429 ou 5xx.
  bool get retryable => _retryable ?? (status == 0 || status == 429 || status >= 500);

  @override
  String toString() => 'TechnasBackendException($status${code == null ? '' : ', $code'}): $message';
}

/// Un moyen de paiement proposé pour une commande (`GET /methods`).
class TechnasPayMethod {
  const TechnasPayMethod({required this.method, required this.available, this.reason});

  factory TechnasPayMethod.fromJson(Map<String, dynamic> j) =>
      TechnasPayMethod(method: j['method'] as String, available: j['available'] == true, reason: j['reason'] as String?);

  /// `mobile_money`, `card`…
  final String method;
  final bool available;

  /// Pourquoi il n'est pas ouvert (`not_enabled`…).
  final String? reason;
}

class TechnasPayMethods {
  const TechnasPayMethods({required this.methods, this.amount, this.currency});

  factory TechnasPayMethods.fromJson(Map<String, dynamic> j) => TechnasPayMethods(
        amount: j['amount'] as num?,
        currency: j['currency'] as String?,
        methods: ((j['methods'] as List?) ?? const []).map((m) => TechnasPayMethod.fromJson((m as Map).cast())).toList(),
      );

  final num? amount;
  final String? currency;
  final List<TechnasPayMethod> methods;

  Iterable<TechnasPayMethod> get available => methods.where((m) => m.available);
}

/// Le client des routes toutes faites des SDK serveur Technas Pay (`pay.appRoutes`,
/// `pay.app_routes`) : contrat `contract/app-contract.v1.json`, rien à écrire côté serveur.
///
/// [baseUrl] : là où votre backend a monté les routes, ex. `https://api.votre-app.com/api/technas-pay`.
/// [headers] : l'authentification de VOTRE utilisateur (jeton de session), jamais une clé Technas.
class TechnasPayClient implements TechnasPayBackend {
  TechnasPayClient({
    required String baseUrl,
    this.headers,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  })  : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  /// Appelée à chaque requête : rend des en-têtes frais (jeton renouvelé).
  final Future<Map<String, String>> Function()? headers;

  /// `POST /payments` avec `{orderId}` : le serveur relit la commande, son montant compris.
  @override
  Future<TechnasPaymentState> startPayment(Map<String, Object?> order) async => _state(await _send('POST', '/payments', jsonEncode(order)));

  /// `GET /payments/{id}`.
  @override
  Future<TechnasPaymentState> readPayment(String paymentId) async =>
      _state(await _send('GET', '/payments/${Uri.encodeComponent(paymentId)}', null));

  static TechnasPaymentState _state(Map<String, dynamic> data) {
    try {
      return TechnasPaymentState.fromJson(data);
    } on FormatException catch (e) {
      throw TechnasBackendException(e.message, status: 200);
    }
  }

  /// `GET /methods?orderId=` : les moyens ouverts pour cette commande, avec son montant.
  Future<TechnasPayMethods> methods(String orderId) async =>
      TechnasPayMethods.fromJson(await _send('GET', '/methods?orderId=${Uri.encodeQueryComponent(orderId)}', null));

  /// Écran d'administration du MARCHAND (routes derrière `authorizeAdmin` côté serveur) : l'état
  /// de son compte carte (`can_accept_payments`, `requirements`…).
  Future<TechnasCardAccount> cardAccount() async =>
      TechnasCardAccount.fromJson(((await _send('GET', '/card/account', null))['account'] as Map).cast());

  /// Ouvre (ou reprend) l'inscription carte du MARCHAND : ouvrez `url` dans le navigateur, au clic
  /// (le lien expire en minutes). [returnUrl] / [refreshUrl] : où il revient (fin / lien expiré).
  Future<TechnasCardOnboarding> startCardOnboarding({required String returnUrl, required String refreshUrl, String? country}) async =>
      TechnasCardOnboarding.fromJson(await _send('POST', '/card/onboarding',
          jsonEncode({'returnUrl': returnUrl, 'refreshUrl': refreshUrl, if (country != null) 'country': country})));

  Future<Map<String, dynamic>> _send(String method, String path, String? body) async {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'))
      ..headers.addAll({'Accept': 'application/json', if (body != null) 'Content-Type': 'application/json'});
    if (headers != null) request.headers.addAll(await headers!());
    if (body != null) request.body = body;
    http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request).timeout(timeout));
    } catch (_) {
      throw TechnasBackendException('Serveur injoignable');
    }
    Object? data;
    try {
      data = response.body.isEmpty ? null : jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      data = null;
    }
    if (response.statusCode >= 400) {
      final map = data is Map ? data : const {};
      throw TechnasBackendException(
        (map['message'] as String?) ?? 'Réponse HTTP ${response.statusCode}',
        status: response.statusCode,
        code: map['code'] as String?,
        retryable: map['retryable'] is bool ? map['retryable'] as bool : null,
      );
    }
    if (data is! Map) throw TechnasBackendException('Réponse illisible', status: response.statusCode);
    try {
      return data.cast<String, dynamic>();
    } on TypeError {
      throw TechnasBackendException('Réponse illisible', status: response.statusCode);
    }
  }
}

/// L'ancien contrat (routes écrites à la main sous `{baseUrl}/technas-pay/payments`).
/// Préférez [TechnasPayClient] et les routes toutes faites de votre SDK serveur.
class TechnasPayHttpBackend extends TechnasPayClient {
  TechnasPayHttpBackend({required String baseUrl, super.headers, super.client, super.timeout})
      : super(baseUrl: '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/technas-pay');
}

/// Le compte carte du marchand, tel que le serveur le montre à l'app.
class TechnasCardAccount {
  TechnasCardAccount.fromJson(Map<String, dynamic> j)
      : status = j['status'] as String,
        canAcceptPayments = j['can_accept_payments'] == true,
        payoutsEnabled = j['payouts_enabled'] == true,
        requirements = ((j['requirements'] as List?) ?? const []).cast<String>(),
        disabledReason = j['disabled_reason'] as String?;

  /// `not_started`, `onboarding`, `under_review`, `restricted`, `enabled`.
  final String status;
  final bool canAcceptPayments;
  final bool payoutsEnabled;
  final List<String> requirements;
  final String? disabledReason;
}

class TechnasCardOnboarding {
  TechnasCardOnboarding.fromJson(Map<String, dynamic> j)
      : url = j['url'] as String,
        kind = j['kind'] as String,
        expiresAt = j['expires_at'] is String ? DateTime.tryParse(j['expires_at'] as String) : null,
        account = TechnasCardAccount.fromJson((j['account'] as Map).cast());

  final String url;

  /// `onboarding` ou `dashboard`.
  final String kind;
  final DateTime? expiresAt;
  final TechnasCardAccount account;
}
