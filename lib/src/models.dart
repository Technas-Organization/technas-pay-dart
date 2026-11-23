/// Modèles typés. Les montants sont en unité principale (5000 = 5 000 FCFA) ; hors zone franc
/// CFA un montant payé peut avoir des centimes (`121.96` GHS) : gardez-le en `num`, ne l'arrondissez pas.
library;

typedef Json = Map<String, dynamic>;

Json _map(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<Json> _list(Object? v) => v is List ? v.map(_map).toList() : <Json>[];

/// Hors zone franc CFA : le change appliqué à un paiement.
class PaymentFx {
  PaymentFx._(this.mode, this.rate, this.francPerUnit, this.marginPct, this.source, this.creditedCurrency);

  static PaymentFx? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = _map(raw);
    return PaymentFx._(j['mode'] as String, j['rate'] as num, j['franc_per_unit'] as num, (j['margin_pct'] as num?) ?? 0,
        j['source'] as String?, j['credited_currency'] as String);
  }

  final String mode;
  final num rate;
  final num francPerUnit;
  final num marginPct;
  final String? source;
  final String creditedCurrency;
}

class Payment {
  Payment.fromJson(Json j)
      : id = j['id'] as String,
        reference = j['reference'] as String,
        amount = j['amount'] as num,
        currency = j['currency'] as String?,
        commission = (j['commission'] as num?) ?? 0,
        netAmount = (j['net_amount'] as num?) ?? 0,
        status = j['status'] as String,
        method = (j['method'] as String?) ?? 'mobile_money',
        refundedAmount = (j['refunded_amount'] as num?) ?? 0,
        originalAmount = j['original_amount'] as num?,
        originalCurrency = j['original_currency'] as String?,
        fx = PaymentFx.fromJson(j['fx']),
        checkoutUrl = j['checkout_url'] as String?,
        metadata = _map(j['metadata']),
        testMode = j['test_mode'] == true,
        createdAt = j['created_at'] as String?,
        completedAt = j['completed_at'] as String?,
        expiresAt = j['expires_at'] as String?,
        expiredAt = j['expired_at'] as String?,
        canceledAt = j['canceled_at'] as String?,
        cancelReason = j['cancel_reason'] as String?,
        reason = j['reason'] as String?,
        customerAmount = (j['customer_amount'] as num?) ?? j['amount'] as num,
        feesPaidBy = (j['fees_paid_by'] as String?) ?? 'partner',
        customerTotal = j['customer_total'] as num?,
        processingFee = j['processing_fee'] as num?,
        network = j['network'] as String?,
        networks = (j['networks'] as List?)?.cast<String>();

  final String id;
  final String reference;

  /// VOTRE prix : comparez-le à votre facture.
  final num amount;

  /// Ce que Technas demande au réseau de paiement, avant ses frais (= [amount] sauf frais au client).
  final num customerAmount;

  /// Qui a payé les frais : `partner` ou `customer`.
  final String feesPaidBy;

  /// Ce que le client paie, frais du réseau de paiement compris (le plus haut des réseaux tant
  /// qu'il n'a pas choisi le sien). `null` : inconnu (carte, hors franc CFA, serveur ancien).
  final num? customerTotal;

  /// Les frais du réseau de paiement dans [customerTotal].
  final num? processingFee;

  /// Le réseau avec lequel le client a payé ([Network]), une fois payé (`null` avant, par carte,
  /// ou sur un serveur ancien). Un réseau plus récent que ce SDK est gardé tel quel.
  final String? network;

  /// Les réseaux permis pour ce paiement, s'il les a restreints (`null` sinon).
  final List<String>? networks;

  /// `null` tant que le payeur n'a pas choisi son pays sur la page de paiement.
  final String? currency;
  final num commission;

  /// Ce qui vous revient.
  final num netAmount;
  final String status;

  /// `mobile_money` ou `card`.
  final String method;
  final num refundedAmount;

  /// Hors zone CFA : le montant demandé, en F CFA.
  final num? originalAmount;
  final String? originalCurrency;
  final PaymentFx? fx;

