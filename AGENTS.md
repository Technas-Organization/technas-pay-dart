# technas_pay (Dart) : règles pour un agent de code

Consignes pour un assistant de code. Appliquez-les dans l'application de l'utilisateur, pas dans ce dépôt. Le README détaille chaque fonction ; un exemple shelf complet est dans [`example/`](example).

Même API, mêmes règles que le SDK TypeScript `@technas/pay` et le SDK Python : noms en camelCase comme en TypeScript.

## Deux bibliothèques, deux endroits

| Import | Où | Règle |
|---|---|---|
| `package:technas_pay/technas_pay.dart` | **Serveur** (shelf, Dart Frog, serverpod) | Seul endroit où vit le secret |
| `package:technas_pay/app.dart` | **App Flutter**, web | Aucun secret : `isTechnasCheckoutUrl`, `canRetry`, `isFinal`, `retryReference` |

- **N'importez JAMAIS `technas_pay.dart` dans une app Flutter**, et ne mettez jamais le secret dans une app (ni `--dart-define`, ni `.env` embarqué, ni Remote Config) : il se lit dans le binaire. Le constructeur `TechnasPay()` lève d'ailleurs une `StateError` dans Flutter.
- Si l'utilisateur n'a pas de backend : il en faut un (une fonction serverless suffit), ou utiliser le SDK Python ou JS côté serveur. Ne contournez pas.

## Avant de commencer (serveur)

1. Dart 3.3+.
2. `TECHNAS_PAY_SECRET` doit exister dans l'environnement serveur et commencer par `tps_test_`. S'il manque, demandez-le à l'utilisateur. **N'en inventez pas, ne l'affichez pas, ne le commitez pas, ne le loggez pas.**
3. Repérez le modèle de commande : un identifiant, un montant calculé côté serveur, un état « payée », un numéro de tentative (1 par défaut) et une colonne pour garder `payment.id`.

## Installer

```yaml
dependencies:
  technas_pay:
    git:
      url: https://github.com/Technas-Organization/technas-pay-dart.git
      ref: v0.11.0
```

## Quelle méthode pour quoi

| Besoin | Appel |
|---|---|
| Faire payer une commande | `pay.askForPayment(amount: ..., reference: retryReference(orderId, attempt), customer: {'email': ..., 'name': ...}, returnUrl: ...)`, puis rendre `payment.checkoutUrl` à l'app ou rediriger (303) |
| Savoir combien le client paiera et combien vous recevrez, avant de créer le paiement | `pay.quote(amount: ..., country: ..., fees: ?)` (ou `pay.getFees`) → `customerTotal` (à afficher au client), `processingFee`, `commission`, `netAmount`, `networks` |
| Afficher un prix FIXE (le même quel que soit le réseau) et recevoir au moins X | `pay.displayPrice(receive: ..., country: ? \| countries: [...], roundTo: ?)` → `byCountry[pays]!.price`, `everywhere?.price` ; puis `askForPayment(amount: price, fees: 'partner')` (jamais `'customer'`) |
| La grille des frais par pays et réseau (back-office) | `pay.getRates([country])` (ou `pay.rates`) → `countries[].networks[]` : `percent`, `minimumAmount`, `commission`, `operatorFeeEstimate`, `example1000.customer/partner` |
| Faire payer TOUS les frais au client (vous recevez exactement `amount`) | `fees: 'customer'` dans `askForPayment` (ou réglage du compte) ; `'partner'` : le client paie `amount`, frais compris |
| Lister les moyens et réseaux ouverts, ce qui est activé, l'ordre | `pay.getPaymentMethods(country)` ; constantes `paymentMethods`, `networks` (une constante par valeur : `PaymentMethod.card`, `Network.mixx`…) |
| Activer / éteindre des moyens et réseaux, fixer l'ordre d'affichage | `pay.setPaymentMethods(methods: ?, networks: ?, networkOrder: ?)` ; par paiement : `networks: [...]` dans `askForPayment` |
| Savoir qu'elle est payée | webhook, `WebhookHandlers(onCompleted: ...)` |
| Rattraper un webhook manqué | `pay.getPaymentByReference(reference)` |
| Savoir si on peut relancer | `onExpired`, ou `canRetry((await pay.getPayment(id)).status)` |
| Le client change d'offre ou revient plus tard | `pay.cancelPayment(ancienId)`, puis nouvel essai `retryReference(factureId, n + 1)` ; au retour, `pay.getPayment(dernierPaiementId)` d'abord (voir la section dédiée) |
| Rembourser | `pay.refund(paymentId, amount:?, fees:?, reference:?)` |
| Noter un remboursement fait hors Technas | `pay.recordExternalRefund(paymentId, amount: ..., method: 'Flooz')` |
| Savoir que le remboursement est arrivé | `onRefund` (`refund.completed`, `refund.failed`, `refund.recorded`) |
| Recharger le solde | `pay.topUpBalance(amount: ..., currency: 'XOF')`, ouvrir `checkoutUrl` ; `onTopUp` |
| Solde, reversements | `pay.getBalance()`, `pay.getSettlements()` |
| Savoir qu'un reversement est arrivé ou a échoué | `onSettlement` (`settlement.completed`, `settlement.failed`) |
| Historique | `pay.listTransactions(limit:, status:, cursor:)` |
| Seuil d'identité (à montrer au marchand) | `pay.getAccountKyc()` ; avis `onKycRequired` |
| Pays hors zone CFA ouverts, risques | `pay.getFxMode()` |
| Activer une option hors zone (après accord explicite) | `pay.setFxMode(mode: 'local', acceptRisk: true)` |
| Pays où vendre | `pay.setCountryRules(allowed:?, excluded:)` ou `allowedCountries` / `excludedCountries` par paiement |
| Numéro de reversement (administrateur) | `pay.getPayoutNetworks('TG')`, `pay.getPayoutDestination()`, `pay.setPayoutDestination(PayoutDestination(...))` |
| Tester la route webhook | `pay.createTestWebhook('payment.completed', reference: ..., amount: ..., currency: 'XOF')` |
| Jouer le payeur en test | `pay.simulateTestPayment(id, 'completed' \| 'failed' \| 'expired')` |

