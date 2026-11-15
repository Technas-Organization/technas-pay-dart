// Routes toutes faites pour une app (technas_pay_flutter, TechnasPayClient) : contrat
// `contract/app-contract.v1.json`, rejoué ici ET par le client Flutter et les SDK Node et Python.
//
// Vous ne fournissez que deux crochets :
//   - authorize(request) : VOTRE authentification ; l'utilisateur, ou null (401) ;
//   - resolveOrder(orderId, user) : la commande relue EN BASE, ou null si elle n'existe pas ou
//     n'est pas à cet utilisateur (404). Le montant ne vient jamais de l'app.
import 'dart:async';
import 'dart:convert';

import 'client.dart';
import 'errors.dart';
import 'models.dart';
import 'status.dart';
import 'webhooks.dart';

/// Ce que `resolveOrder` rend : relu en base, jamais pris de la requête de l'app.
class AppOrder {
  const AppOrder({
    required this.amount,
    required this.customer,
    this.currency,
    this.description,
    this.returnUrl,
    this.metadata = const {},
  });

  /// Unité principale (5000 = 5 000 FCFA ; 12.5 = 12,50 € par carte). Entier pour le mobile money.
  final num amount;

  /// `{'email', 'name', 'phone'?, 'country'?}`
  final Map<String, String> customer;
  final String? currency;
  final String? description;
  final String? returnUrl;
  final Map<String, Object?> metadata;
}

/// La requête, vue indépendamment du framework. [path] est relatif au préfixe de montage.
class AppRequest {
  const AppRequest({
    required this.method,
    required this.path,
    this.query = const {},
    this.headers = const {},
    this.rawBody = '',
    this.original,
  });

  final String method;
  final String path;
  final Map<String, String> query;

  /// Clés en minuscules.
  final Map<String, String> headers;
  final String rawBody;

  /// L'objet de requête du framework, passé tel quel à `authorize`.
  final Object? original;
}

class AppResponse {
  const AppResponse(this.status, this.body);
  final int status;
  final Object? body;
}

AppResponse _err(int status, String code, String message, [bool retryable = false]) =>
    AppResponse(status, {'code': code, 'message': message, 'retryable': retryable});

AppResponse _fromPayError(TechnasPayException e) {
  // Panne ou réseau côté Technas : 502, à relire plus tard. Sinon le refus est transmis tel quel.
  if (e.code == 'network_error' || e.status >= 500 || e.status == 0) return _err(502, e.code, e.message, true);
  return _err(e.status, e.code, e.message, e.retryable);
}

final _essai = RegExp(r'^(.+?)-(?:card-)?\d+$');

/// `42-3` ou `42-card-3` → `42` (la commande d'un essai).
String _orderIdOf(String reference) => _essai.firstMatch(reference)?.group(1) ?? reference;

/// Ce que l'app voit du compte carte : ni pays, ni identifiants.
Map<String, Object?> _appAccount(CardAccount a) => {
      'status': a.status,
      'can_accept_payments': a.canAcceptPayments,
      'payouts_enabled': a.payoutsEnabled,
      'requirements': a.requirements,
      'disabled_reason': a.disabledReason,
    };

final _paymentPath = RegExp(r'^/payments/([^/]+)$');

class AppRoutes<User extends Object> {
  AppRoutes(
    this._pay, {
    required this.authorize,
    required this.resolveOrder,
    this.returnUrl,
    this.webhooks,
    this.maxAttempts = 20,
    this.card = false,
    this.authorizeAdmin,
  });

  final TechnasPay _pay;

  /// Votre authentification : l'utilisateur, ou null (401).
  final FutureOr<User?> Function(AppRequest request) authorize;

  /// La commande de CET utilisateur, relue en base ; null si inconnue ou à un autre (404).
  final FutureOr<AppOrder?> Function(String orderId, User user) resolveOrder;

  /// Page de retour par défaut (https, ou lien qui rouvre l'app).
  final String? returnUrl;

  /// Vos fonctions de webhook. Route : POST /webhook. Sans elles, la route n'existe pas.
  final WebhookHandlers? webhooks;
  final int maxAttempts;

  /// Proposer la carte : ouverte seulement si votre compte carte est prêt et que la commande a une
  /// `currency`.
  final bool card;

  /// Le MARCHAND, pour `GET /card/account` et `POST /card/onboarding` ; null → 403. Sans ce crochet,
  /// ces routes n'existent pas.
  final FutureOr<Object?> Function(AppRequest request)? authorizeAdmin;

  Future<Map<String, Object?>> _cardMethod(AppOrder order) async {
    if (!card) return {'method': 'card', 'available': false, 'reason': 'not_enabled'};
    if (order.currency == null) return {'method': 'card', 'available': false, 'reason': 'currency_required'};
    final account = await _pay.getCardAccount();
    return account.canAcceptPayments
        ? {'method': 'card', 'available': true, 'reason': null}
        : {'method': 'card', 'available': false, 'reason': 'card_account_not_ready'};
  }

