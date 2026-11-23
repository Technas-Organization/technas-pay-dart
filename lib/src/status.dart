/// Statuts et règles sans secret : utilisables côté serveur ET dans une app Flutter.
library;

/// `failed` n'est PAS définitif : le payeur peut réessayer sur la même page pendant une heure.
/// `expired` l'est : seulement alors, relancez avec une NOUVELLE référence ([canRetry]).
abstract final class PaymentStatus {
  static const creating = 'creating';
  static const pending = 'pending';
  static const completed = 'completed';
  static const failed = 'failed';
  static const amountMismatch = 'amount_mismatch';
  static const expired = 'expired';

  static const finals = {completed, amountMismatch, expired};
}

/// Les moyens de paiement : `mobile_money` (défaut) ou `card`.
abstract final class PaymentMethod {
  static const mobileMoney = 'mobile_money';
  static const card = 'card';

  /// Tous les moyens, à énumérer.
  static const all = [mobileMoney, card];
}

/// Tous les moyens de paiement, à énumérer (`for (final m in paymentMethods)`).
const List<String> paymentMethods = PaymentMethod.all;

/// Les réseaux mobile money : le porte-monnaie que le client a dans sa poche, jamais
/// l'intermédiaire qui fait passer le paiement. [mixx] = Mixx by Yas (ex-T-Money, Togocel),
/// [moov] = Moov Money (Flooz au Togo). Ceux réellement ouverts, par pays :
/// `pay.getPaymentMethods(country)`.
///
/// Un réseau se lit comme une chaîne : un réseau plus récent que ce SDK est gardé tel quel.
abstract final class Network {
  static const mixx = 'mixx';
  static const moov = 'moov';
  static const mtnMomo = 'mtn_momo';
  static const orangeMoney = 'orange_money';
  static const wave = 'wave';
  static const airtelMoney = 'airtel_money';
  static const freeMoney = 'free_money';
  static const celtiisCash = 'celtiis_cash';
  static const djamo = 'djamo';
  static const expresso = 'expresso';
  static const wizall = 'wizall';
  static const mobicash = 'mobicash';
  static const mpesa = 'mpesa';
  static const telecelCash = 'telecel_cash';
  static const airteltigoMoney = 'airteltigo_money';
  static const afrimoney = 'afrimoney';
  static const qmoney = 'qmoney';
  static const tnmMpamba = 'tnm_mpamba';
  static const emola = 'emola';
  static const zamtelKwacha = 'zamtel_kwacha';
  static const ezypesa = 'ezypesa';
  static const halopesa = 'halopesa';
  static const tpesa = 'tpesa';

  /// Tous les réseaux, à énumérer.
  static const all = [
    mixx, moov, mtnMomo, orangeMoney, wave, airtelMoney, freeMoney, celtiisCash, //
    djamo, expresso, wizall, mobicash, mpesa, telecelCash, airteltigoMoney, afrimoney, //
    qmoney, tnmMpamba, emola, zamtelKwacha, ezypesa, halopesa, tpesa,
  ];
}

/// Tous les réseaux mobile money (voir [Network]), à énumérer.
const List<String> networks = Network.all;

/// Vrai si le statut ne changera plus : `completed`, `expired`, `amount_mismatch`. Jamais `failed`.
bool isFinal(String status) => PaymentStatus.finals.contains(status);

/// Vrai seulement pour `expired` : relancez le client avec une NOUVELLE référence. Jamais sur `failed`.
bool canRetry(String status) => status == PaymentStatus.expired;

/// Une référence = un essai : `'$orderId-$attempt'`. Gardez `attempt` en base (1, 2, 3…).
String retryReference(Object orderId, int attempt) {
  if (attempt < 1) throw ArgumentError.value(attempt, 'attempt', 'entier >= 1');
  return '$orderId-$attempt';
}

/// Zone franc CFA : pays → devise. XOF et XAF sont à parité fixe : même montant dans les deux.
const Map<String, String> currencyByCountry = {
  // UEMOA
  'BJ': 'XOF', 'BF': 'XOF', 'CI': 'XOF', 'GW': 'XOF', 'ML': 'XOF', 'NE': 'XOF', 'SN': 'XOF', 'TG': 'XOF',
  // CEMAC
  'CM': 'XAF', 'CF': 'XAF', 'CG': 'XAF', 'GA': 'XAF', 'GQ': 'XAF', 'TD': 'XAF',
};

/// La devise d'un pays de la zone franc CFA (code ISO à deux lettres), sinon `null`.
String? currencyForCountry(String? country) => country == null ? null : currencyByCountry[country.trim().toUpperCase()];

/// Vrai si [url] est une page de paiement Technas (https, domaine technas.fr).
///
/// Dans une app : vérifiez le lien reçu de VOTRE backend avant de l'ouvrir, pour ne jamais
/// envoyer un client sur une page de paiement imitée.
bool isTechnasCheckoutUrl(String? url, {Set<String> hosts = const {'pay-api.technas.fr'}}) {
  final uri = url == null ? null : Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) return false;
  if (!hosts.contains(uri.host)) return false;
  return uri.path.startsWith('/checkout/') || uri.path.startsWith('/test-checkout/');
}
