/// Vérification des webhooks Technas : `X-Technas-Payment-Signature: t=<s>,s=<hmac_sha256_hex>`,
/// HMAC de `'$t.$corpsBrut'` avec la partie webhook du secret. Toujours sur les octets reçus.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'errors.dart';
import 'models.dart';

const signatureHeader = 'x-technas-payment-signature';
const defaultToleranceSeconds = 300;

final _signatureRe = RegExp(r'^t=(\d+),s=([0-9a-fA-F]+)$');

class EventPayment {
  EventPayment.fromJson(Json d)
      : id = d['id'] as String,
        reference = d['reference'] as String,
        status = d['status'] as String,
        amount = d['amount'] as num,
        currency = d['currency'] as String?,
        commission = (d['commission'] as num?) ?? 0,
        netAmount = (d['net_amount'] as num?) ?? 0,
        metadata = d['metadata'] is Map ? (d['metadata'] as Map).cast<String, dynamic>() : <String, dynamic>{},
        completedAt = d['completed_at'] as String?,
        originalAmount = d['original_amount'] as num?,
        originalCurrency = d['original_currency'] as String?,
        fx = PaymentFx.fromJson(d['fx']),
        expiresAt = d['expires_at'] as String?,
        expiredAt = d['expired_at'] as String?,
        reason = d['reason'] as String?,
        canceledAt = d['canceled_at'] as String?,
        cancelReason = d['cancel_reason'] as String?,
        customerAmount = (d['customer_amount'] as num?) ?? d['amount'] as num,
        feesPaidBy = (d['fees_paid_by'] as String?) ?? 'partner',
        customerTotal = d['customer_total'] as num?,
        processingFee = d['processing_fee'] as num?,
        network = d['network'] as String?;

  final String id;
  final String reference;
  final String status;
  final num amount;

  /// Ce que Technas a demandé au réseau de paiement, avant ses frais (= [amount] sauf frais au client).
  final num customerAmount;

  /// Qui a payé les frais : `partner` ou `customer`.
  final String feesPaidBy;

  /// Ce que le client a payé, frais du réseau de paiement compris (`null` : inconnu).
  final num? customerTotal;

  /// Les frais du réseau de paiement dans [customerTotal].
  final num? processingFee;

  /// Le réseau avec lequel le client a payé ([Network], ex. `mixx`) ; `null` sinon.
  final String? network;
  final String? currency;
  final num commission;
  final num netAmount;
  final Json metadata;
  final String? completedAt;

  /// Hors zone CFA : le montant demandé en F CFA ; `amount`/`currency` = ce qui a été payé.
  final num? originalAmount;
  final String? originalCurrency;
  final PaymentFx? fx;
  final String? expiresAt;
  final String? expiredAt;

  /// `payment.expired` : `canceled` (annulé par vous, `cancelPayment`) ou `timeout` (délai
  /// dépassé) ; null dans un avis plus ancien.
  final String? reason;

  /// `payment.expired` annulé : quand.
  final String? canceledAt;
  final String? cancelReason;
}

/// Un événement vérifié. Selon [type], un seul champ de contenu est rempli ; [data] garde le brut.
/// [id] est stable d'une livraison à l'autre : servez-vous-en pour ignorer un doublon.
class TechnasPayEvent {
  TechnasPayEvent._(this.id, this.type, this.createdAt, this.data,
      {this.payment, this.refund, this.destination, this.cardAccount, this.kycRequired, this.settlement});

  final String id;
  final String type;
  final String? createdAt;
  final Json data;
  final EventPayment? payment;
  final Refund? refund;
  final PayoutDestinationView? destination;

  /// `card_account.updated` : le nouvel état de votre compte carte.
  final CardAccount? cardAccount;

  /// `account.kyc_required` : seuil d'identité proche ou atteint.
  final KycRequiredNotice? kycRequired;

  /// `settlement.completed` / `settlement.failed` : l'issue d'un reversement de votre solde.
  final SettlementNotice? settlement;

  static TechnasPayEvent parse(Object? raw) {
    if (raw is! Map || raw['id'] is! String || raw['type'] is! String || raw['data'] is! Map) {
      throw WebhookVerificationException('Webhook illisible');
    }
    final d = (raw['data'] as Map).cast<String, dynamic>();
    final type = raw['type'] as String;
    final id = raw['id'] as String;
    final createdAt = raw['created_at'] as String?;
    try {
      if (type.startsWith('payment.') && const {'payment.completed', 'payment.failed', 'payment.expired'}.contains(type)) {
        return TechnasPayEvent._(id, type, createdAt, d, payment: EventPayment.fromJson(d));
      }
      if (const {'refund.completed', 'refund.failed', 'refund.recorded'}.contains(type)) {
        return TechnasPayEvent._(id, type, createdAt, d, refund: Refund.fromJson(d));
      }
      if (type == 'card_account.updated') {
        return TechnasPayEvent._(id, type, createdAt, d, cardAccount: CardAccount.fromJson(d));
      }
      if (type == 'account.kyc_required') {
        return TechnasPayEvent._(id, type, createdAt, d, kycRequired: KycRequiredNotice.fromJson(d));
      }
      if (type == 'settlement.completed' || type == 'settlement.failed') {
        return TechnasPayEvent._(id, type, createdAt, d, settlement: SettlementNotice.fromJson(d));
      }
      if (type == 'payout_destination.change_scheduled' || type == 'payout_destination.updated') {
        return TechnasPayEvent._(id, type, createdAt, d, destination: PayoutDestinationView.fromJson(d));
      }
    } on TypeError {
      throw WebhookVerificationException('Webhook illisible');
    }
    // balance.topped_up, balance.converted, fx_mode.updated et tout type inconnu : lire [data].
    return TechnasPayEvent._(id, type, createdAt, d);
  }
}