  /// `null` après expiration : n'envoyez jamais un ancien lien.
  final String? checkoutUrl;
  final Json metadata;
  final bool testMode;
  final String? createdAt;
  final String? completedAt;
  final String? expiresAt;
  final String? expiredAt;

  /// Quand vous l'avez annulé (`cancelPayment`) ; null sinon. Un paiement annulé reste `expired`.
  final String? canceledAt;

  /// `canceled_by_partner`, ou null.
  final String? cancelReason;

  /// Dans l'avis `payment.expired` : `canceled` (annulé par vous) ou `timeout` (délai dépassé) ;
  /// null ailleurs et dans un avis plus ancien.
  final String? reason;

  /// Ce que VOTRE backend renvoie à votre app (`{"payment": toAppJson()}`) : ni commission, ni
  /// montant net, ni métadonnées. C'est le contrat que lit `technas_pay_flutter`
  /// (`TechnasPayHttpBackend`).
  Map<String, Object?> toAppJson() => {
        'id': id,
        'reference': reference,
        'status': status,
        'checkout_url': checkoutUrl,
        'amount': amount,
        'currency': currency,
        'expires_at': expiresAt,
        'method': method,
      };
}

/// Un réseau du devis : ce que le client paie s'il paie avec lui.
class QuoteNetwork {
  QuoteNetwork.fromJson(Json j)
      : network = j['network'] as String,
        networkName = (j['network_name'] as String?) ?? j['network'] as String,
        customerTotal = j['customer_total'] as num,
        processingFee = j['processing_fee'] as num,
        commission = j['commission'] as num,
        netAmount = j['net_amount'] as num,
        operatorFeeEstimate = j['operator_fee_estimate'] as num?,
        otpRequired = j['otp_required'] == true,
        otpInstructions = j['otp_instructions'] as String?;

  /// Le réseau ([Network]), ex. `mixx`. Un réseau plus récent que ce SDK est gardé tel quel.
  final String network;

  /// Le nom que le client connaît (ex. « Mixx by Yas »).
  final String networkName;

  /// Ce que le client paie, frais du réseau de paiement compris : le montant à afficher.
  final num customerTotal;

  /// Les frais du réseau de paiement dans [customerTotal].
  final num processingFee;

  /// La commission Technas.
  final num commission;

  /// Ce que vous recevez.
  final num netAmount;

  /// Les frais propres de l'opérateur du client, prélevés sur son téléphone EN PLUS, hors Technas :
  /// une estimation (« environ »), jamais promise. `null` : inconnus.
  final num? operatorFeeEstimate;

  /// Le client doit obtenir un code sur son téléphone avant de payer ([otpInstructions]).
  final bool otpRequired;
  final String? otpInstructions;
}

/// Le devis d'un paiement (`quote`, `getFees`) : rien n'est créé.
class Quote {
  Quote.fromJson(Json j)
      : method = (j['method'] as String?) ?? 'mobile_money',
        currency = j['currency'] as String,
        country = j['country'] as String?,
        feesPaidBy = (j['fees_paid_by'] as String?) ?? 'partner',
        amount = j['amount'] as num,
        customerAmount = (j['customer_amount'] as num?) ?? j['amount'] as num,
        customerTotal = (j['customer_total'] as num?) ?? j['amount'] as num,
        processingFee = j['processing_fee'] as num?,
        commission = (j['commission'] as num?) ?? 0,
        netAmount = j['net_amount'] as num?,
        networks = _list(j['networks']).map(QuoteNetwork.fromJson).toList();

  /// `mobile_money` ou `card`.
  final String method;
  final String currency;
  final String? country;

  /// Qui paie les frais : `partner` ou `customer`.
  final String feesPaidBy;

  /// Votre prix.
  final num amount;

  /// Ce que Technas demande au réseau de paiement (avant ses frais).
  final num customerAmount;

  /// Ce que le client paie, frais du réseau compris (le plus haut des réseaux possibles) : le
  /// montant à afficher. Par carte : [amount] (les frais de la carte sont pris sur votre compte carte).
  final num customerTotal;

  /// Les frais du réseau de paiement (le plus haut des réseaux) ; `null` par carte.
  final num? processingFee;
  final num commission;

  /// Ce que vous recevez ; `null` par carte (dépend de la carte du client).
  final num? netAmount;

