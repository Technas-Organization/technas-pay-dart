/// Technas Pay, côté APP (Flutter, web) : uniquement ce qui est sûr sans secret.
///
/// L'app ne parle jamais à Technas avec une clé : elle demande à VOTRE backend de créer le
/// paiement, reçoit `checkoutUrl`, vérifie que c'est bien une page Technas
/// ([isTechnasCheckoutUrl]), l'ouvre (url_launcher, WebView), puis relit le statut auprès de
/// VOTRE backend. Seul le webhook reçu par votre backend prouve le paiement.
library;

export 'src/errors.dart' show TechnasPayException;
export 'src/status.dart';