  Future<AppResponse> _cardRoutes(AppRequest req, String path) async {
    if (authorizeAdmin == null) return _err(404, 'not_found', 'Route inconnue');
    final admin = await authorizeAdmin!(req);
    if (admin == null || admin == false) return _err(403, 'forbidden', 'Réservé au marchand');
    try {
      if (path == '/card/account') return AppResponse(200, {'account': _appAccount(await _pay.getCardAccount())});
      Object? body;
      try {
        body = req.rawBody.isEmpty ? <String, Object?>{} : jsonDecode(req.rawBody);
      } on FormatException {
        return _err(400, 'invalid_request', 'Corps JSON illisible');
      }
      if (body is! Map || body['returnUrl'] is! String || body['refreshUrl'] is! String) {
        return _err(400, 'invalid_request', 'returnUrl et refreshUrl sont obligatoires');
      }
      final link = await _pay.startCardOnboarding(
        returnUrl: body['returnUrl'] as String,
        refreshUrl: body['refreshUrl'] as String,
        country: body['country'] as String?,
        email: body['email'] as String?,
        businessType: body['businessType'] as String?,
      );
      return AppResponse(200, {'url': link.url, 'kind': link.kind, 'expires_at': link.expiresAt, 'account': _appAccount(link.account)});
    } on TechnasPayException catch (e) {
      return _fromPayError(e);
    }
  }

  Future<Payment> _start(String orderId, AppOrder order, String method) async {
    // Une référence = un essai : `orderId-1`, `-2`… Un essai expiré lève payment_expired, on passe
    // au suivant. Un essai en cours (ou payé) est rendu tel quel : jamais deux paiements.
    for (var attempt = 1;; attempt++) {
      try {
        return await _pay.askForPayment(
          amount: order.amount,
          // La carte a ses propres essais : un essai mobile money en cours n'est jamais heurté.
          reference: method == 'card' ? '$orderId-card-$attempt' : retryReference(orderId, attempt),
          method: method,
          customer: order.customer,
          returnUrl: order.returnUrl ?? returnUrl ?? '',
          currency: order.currency,
          description: order.description,
          metadata: {...order.metadata, 'order_id': orderId},
        );
      } on TechnasPayException catch (e) {
        if (e.code == 'payment_expired' && attempt < maxAttempts) continue;
        rethrow;
      }
    }
  }

  /// Le cœur, sans framework.
  Future<AppResponse> handle(AppRequest req) async {
    final path = '/${req.path.replaceAll(RegExp(r'^/+|/+$'), '')}';
    final method = req.method.toUpperCase();

    if (method == 'POST' && path == '/webhook') {
      if (webhooks == null) return _err(404, 'not_found', 'Webhook non branché');
      final r = await _pay.handleWebhook(req.rawBody, req.headers[signatureHeader], webhooks!);
      return AppResponse(r.status, r.body);
    }

    if ((method == 'GET' && path == '/card/account') || (method == 'POST' && path == '/card/onboarding')) {
      return _cardRoutes(req, path);
    }

    final known = (method == 'GET' && (path == '/methods' || _paymentPath.hasMatch(path))) || (method == 'POST' && path == '/payments');
    if (!known) return _err(404, 'not_found', 'Route inconnue');

    final user = await authorize(req);
    if (user == null) return _err(401, 'unauthorized', 'Connexion requise');

    try {
      if (path == '/methods') {
        final orderId = req.query['orderId'];
        if (orderId == null || orderId.isEmpty) return _err(400, 'invalid_request', 'orderId manquant');
        final order = await resolveOrder(orderId, user);
        if (order == null) return _err(404, 'order_not_found', 'Commande introuvable');
        return AppResponse(200, {
          'amount': order.amount,
          'currency': order.currency,
          // La carte s'ouvre quand le compte carte du marchand est prêt.
          'methods': [
            {'method': 'mobile_money', 'available': true, 'reason': null},
            await _cardMethod(order),
          ],
        });
      }

      if (path == '/payments') {
        Object? body;
        try {
          body = req.rawBody.isEmpty ? <String, Object?>{} : jsonDecode(req.rawBody);
        } on FormatException {
          return _err(400, 'invalid_request', 'Corps JSON illisible');
        }
        final raw = body is Map ? body['orderId'] : null;
        final orderId = raw is String || raw is int ? '$raw' : '';
        if (orderId.isEmpty) return _err(400, 'invalid_request', 'orderId manquant');
        final payMethod = (body as Map)['method'] ?? 'mobile_money';
        if (payMethod != 'mobile_money' && payMethod != 'card') {
          return _err(400, 'invalid_request', 'method vaut "mobile_money" ou "card"');
        }
        if (payMethod == 'card' && !card) return _err(400, 'method_not_available', "Le paiement par carte n'est pas ouvert");
        final order = await resolveOrder(orderId, user);
        if (order == null) return _err(404, 'order_not_found', 'Commande introuvable');
        if (payMethod == 'card' && order.currency == null) {
          return _err(400, 'currency_required', "La commande n'a pas de devise : carte impossible");
        }
        return AppResponse(200, {'payment': (await _start(orderId, order, payMethod as String)).toAppJson()});
      }

      // GET /payments/{id} : seulement si la commande de ce paiement est à cet utilisateur.
      final id = Uri.decodeComponent(_paymentPath.firstMatch(path)!.group(1)!);
      final Payment payment;
      try {
        payment = await _pay.getPayment(id);
      } on TechnasPayException catch (e) {
        if (e.code == 'payment_not_found') return _err(404, 'payment_not_found', 'Paiement introuvable');
        rethrow;
      }
      if (await resolveOrder(_orderIdOf(payment.reference), user) == null) {
        return _err(404, 'payment_not_found', 'Paiement introuvable');
      }
      return AppResponse(200, {'payment': payment.toAppJson()});
    } on TechnasPayException catch (e) {
      return _fromPayError(e);
    }
  }
}