  /// Réseau par réseau (mobile money) ; vide par carte.
  final List<QuoteNetwork> networks;
}

class TransactionPage {
  TransactionPage(this.items, this.nextCursor);
  final List<Payment> items;
  final String? nextCursor;
}

class Balance {
  Balance(this.currency, this.amount);
  final String currency;
  final num amount;
}

class Settlement {
  Settlement.fromJson(Json j)
      : id = j['id'] as String,
        amount = j['amount'] as num,
        fee = (j['fee'] as num?) ?? 0,
        currency = j['currency'] as String,
        status = j['status'] as String,
        createdAt = j['created_at'] as String?;

  final String id;

  /// Ce qui a quitté votre solde ; vous recevez `amount - fee`.
  final num amount;
  final num fee;
  final String currency;
  final String status;
  final String? createdAt;
}

/// Contenu des avis `settlement.completed` et `settlement.failed` : l'issue d'un reversement de
/// votre solde vers votre numéro mobile money. Tous facultatifs : un champ absent se lit `null`.
class SettlementNotice {
  SettlementNotice.fromJson(Json j)
      : id = j['id'] as String?,
        amount = j['amount'] as num?,
        fee = j['fee'] as num?,
        netAmount = j['net_amount'] as num?,
        currency = j['currency'] as String?,
        status = j['status'] as String?,
        createdAt = j['created_at'] as String?;

  /// Identifiant du reversement, le même que dans `getSettlements()`.
  final String? id;

  /// Ce qui a quitté votre solde. Sur `settlement.failed`, cette somme y est recréditée.
  final num? amount;

  /// Frais du versement mobile money, à votre charge.
  final num? fee;

  /// Ce qui arrive sur votre numéro.
  final num? netAmount;
  final String? currency;

  /// `completed` | `failed`
  final String? status;
  final String? createdAt;
}

/// Le numéro mobile money où Technas vous reverse votre solde.
class PayoutDestination {
  const PayoutDestination({required this.country, required this.network, required this.phone, required this.beneficiaryName});

  /// "TG", "BJ"…
  final String country;

  /// Code de `getPayoutNetworks(country)` : "moov_tg", "togocel"…
  final String network;

  /// Format international : "+22890000000".
  final String phone;
  final String beneficiaryName;

  Json toJson() => {'country': country, 'network': network, 'phone': phone, 'beneficiary_name': beneficiaryName};
}

class PayoutDestinationView {
  PayoutDestinationView.fromJson(Json j)
      : currency = j['currency'] as String,
        country = j['country'] as String,
        network = j['network'] as String,
        phone = j['phone'] as String,
        beneficiaryName = j['beneficiary_name'] as String,
        status = j['status'] as String,
        effectiveAt = j['effective_at'] as String?,
        confirmExpiresAt = j['confirm_expires_at'] as String?;

  final String currency;
  final String country;
  final String network;
  final String phone;
  final String beneficiaryName;

  /// `awaiting_confirmation` | `scheduled` | `active`
  final String status;
  final String? effectiveAt;
  final String? confirmExpiresAt;
}

class CurrencyDestinations {
  CurrencyDestinations(this.currency, this.current, this.pending);
  final String currency;

  /// `null` : aucun reversement ne part dans cette devise ; l'argent attend sur le solde.
  final PayoutDestinationView? current;
  final PayoutDestinationView? pending;
}

class PayoutDestinationState {
  PayoutDestinationState.fromJson(Object? raw)
      : destinations = _list(_map(raw)['destinations'])
            .map((d) => CurrencyDestinations(
                  d['currency'] as String,
                  d['current'] is Map ? PayoutDestinationView.fromJson(_map(d['current'])) : null,
                  d['pending'] is Map ? PayoutDestinationView.fromJson(_map(d['pending'])) : null,
                ))
            .toList();

  final List<CurrencyDestinations> destinations;
}

class PayoutNetwork {
  PayoutNetwork(this.code, this.name, this.currency);
  final String code;
  final String name;
  final String? currency;
}

