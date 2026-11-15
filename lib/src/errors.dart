/// Erreurs du SDK. Leur message ne cite jamais le secret.
library;

/// Une erreur rendue par Technas, ou détectée avant tout appel (`status` vaut alors 0).
///
/// Testez [code] (stable), jamais le message : `payment_expired`, `reference_conflict`,
/// `risk_not_accepted`, `fx_mode_unavailable`, `insufficient_balance`, `kyc_required`…
/// [retryable] : refaire LE MÊME appel, mêmes valeurs, a du sens.
class TechnasPayException implements Exception {
  TechnasPayException(
    this.code,
    this.message, {
    this.status = 0,
    this.errors,
    this.missingAmount,
    this.currency,
    this.refundableAmount,
    this.reason,
    this.risk,
    this.accountStatus,
    this.consoleUrl,
    this.version,
  });

  factory TechnasPayException.fromResponse(int status, Object? data) {
    final d = data is Map<String, dynamic> ? data : const <String, dynamic>{};
    // Les précisions arrivent au premier niveau ou dans `details`.
    final details = d['details'] is Map ? (d['details'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    T? pick<T>(String key) => (d[key] ?? details[key]) is T ? (d[key] ?? details[key]) as T : null;
    return TechnasPayException(
      (d['code'] as String?) ?? 'request_failed',
      (d['message'] as String?) ?? 'Réponse HTTP $status',
      status: status,
      errors: (d['errors'] as List?)?.cast<Map<String, dynamic>>(),
      missingAmount: pick<num>('missing_amount'),
      currency: pick<String>('currency'),
      refundableAmount: pick<num>('refundable_amount'),
      reason: pick<String>('reason'),
      risk: pick<String>('risk'),
      accountStatus: pick<String>('account_status'),
      consoleUrl: pick<String>('console_url'),
      version: pick<String>('version'),
    );
  }

  final String code;
  final String message;
  final int status;
  final List<Map<String, dynamic>>? errors;

  /// `insufficient_balance` : rechargez au moins ce montant ([currency]) avec `topUpBalance`.
  final num? missingAmount;
  final String? currency;

  /// `refund_exceeds_payment` : le plus qu'on peut encore rembourser.
  final num? refundableAmount;

  /// `country_not_available` : ce qui manque (`no_payout_number`…).
  /// `kyc_required` : `amount` (seuil de cumul atteint) ou `duration` (délai dépassé).
  final String? reason;

  /// `risk_not_accepted` : le texte du risque, à montrer à l'utilisateur.
  final String? risk;

  /// `card_account_not_ready` : où en est votre compte carte (`not_started`, `onboarding`…).
  final String? accountStatus;

  /// `kyc_required`, `contract_required` : la console où le responsable agit.
  final String? consoleUrl;

  /// `contract_required` : la version du contrat à accepter dans la console.
  final String? version;

  bool get retryable => code == 'network_error' || code == 'payment_in_progress' || status == 429 || status >= 500;

  @override
  String toString() => 'TechnasPayException($code, status: $status): $message';
}

/// Signature absente, mal formée, trop ancienne, fausse, ou corps illisible : répondez 400.
class WebhookVerificationException implements Exception {
  WebhookVerificationException(this.message);
  final String message;

  @override
  String toString() => 'WebhookVerificationException: $message';
}