## App Flutter

Ne réécrivez pas de routes : `technasPayShelfHandler(pay.appRoutes(authorize: ..., resolveOrder: ..., returnUrl: ..., webhooks: ...))` monté sur `/api/technas-pay/` (`package:technas_pay/shelf.dart`). `resolveOrder` relit la commande EN BASE et rend `null` si elle n'est pas à cet utilisateur. Routes : `GET /methods?orderId=`, `POST /payments`, `GET /payments/{id}`, `POST /payments/{id}/cancel`, `POST /webhook`. Le client change d'offre : l'app appelle `technasPay.cancelPayment(paiementAffiche.id)` (`POST /payments/{id}/cancel`), puis `startPayment(...)` ; si la commande a changé de montant, `POST /payments` annule lui-même l'ancien essai encore ouvert.

## Étapes

1. Serveur : `final pay = TechnasPay();` au niveau du module (lit `TECHNAS_PAY_SECRET` au premier appel).
2. Route « payer » : relisez la commande en base, appelez `askForPayment`, gardez `payment.id`, rendez `checkoutUrl` (à l'app) ou redirigez.
3. Route webhook `POST /api/technas-pay` : lisez le corps **brut** (shelf `request.readAsString()`, Dart Frog `context.request.body()`), puis `final r = await pay.handleWebhook(raw, request.headers[signatureHeader], handlers);` et répondez `r.status` avec `r.jsonBody`. Modèle : `example/shelf_server.dart`.
4. App Flutter (si besoin) : `import 'package:technas_pay/app.dart';`, demandez `checkoutUrl` à VOTRE backend, vérifiez `isTechnasCheckoutUrl(url)`, ouvrez-le (`url_launcher`), puis relisez le statut auprès de VOTRE backend.
5. Ajoutez un test qui envoie `pay.createTestWebhook(...)` à la route (voir `test/technas_pay_test.dart`), puis lancez-le.

## Obligatoire

- **`amount`** : un `int` en unité principale (`5000` = 5 000 FCFA, jamais × 100), calculé côté serveur.
- **`reference`** : `retryReference(orderId, attempt)`. Voir la règle de relance.
- **`customer`** : `{'email': ..., 'name': ...}` de vrais champs du client, jamais inventés. Ajoutez `'country'` et `'phone'` si l'application les connaît.
- **`returnUrl`** : en https en production.

## La devise est automatique

- **Ne passez pas `currency`** si l'application vend en francs CFA : elle suit le pays du client (TG → XOF, CM → XAF, même montant) ; sans pays, le client choisit sur la page.
- **Ne fixez pas `defaultCurrency`** : il empêcherait ce choix.
- **Hors zone, les montants payés peuvent avoir des centimes** (`121.96` GHS) : stockez-les en `num` (base : `NUMERIC`), ne les arrondissez pas.
- Dans le webhook, `event.payment!.originalAmount` est le montant demandé en F CFA ; `amount` et `currency` sont ce qui a été payé.

## Clients hors zone franc CFA : une option à risque, décidée par l'utilisateur

- **Technas ne couvre aucun risque de change.** Avant `setFxMode(mode: 'local', acceptRisk: true)` :
  1. lisez `(await pay.getFxMode()).risks['local']` (et `risks['markup']` si un supplément est prévu) ;
  2. **montrez ce texte à l'utilisateur, en entier, et expliquez-le simplement** ;
  3. attendez son accord explicite, en toutes lettres ;
  4. seulement ensuite, appelez `setFxMode`.
- **N'activez jamais une option de vous-même**, et ne passez jamais `acceptRisk: true` sans cet accord.
- **`local`** : solde tenu et reversé dans la monnaie du client ; il faut un numéro de reversement **confirmé** dans cette monnaie, sinon le pays reste fermé (`no_payout_number`).
- **`converted`** : PAS ENCORE OUVERT (`fx_mode_unavailable`). Seules les options de `getFxMode().availableModes` existent.
- **Ne promettez jamais** un pays que `getFxMode()` ne donne pas `available == true`.
- Branchez `onFxModeUpdated` : un changement que l'utilisateur n'a pas fait signale une clé compromise.

## Sécurité

- **Le secret reste côté serveur** : ni template, ni réponse JSON, ni log, ni commit, ni URL.
- **Vérifiez la signature de chaque webhook** : `handleWebhook` / `verifyWebhook` le font. Un secret `tps_test_` ne vérifie que les webhooks de test, `tps_live_` que ceux du réel.
- **Corps brut** : shelf `request.readAsString()`, Dart Frog `context.request.body()`. Jamais `jsonDecode` puis `jsonEncode` avant la vérification : la signature ne correspondrait plus.
- **Seul le webhook prouve le paiement.** Ne marquez jamais une commande payée depuis la page `returnUrl`.
- **Réservez à un administrateur** les remboursements et le numéro de reversement.

## Paiement par carte

1. **Compte carte, une fois** : au clic du RESPONSABLE, `final link = await pay.startCardOnboarding(country: 'TG', returnUrl: ..., refreshUrl: ...)`, puis redirigez-le vers `link.url`, sur la page sécurisée de notre partenaire carte (Stripe), qui vous fera accepter son contrat (identité et banque ; le lien expire en minutes).
2. **Attendez `(await pay.getCardAccount()).canAcceptPayments`** (ou `onCardAccountUpdated`). Avant, `method: 'card'` lève `card_account_not_ready` (`e.accountStatus`).
3. **Faire payer** : `pay.askForPayment(method: 'card', amount: 12.5, currency: 'EUR', ...)`. Devise obligatoire, décimales permises.
4. **L'argent va directement sur le compte carte**, commission Technas déjà retirée : il n'apparaît pas dans `getBalance()`. Un remboursement repart sur la carte (`refund.kind == 'card'`).
5. **Tableau de bord** : `pay.getCardDashboardLink()` → le tableau de bord de votre compte carte, identifiants du responsable.
6. **App** : `pay.appRoutes(..., card: true, authorizeAdmin: ...)`. Côté Flutter, `order: {'orderId': id, 'method': 'card'}` ; l'écran du marchand utilise `cardAccount()` et `startCardOnboarding(...)` de `TechnasPayClient`.

## Seuil d'identité

En réel, un compte sans pièce d'identité vérifiée voit ses **nouveaux** paiements mobile money refusés (`kyc_required`) au-delà de 1 000 000 F CFA encaissés en cumul, ou 30 jours après son premier paiement réel encaissé. Rien de ce qui existe n'est bloqué (paiement en cours, remboursement, reversement, lecture). La carte n'est pas concernée. Le responsable du compte dépose sa pièce dans la console (`consoleUrl`).

- **Lisez `pay.getAccountKyc()`** pour afficher l'état au **marchand** (tableau de bord, écran d'administration), jamais au client final : `stage` (`ok`, `soon`, `blocked`, `verified`, `not_applicable`), `collectedXof` / `thresholdXof`, `deadline`, `consoleUrl`. Une valeur inconnue de `stage`, `level` ou `reason` est gardée telle quelle : traitez-la comme « à vérifier dans la console ».
- **Branchez `onKycRequired`** (avis `account.kyc_required`, envoyé à 80 % du seuil, 7 jours avant l'échéance, puis au premier refus) : prévenez le responsable avec `event.kycRequired!.consoleUrl`. L'avis porte aussi l'état du compte, comme `getAccountKyc()` : `stage`, `blockReason` (`amount` | `duration`), `daysElapsed`, `graceDays`, `firstCollectedAt` ; tous facultatifs (`null` sur un avis plus ancien).
- **Sur `kyc_required`** : proposez la carte si elle est ouverte, sinon expliquez au client que le paiement mobile money n'est pas disponible pour le moment. **Ne réessayez jamais.**
- **N'écrivez jamais les chiffres en dur** (1 000 000, 30) : ils viennent de l'API (`thresholdXof`, `graceDays`).

## La règle de relance (à respecter strictement)

**Une référence = un essai. Relancez avec une NOUVELLE référence seulement après `payment.expired` (ou `get_payment` → `expired`), jamais sur `failed`.**

- Composez `retryReference(orderId, attempt)` et gardez `attempt` en base.
- Rejouer la référence d'un paiement expiré lève `payment_expired` (409) : ne réessayez pas le même appel, incrémentez `attempt`.
- Après expiration, `checkoutUrl` vaut `null` : n'envoyez jamais l'ancien lien.
- `failed` n'est **pas** définitif : le client peut encore payer sur la même page pendant une heure. Dans `onFailed`, n'annulez rien, n'envoyez pas de nouveau lien.
- `expired` est définitif. `canRetry(payment.status)` n'est vrai que là.
- Expliquez cette règle à l'utilisateur : un client relancé sur `failed` pourrait payer deux fois.
- Le client choisit lui-même une AUTRE offre (autre montant) : c'est un nouvel essai tout de suite, voir la section suivante.

## Le client change d'offre ou revient plus tard

Le client choisit une offre, arrive sur la page de paiement, ne paie pas, puis revient choisir une AUTRE offre (ou revient plus tard). Ce n'est jamais « un paiement existe déjà ».

- **Une référence = un essai.** Nouvelle offre, ou retour après expiration : un NOUVEL essai, avec une nouvelle référence `retryReference(factureId, n + 1)` (`n` gardé en base). Réutiliser la référence avec un autre montant lève `reference_conflict` (409) ; celle d'un essai expiré, `payment_expired` (409). Les routes toutes faites (`appRoutes`) le font seules.
- **Une facture n'est payée QUE sur `payment.completed`** (avis signé, `onCompleted`). Jamais sur `returnUrl`, jamais à l'ouverture de la page.
- **Un essai non payé ne bloque jamais un nouvel essai.** Même offre et essai `pending` ou `failed` : renvoyez le client sur la même page (`checkoutUrl`). Autre offre : ANNULEZ l'ancien essai (`pay.cancelPayment(ancienId)`), puis créez le nouveau avec une NOUVELLE référence ; ne refusez pas. `expired` : marquez la tentative expirée et laissez recommencer.
- **`cancelPayment` refuse quand c'est trop tard** : `payment_already_completed` (le client a payé l'ancienne offre : relisez le paiement, ne créez rien) ; `payment_in_progress` (une demande est en cours chez l'opérateur : ne créez PAS de second paiement, attendez l'avis de l'issue). Un paiement annulé reste `expired` (`canceledAt`, `cancelReason` ; `canRetry` marche tel quel), et son avis `payment.expired` porte `event.payment!.reason` = `canceled` (`timeout` pour une échéance passée, `null` dans un avis plus ancien).
- **Au retour du client**, vérifiez avec `pay.getPayment(dernierPaiementId)` avant de dire quoi que ce soit ; ne vous fiez jamais seulement à votre base. Dans l'app Flutter : `technasPay.readPayment(id)` (route `GET /payments/{id}`).
- **Un ancien essai payé APRÈS le nouveau** (le client a payé les deux pages) : n'activez rien deux fois ; remboursez l'essai en trop avec `pay.refund(paymentId)`.

```dart
/// Au clic « payer » : [montant] est celui de l'offre choisie MAINTENANT.
Future<String?> payer(Facture facture, int montant) async {
  final dernierId = facture.dernierPaiementId;
  if (dernierId != null) {
    final dernier = await pay.getPayment(dernierId); // la vérité est chez Technas
    if (dernier.status == 'completed') return null; // déjà payée
    final memeOffre = dernier.amount == montant;
    if (memeOffre && dernier.status != 'expired' && dernier.checkoutUrl != null) {
      return dernier.checkoutUrl; // pending ou failed : même page, le client peut encore payer
    }
    if (dernier.status != 'expired') {
      // Autre offre : l'ancien lien est fermé d'abord. payment_in_progress (demande en cours chez
      // l'opérateur) ou payment_already_completed (déjà payé) remontent : on ne crée alors AUCUN
      // second paiement.
      await pay.cancelPayment(dernier.id);
    }
  }
  facture.essai += 1; // nouvel essai, nouvelle référence, jamais un refus
  final paiement = await pay.askForPayment(
    amount: montant,
    reference: retryReference(facture.id, facture.essai),
    customer: {'email': facture.email, 'name': facture.nom},
    returnUrl: 'https://votre-site.example/merci',
  );
  facture.dernierPaiementId = paiement.id;
  await facture.save();
  return paiement.checkoutUrl;
}

final handlers = WebhookHandlers(onCompleted: (event) async {
  final p = event.payment!;
  final facture = await Facture.get(p.reference.substring(0, p.reference.lastIndexOf('-')));
  if (facture.payeePar != null && facture.payeePar != p.id) {
    await pay.refund(p.id); // le client a payé deux pages : on rend l'essai en trop
    return;
  }
  facture.payeePar = p.id; // payée ici, et seulement ici
  await facture.save();
});
```

## Webhooks

- **Ils peuvent arriver plusieurs fois** : vos fonctions doivent le supporter (vérifiez l'état en base ou gardez `event.id`).
- **Ne rattrapez pas leurs exceptions pour répondre 200** : elles doivent remonter (5xx) pour que Technas relivre.
- `onRefund` : prévenez le client (e-mail, SMS). Technas ne lui écrit pas. `refund.failed` : rien n'est parti, votre solde est recrédité.
- `onSettlement` : l'issue d'un reversement de votre solde vers votre numéro mobile money. `event.settlement!` porte `amount` (ce qui a quitté le solde), `fee` (frais du versement, à votre charge), `netAmount` (ce qui arrive sur le numéro), `currency`, `status`. `settlement.failed` : `amount` est recrédité sur le solde. Un champ absent se lit `null`.

## Rembourser

- `pay.refund(paymentId)` rembourse tout ce qui reste ; `amount:` une partie. L'argent repart au numéro qui a payé.
- Plafond : jamais plus que le montant payé. La commission Technas n'est pas rendue.
- `fees: 'partner'` (défaut : le client reçoit tout) ou `'customer'` (frais retirés de `sentAmount`).
- Rejouer le même appel ne rembourse pas deux fois. Deux remboursements partiels identiques voulus : une `reference` chacun.
- `insufficient_balance` : `e.missingAmount` ; `topUpBalance` puis rappeler `refund`.
- Remboursement déjà fait à la main : `recordExternalRefund`, jamais `refund` (le client serait remboursé deux fois).

## Erreurs

Attrapez `TechnasPayException` (`on TechnasPayException catch (e)`) et testez `e.code` (jamais le message). `e.retryable` vrai : refaites **le même appel**, mêmes valeurs. Selon le code : `e.missingAmount`, `e.refundableAmount`, `e.reason`, `e.risk`, `e.accountStatus`, `e.consoleUrl`, `e.version`.

| `error.code` | Que faire |
|---|---|
| `invalid_secret` | Variable absente ou mal copiée : demandez à l'utilisateur de la vérifier |
| `invalid_api_key` | Secret refusé : contacter Technas |
| `invalid_request` | Corriger le champ indiqué dans `e.errors` |
| `invalid_amount`, `amount_too_low` | Montant `int` positif, assez grand pour couvrir les frais ; `amount_too_low` : `e.minimumAmount` |
| `currency_not_enabled` | Devise non ouverte sur ce compte : contacter Technas |
| `currency_conversion_unavailable` | Client hors zone CFA en mode `none` : ne pas proposer ce pays ; voir `getFxMode()` |
| `country_not_allowed` | Le marchand ne vend pas dans ce pays : ne pas contourner |
| `method_not_enabled` | Moyen éteint sur ce compte : ne pas le proposer ; voir `getPaymentMethods()` |
| `network_not_enabled` | Réseau éteint sur ce compte : ne pas le proposer ; voir `getPaymentMethods()` |
| `network_not_available` | Réseau pas ouvert dans ce pays : ne pas le proposer ; voir `getPaymentMethods(country)` |
| `country_not_available` | Pays pas prêt : `e.reason` |
| `risk_not_accepted` | Montrer `e.risk` à l'utilisateur ; n'activer qu'avec son accord explicite |
| `fx_mode_unavailable`, `fx_channel_unavailable` | `converted` pas ouvert : proposer `local` (avec accord) ou rester en `none` |
| `quote_expired` | Le client rechoisit son pays sur la page, rien à faire |
| `reference_conflict` | Même référence, autres valeurs : ne pas réutiliser la référence |
| `payment_in_progress` | Réessayer dans une minute, même appel. Sur `cancelPayment` : ne créez PAS de second paiement, attendez l'avis de l'issue |
| `payment_already_completed` | `cancelPayment` : le paiement est déjà payé. Relire le paiement ; ne créer aucun nouvel essai |
| `payment_not_found`, `refund_not_found` | Mauvais identifiant ou autre compte |
| `payment_expired` | Essai expiré : NOUVELLE référence (`attempt + 1`), jamais le même appel |
| `payment_not_refundable` | Seul un paiement `completed` se rembourse |
| `refund_exceeds_payment` | Rembourser au plus `e.refundableAmount` |
| `refund_conflict` | Cette `reference` de remboursement a déjà servi avec d'autres valeurs |
| `insufficient_balance` | Recharger au moins `e.missingAmount`, puis rappeler |
| `payer_unknown`, `refund_network_unavailable` | Rembourser le client autrement, prévenir Technas |
| `provider_unavailable`, `unavailable`, `network_error` | Panne passagère : refaire le même appel |
| `rate_limited` | Ralentir, réessayer |
| `test_only` | Fonction de test appelée avec un secret réel |
| `kyc_required` (409) | Seuil d'identité atteint (`e.reason` : `amount` ou `duration`) : proposer la carte ou expliquer au client que le mobile money n'est pas disponible pour le moment, prévenir le responsable (`e.consoleUrl`). Jamais réessayer |
| `contract_required` (409) | Le responsable doit accepter le contrat `e.version` dans la console (`e.consoleUrl`). Jamais réessayer |

## Vérifier l'intégration

Avec un secret `tps_test_`, aucun argent ne circule.

1. Déclenchez un paiement : `checkoutUrl` ouvre une page de test (« réussi », « refusé », « expiration »).
2. Sans navigateur : `pay.simulateTestPayment(id, 'completed')`, puis `pay.getPaymentByReference(reference)`.
3. Relance : sur un autre paiement, `'failed'` (rien ne doit être relancé), puis `'expired'` (`onExpired` incrémente la tentative).
4. Remboursez avec `pay.refund(payment.id)` : en test, terminé aussitôt.
5. Le webhook n'arrive sur votre poste que si Technas connaît une adresse publique. Sinon, testez la route avec `createTestWebhook`, et demandez à l'utilisateur de transmettre à son contact Technas l'adresse d'un tunnel.

## Passer en réel

Remplacez seulement le secret par `tps_live_…`. `returnUrl` doit être en https. Cette étape revient à l'utilisateur et à Technas : ne la faites pas de votre propre initiative.