class Refund {
  Refund.fromJson(Json j)
      : id = j['id'] as String,
        paymentId = j['payment_id'] as String,
        paymentReference = j['payment_reference'] as String,
        amount = j['amount'] as num,
        sentAmount = (j['sent_amount'] as num?) ?? 0,
        fee = (j['fee'] as num?) ?? 0,
        fees = j['fees'] as String? ?? 'partner',
        balanceDebit = (j['balance_debit'] as num?) ?? 0,
        currency = j['currency'] as String,
        status = j['status'] as String,
        failure = j['failure'] as String?,
        kind = _normaliserLeGenre((j['kind'] as String?) ?? 'payout'),
        method = j['method'] as String?,
        note = j['note'] as String?,
        recordedBy = j['recorded_by'] as String?,
        createdAt = j['created_at'] as String?;

  final String id;
  final String paymentId;
  final String paymentReference;

  /// Décompté du paiement : jamais plus que le montant payé, au total.
  final num amount;

  /// Ce qui arrive sur le téléphone du client.
  final num sentAmount;
  final num fee;
  final String fees;

  /// Ce qui a quitté votre solde.
  final num balanceDebit;
  final String currency;

  /// `pending` | `completed` | `failed`
  final String status;
  final String? failure;

  /// `payout` (renvoyé par Technas) | `card` (carte, remboursée depuis VOTRE compte carte) |
  /// `external` (fait hors plateforme, seulement enregistré)
  final String kind;
  final String? method;
  final String? note;
  final String? recordedBy;
  final String? createdAt;

  // Transition : l'ancienne valeur `stripe` est lue comme `card`.
  static String _normaliserLeGenre(String kind) => kind == 'stripe' ? 'card' : kind;
}

class TopUp {
  TopUp.fromJson(Json j)
      : id = j['id'] as String,
        amount = j['amount'] as num,
        currency = j['currency'] as String,
        status = j['status'] as String,
        checkoutUrl = j['checkout_url'] as String,
        testMode = j['test_mode'] == true,
        createdAt = j['created_at'] as String?,
        completedAt = j['completed_at'] as String?;

  final String id;
  final num amount;
  final String currency;
  final String status;

  /// Ouvrez cette page pour payer la recharge.
  final String checkoutUrl;
  final bool testMode;
  final String? createdAt;
  final String? completedAt;
}

/// Un moyen de paiement ouvert pour votre compte, et s'il est activé.
class MethodSetting {
  MethodSetting.fromJson(Json j)
      : method = j['method'] as String,
        enabled = j['enabled'] == true;

  /// [PaymentMethod] : `mobile_money` ou `card`.
  final String method;
  final bool enabled;
}

/// Un réseau ouvert pour votre compte, dans un pays, et s'il est activé (votre réglage).
class NetworkSetting {
  NetworkSetting.fromJson(Json j)
      : network = j['network'] as String,
        name = (j['name'] as String?) ?? j['network'] as String,
        country = j['country'] as String?,
        currency = j['currency'] as String?,
        enabled = j['enabled'] == true;

  /// Le réseau ([Network]), ex. `mixx`.
  final String network;

  /// Le nom que le client connaît (ex. « Mixx by Yas »).
  final String name;
  final String? country;
  final String? currency;
  final bool enabled;
}

/// Les moyens et réseaux ouverts pour votre compte, ce que vous avez activé, et votre ordre.
class PaymentMethods {
  PaymentMethods.fromJson(Object? raw)
      : methods = _list(_map(raw)['methods']).map(MethodSetting.fromJson).toList(),
        networks = _list(_map(raw)['networks']).map(NetworkSetting.fromJson).toList(),
        networkOrder = ((_map(raw)['network_order'] as List?) ?? const []).cast<String>();

  final List<MethodSetting> methods;

  /// Réseaux ouverts, par pays, dans VOTRE ordre d'affichage.
  final List<NetworkSetting> networks;
  final List<String> networkOrder;
}

class CountryRules {
  CountryRules.fromJson(Object? raw)
      : allowed = (_map(raw)['allowed'] as List?)?.cast<String>(),
        excluded = ((_map(raw)['excluded'] as List?) ?? const []).cast<String>();

  /// `null` : tous les pays.
  final List<String>? allowed;
  final List<String> excluded;
}

