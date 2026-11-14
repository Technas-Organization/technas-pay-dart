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
  TechnasBackendException(this.message, {this.status = 0, this.code});
  final String message;
  final int status;
  final String? code;

  /// Vrai si relire plus tard a du sens (réseau, 429, 5xx).
  bool get retryable => status == 0 || status == 429 || status >= 500;

  @override
  String toString() => 'TechnasBackendException($status${code == null ? '' : ', $code'}): $message';
}

/// Implémentation prête du contrat HTTP par défaut, que les SDK serveur Technas Pay exposent :
///
/// - `POST {baseUrl}/technas-pay/payments`, corps = [TechnasPayBackend.startPayment] `order` ;
/// - `GET  {baseUrl}/technas-pay/payments/{id}`.
///
/// Les deux rendent `{"payment": {id, status, reference, checkout_url, amount, currency, expires_at}}`.
/// [headers] : l'authentification de VOTRE utilisateur (jeton de session), jamais une clé Technas.
class TechnasPayHttpBackend implements TechnasPayBackend {
  TechnasPayHttpBackend({
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

  @override
  Future<TechnasPaymentState> startPayment(Map<String, Object?> order) => _send('POST', '/technas-pay/payments', jsonEncode(order));

  @override
  Future<TechnasPaymentState> readPayment(String paymentId) =>
      _send('GET', '/technas-pay/payments/${Uri.encodeComponent(paymentId)}', null);

  Future<TechnasPaymentState> _send(String method, String path, String? body) async {
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
      );
    }
    if (data is! Map) throw TechnasBackendException('Réponse illisible', status: response.statusCode);
    try {
      return TechnasPaymentState.fromJson(data.cast<String, dynamic>());
    } on FormatException catch (e) {
      throw TechnasBackendException(e.message, status: response.statusCode);
    }
  }
}