/// Valeur de l'en-tête de signature pour ce corps (sert aux tests).
String sign(String body, String webhookSecret, {int? timestamp}) {
  final ts = timestamp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final digest = Hmac(sha256, utf8.encode(webhookSecret)).convert(utf8.encode('$ts.$body'));
  return 't=$ts,s=$digest';
}

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// Vérifie la signature sur le corps BRUT et rend l'événement. Lève [WebhookVerificationException].
TechnasPayEvent verifySignature(
  String rawBody,
  String? signature,
  String webhookSecret, {
  int toleranceSeconds = defaultToleranceSeconds,
  DateTime? now,
}) {
  final match = _signatureRe.firstMatch((signature ?? '').trim());
  if (match == null) throw WebhookVerificationException('Signature absente ou mal formée');
  final ts = int.parse(match.group(1)!);
  final current = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  if ((current - ts).abs() > toleranceSeconds) throw WebhookVerificationException('Signature trop ancienne');
  final expected = Hmac(sha256, utf8.encode(webhookSecret)).convert(utf8.encode('$ts.$rawBody')).toString();
  if (!_constantTimeEquals(expected, match.group(2)!.toLowerCase())) {
    throw WebhookVerificationException('Signature invalide');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(rawBody);
  } on FormatException {
    throw WebhookVerificationException('Webhook illisible');
  }
  return TechnasPayEvent.parse(decoded);
}

typedef WebhookCallback = FutureOr<void> Function(TechnasPayEvent event);

/// Vos fonctions, toutes facultatives. Une exception doit REMONTER (réponse 5xx) : Technas relivre.
class WebhookHandlers {
  const WebhookHandlers({
    this.onCompleted,
    this.onFailed,
    this.onExpired,
    this.onPayoutDestination,
    this.onRefund,
    this.onTopUp,
    this.onBalanceConverted,
    this.onFxModeUpdated,
    this.onCardAccountUpdated,
    this.onKycRequired,
    this.onSettlement,
  });

  /// Marquez la commande payée (`event.payment!.reference`).
  final WebhookCallback? onCompleted;

  /// PAS définitif : n'annulez rien, ne relancez rien.
  final WebhookCallback? onFailed;

  /// Définitif : seul moment où relancer, avec une NOUVELLE référence.
  final WebhookCallback? onExpired;
  final WebhookCallback? onPayoutDestination;

  /// `refund.completed` / `refund.failed` / `refund.recorded` : prévenez le client.
  final WebhookCallback? onRefund;
  final WebhookCallback? onTopUp;
  final WebhookCallback? onBalanceConverted;

  /// Si ce n'est pas vous qui avez changé d'option, prévenez Technas (clé compromise ?).
  final WebhookCallback? onFxModeUpdated;

  /// Votre compte carte a changé d'état (ouvert, à compléter, suspendu…).
  final WebhookCallback? onCardAccountUpdated;

  /// `account.kyc_required` (80 % du seuil, 7 jours avant l'échéance, premier refus) : prévenez
  /// le RESPONSABLE du compte, avec `event.kycRequired!.consoleUrl`.
  final WebhookCallback? onKycRequired;

  /// `settlement.completed` / `settlement.failed` : l'issue d'un reversement de votre solde vers
  /// votre numéro mobile money (`event.settlement!`). Sur `failed`, `amount` est recrédité.
  final WebhookCallback? onSettlement;

  WebhookCallback? forType(String type) {
    if (type == 'payment.completed') return onCompleted;
    if (type == 'payment.failed') return onFailed;
    if (type == 'payment.expired') return onExpired;
    if (type.startsWith('payout_destination.')) return onPayoutDestination;
    if (type.startsWith('refund.')) return onRefund;
    if (type == 'balance.topped_up') return onTopUp;
    if (type == 'balance.converted') return onBalanceConverted;
    if (type == 'fx_mode.updated') return onFxModeUpdated;
    if (type == 'card_account.updated') return onCardAccountUpdated;
    if (type == 'account.kyc_required') return onKycRequired;
    if (type == 'settlement.completed' || type == 'settlement.failed') return onSettlement;
    return null; // type inconnu : acquitté sans rien appeler
  }
}

/// Réponse à renvoyer : 200 `{"received":true}` ou 400 `{"error":"invalid_signature"}`.
class WebhookResult {
  WebhookResult(this.status, this.body, [this.event]);
  final int status;
  final Json body;
  final TechnasPayEvent? event;

  String get jsonBody => jsonEncode(body);
}