class FxCountry {
  FxCountry.fromJson(Json c)
      : country = c['country'] as String,
        name = c['name'] as String,
        currency = c['currency'] as String,
        available = c['available'] == true,
        reason = c['reason'] as String?,
        rate = c['rate'] as num?,
        rateSource = c['rate_source'] as String?,
        ratePublishedAt = c['rate_published_at'] as String?,
        markupPct = (c['markup_pct'] as num?) ?? 0,
        estimatedConversionCostPct = c['estimated_conversion_cost_pct'] as num?;

  final String country;
  final String name;
  final String currency;
  final bool available;

  /// Si `available` est faux : `no_operator`, `no_fresh_rate`, `no_payout_number`,
  /// `no_fx_channel`, `currency_not_enabled`.
  final String? reason;
  final num? rate;
  final String? rateSource;
  final String? ratePublishedAt;
  final num markupPct;
  final num? estimatedConversionCostPct;
}

/// Votre option hors zone CFA, ses risques en clair, vos règles de pays, les pays ouverts.
class FxMode {
  FxMode.fromJson(Json j)
      : mode = j['mode'] as String,
        availableModes = ((j['available_modes'] as List?) ?? const ['none', 'local']).cast<String>(),
        homeCurrency = j['home_currency'] as String?,
        markupPct = (j['markup_pct'] as num?) ?? 0,
        riskAcceptedAt = j['risk_accepted_at'] as String?,
        riskVersion = j['risk_version'] as String?,
        risks = _map(j['risks']).cast<String, String>(),
        countryRules = CountryRules.fromJson(j['country_rules']),
        countries = _list(j['countries']).map(FxCountry.fromJson).toList();

  final String mode;

  /// Options choisissables aujourd'hui. `converted` lève `fx_mode_unavailable`.
  final List<String> availableModes;
  final String? homeCurrency;
  final num markupPct;
  final String? riskAcceptedAt;
  final String? riskVersion;

  /// Textes à MONTRER à l'utilisateur avant `setFxMode` : `none`, `local`, `converted`, `markup`.
  final Map<String, String> risks;
  final CountryRules countryRules;
  final List<FxCountry> countries;
}

/// Où en est votre compte de paiement par carte : `not_started`, `onboarding`, `under_review`,
/// `restricted` (`requirements`, `disabledReason`) ou `enabled`.
class CardAccount {
  CardAccount.fromJson(Json j)
      : status = j['status'] as String,
        canAcceptPayments = j['can_accept_payments'] == true,
        payoutsEnabled = j['payouts_enabled'] == true,
        detailsSubmitted = j['details_submitted'] == true,
        country = j['country'] as String?,
        requirements = ((j['requirements'] as List?) ?? const []).cast<String>(),
        disabledReason = j['disabled_reason'] as String?,
        testMode = j['test_mode'] == true,
        updatedAt = j['updated_at'] as String?;

  final String status;

  /// Seule condition pour `askForPayment(method: 'card')`.
  final bool canAcceptPayments;
  final bool payoutsEnabled;
  final bool detailsSubmitted;
  final String? country;
  final List<String> requirements;
  final String? disabledReason;
  final bool testMode;
  final String? updatedAt;
}

class CardOnboardingLink {
  CardOnboardingLink.fromJson(Json j)
      : url = j['url'] as String,
        kind = j['kind'] as String,
        expiresAt = j['expires_at'] as String?,
        account = CardAccount.fromJson(_map(j['account']));

  /// À ouvrir par le RESPONSABLE du compte. Expire vite : à générer au clic.
  final String url;

  /// `onboarding` ou `dashboard`.
  final String kind;
  final String? expiresAt;
  final CardAccount account;
}

int _int(Object? v) => v is num ? v.toInt() : 0;
int? _intOrNull(Object? v) => v is num ? v.toInt() : null;

/// Le seuil d'identité de votre compte (`getAccountKyc()`). En réel, sans pièce d'identité
/// vérifiée, les NOUVEAUX paiements mobile money sont refusés (`kyc_required`) au-delà de
/// [thresholdXof] encaissés ou [graceDays] jours après le premier paiement réel encaissé.
/// Les chiffres viennent d'ici : ne les écrivez jamais en dur.
///
/// À montrer au MARCHAND (pas au client final). Une valeur inconnue de [stage], [level] ou
/// [reason] est gardée telle quelle.
class AccountKyc {
  AccountKyc.fromJson(Json j)
      : applies = j['applies'] == true,
        stage = (j['stage'] as String?) ?? 'not_applicable',
        level = (j['level'] as String?) ?? 'none',
        daysElapsed = _intOrNull(j['days_elapsed']),
        warnFromXof = _int(j['warn_from_xof']),
        warnFromDate = j['warn_from_date'] as String?,
        collectedXof = _int(j['collected_xof']),
        thresholdXof = _int(j['threshold_xof']),
        graceDays = _int(j['grace_days']),
        firstCollectedAt = j['first_collected_at'] as String?,
        deadline = j['deadline'] as String?,
        waiverUntil = j['waiver_until'] as String?,
        blocked = j['blocked'] == true,
        reason = j['reason'] as String?,
        consoleUrl = (j['console_url'] as String?) ?? '';

  /// Faux : le seuil ne vous concerne pas (compte de test, déjà vérifié…).
  final bool applies;

  /// `ok` | `soon` | `blocked` | `verified` | `not_applicable`.
  final String stage;

  /// Pièce vérifiée : `none` | `identity` | `business`.
  final String level;

  /// Jours depuis le premier paiement réel encaissé (`null` : aucun).
  final int? daysElapsed;

  /// Montant (F CFA) à partir duquel `stage` passe à `soon`.
  final int warnFromXof;

  /// Date à partir de laquelle `stage` passe à `soon`.
  final String? warnFromDate;

  /// Cumul encaissé en réel, en F CFA.
  final int collectedXof;

  /// Seuil de cumul, en F CFA.
  final int thresholdXof;

  /// Jours accordés après le premier paiement réel encaissé.
  final int graceDays;
  final String? firstCollectedAt;

  /// Date au-delà de laquelle les nouveaux paiements mobile money sont refusés.
  final String? deadline;

  /// Délai supplémentaire accordé par Technas, jusqu'à cette date.
  final String? waiverUntil;

  /// Vrai : les NOUVEAUX paiements mobile money sont refusés (`kyc_required`).
  final bool blocked;

  /// Si [blocked] : `amount` (seuil de cumul) ou `duration` (délai dépassé).
  final String? reason;

  /// Où le responsable du compte dépose sa pièce.
  final String consoleUrl;
}

/// Contenu de l'avis `account.kyc_required` : prévenez le RESPONSABLE du compte.
class KycRequiredNotice {
  KycRequiredNotice.fromJson(Json j)
      : reason = (j['reason'] as String?) ?? '',
        collectedXof = _int(j['collected_xof']),
        thresholdXof = _int(j['threshold_xof']),
        deadline = j['deadline'] as String?,
        blocked = j['blocked'] == true,
        consoleUrl = (j['console_url'] as String?) ?? '',
        stage = j['stage'] as String?,
        blockReason = j['block_reason'] as String?,
        daysElapsed = _intOrNull(j['days_elapsed']),
        graceDays = _intOrNull(j['grace_days']),
        firstCollectedAt = j['first_collected_at'] as String?;

  /// `amount_80` (80 % du seuil), `deadline_7d` (7 jours avant l'échéance) ou `blocked`
  /// (premier refus). Valeur inconnue gardée telle quelle.
  final String reason;
  final int collectedXof;
  final int thresholdXof;
  final String? deadline;
  final bool blocked;

  /// Où le responsable du compte dépose sa pièce.
  final String consoleUrl;

  // L'état du compte, comme [AccountKyc]. Tous facultatifs : `null` sur un avis plus ancien.

  /// `ok` | `soon` | `blocked` | `verified` | `not_applicable` (valeur inconnue gardée telle quelle).
  final String? stage;

  /// Si bloqué : `amount` (seuil de cumul) ou `duration` (délai dépassé).
  final String? blockReason;

  /// Jours depuis le premier paiement réel encaissé.
  final int? daysElapsed;

  /// Jours accordés après le premier paiement réel encaissé.
  final int? graceDays;

  /// Date du premier paiement réel encaissé.
  final String? firstCollectedAt;
}
