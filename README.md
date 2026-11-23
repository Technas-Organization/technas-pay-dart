# technas_pay (Dart)

Encaissez des paiements mobile money et par carte via Technas depuis un serveur Dart (shelf, Dart Frog, serverpod), et ouvrez la page de paiement depuis une app Flutter **sans jamais y mettre de clé**.

**Technas Pay réunit le mobile money et la carte dans un seul SDK, du serveur jusqu'à l'app Flutter.** Carte : 1 % (plus les frais de votre compte carte, selon le pays : environ 1,5 % + 0,25 € en Europe). Mobile money : 2 %, et vous choisissez qui paie les frais : le client (vous recevez exactement votre prix) ou vous (le client paie votre prix) ; `pay.quote` dit les montants avant le paiement. Sans abonnement, et une clé de test sans papier pour commencer.

Devises et pays, pièces demandées, versements, comparaison avec les autres prestataires : [le hub Technas Pay](https://github.com/Technas-Organization/technas-pay).

Vous intégrez avec un assistant de code ? Dites-lui de lire [AGENTS.md](AGENTS.md).

C'est la même API que le SDK TypeScript [`@technas/pay`](https://github.com/Technas-Organization/technas-pay-node) et le SDK [Python](https://github.com/Technas-Organization/technas-pay-python).

Deux bibliothèques dans un paquet :

| Import | Où | Contenu |
|---|---|---|
| `package:technas_pay/technas_pay.dart` | **Serveur** uniquement | Client complet avec le secret : paiements, remboursements, change, webhooks |
| `package:technas_pay/app.dart` | App Flutter, web | Sans secret : statuts (`canRetry`, `isFinal`), `retryReference`, `isTechnasCheckoutUrl` |
| `technas_pay_flutter` (sous-dossier) | App Flutter | Le flux complet : backend, page, attente, écrans d'état en 6 langues |

Le client serveur **refuse de se construire dans une app Flutter** : un secret embarqué dans une app se lit en quelques minutes.

## 1. Installer

```yaml
dependencies:
  technas_pay:
    git:
      url: https://github.com/Technas-Organization/technas-pay-dart.git
      ref: v0.9.0
```

Sur le serveur, le secret remis par Technas va dans l'environnement :

```bash
TECHNAS_PAY_SECRET=tps_test_...
```

Un secret `tps_test_` ne déplace aucun argent. Un secret `tps_live_` encaisse pour de vrai. Le code est le même.

## 2. Serveur : demander un paiement

```dart
import 'package:technas_pay/technas_pay.dart';

final pay = TechnasPay(); // lit TECHNAS_PAY_SECRET au premier appel

final payment = await pay.askForPayment(
  amount: 5000,                                        // int : 5 000 FCFA
  reference: retryReference(order.id, order.attempt),  // "42-1" : une référence = un essai
  customer: {'email': 'client@exemple.com', 'name': 'Awa Mensah'},
  returnUrl: 'https://votre-site.com/merci',
);
order.paymentId = payment.id;
// rendez payment.checkoutUrl à votre app, ou redirigez (303) un navigateur
```

Ne passez pas `currency` si vous vendez en francs CFA : la devise suit le pays du client (`customer['country']`), ou le client choisit son pays sur la page.

### Qui paie les frais, et combien paie le client

Deux modes, en mobile money (franc CFA). Le mode par défaut est celui de votre compte (demandez à Technas de le changer) ; chaque paiement peut le surcharger avec `fees`.

| `fees` | Le client paie | Vous recevez |
|---|---|---|
| `'customer'` | votre prix + les frais du réseau de paiement + la commission Technas | **exactement votre prix** |
| `'partner'` | **votre prix**, frais compris | votre prix − les frais |

Pour savoir AVANT de créer le paiement combien le client paiera (le montant à lui afficher) et combien vous recevrez :

```dart
final q = await pay.quote(amount: 200, country: 'TG', fees: 'customer');
q.customerTotal;   // 214 : ce que le client paie (à afficher)
q.processingFee;   // 9   : frais du réseau de paiement
q.commission;      // 5   : commission Technas (2 %)
q.netAmount;       // 200 : ce que vous recevez
q.networks;        // le détail réseau par réseau (Mixx by Yas, Moov Money…)

final p = await pay.quote(amount: 1000, country: 'TG', fees: 'partner');
// p.customerTotal 1000, p.processingFee 40, p.commission 20, p.netAmount 940
```

- `pay.getFees(...)` est le même appel que `pay.quote(...)`. Rien n'est créé.
- Un paiement créé ensuite avec le même montant, le même pays et le même `fees` porte les mêmes montants : `payment.customerTotal`, `payment.processingFee`, `payment.netAmount`. `payment.amount` reste votre prix.
- Les frais du réseau de paiement suivent la grille du réseau. Le client choisit son réseau sur la page de paiement : `customerTotal` est le plus haut des réseaux possibles, `networks[i].customerTotal` le montant exact de chacun.
- L'opérateur du client (Mixx by Yas, Moov…) peut prendre ses propres frais sur le téléphone, en dehors de Technas : `networks[i].operatorFeeEstimate` en donne une estimation quand on la connaît (« environ »), jamais une promesse.
- Montant trop petit : `amount_too_low` avec `e.minimumAmount` (`TechnasPayException`). Au Togo, le réseau n'accepte rien sous 200 F : en `'partner'`, 209 F au minimum ; en `'customer'`, 200 F passent.
- Par carte, seulement `'partner'` : ajouter des frais au paiement par carte d'un consommateur est interdit en Europe. `pay.quote(amount: 20, method: 'card', currency: 'EUR')` rend la commission (`netAmount` null : les frais de la carte dépendent de la carte du client).

## 3. Serveur : recevoir le webhook

```dart
final handlers = WebhookHandlers(
  onCompleted: (event) => markPaid(event.payment!.reference),       // idempotent
  onExpired: (event) => nextAttempt(event.payment!.reference),      // seul moment où relancer
);

// shelf
final raw = await request.readAsString();                            // corps BRUT
final result = await pay.handleWebhook(raw, request.headers[signatureHeader], handlers);
return Response(result.status, body: result.jsonBody, headers: {'content-type': 'application/json'});
```

```dart
// Dart Frog : routes/api/technas-pay.dart
Future<Response> onRequest(RequestContext context) async {
  final raw = await context.request.body();
  final result = await pay.handleWebhook(raw, context.request.headers[signatureHeader], handlers);
  return Response.json(statusCode: result.status, body: result.body);
}
```

Exemple complet, testé : [example/shelf_server.dart](example/shelf_server.dart). Signature refusée : 400, aucune fonction appelée. Une exception dans votre fonction remonte (500) : Technas relivrera.

## Pour une app : les routes toutes faites

```dart
import 'package:technas_pay/shelf.dart';

final routes = pay.appRoutes<MonUser>(
  authorize: (req) => sessions.user(req.headers['authorization']),          // null → 401
  resolveOrder: (orderId, user) async {                                       // relue EN BASE, null → 404
    final o = await db.order(orderId, userId: user.id);
    return o == null ? null : AppOrder(amount: o.total, customer: {'email': user.email, 'name': user.name});
  },
  returnUrl: 'https://votre-app.com/paiement/retour',
  webhooks: WebhookHandlers(onCompleted: (e) => db.markPaid(e.payment!.reference)),
);
final router = Router()..mount('/api/technas-pay/', technasPayShelfHandler(routes)); // Dart Frog : fromShelfHandler
```

Routes : `GET /methods?orderId=`, `POST /payments` `{orderId}`, `GET /payments/{id}`, `POST /payments/{id}/cancel` (le client change d'offre : l'essai affiché est annulé), `POST /webhook`. Si la commande a changé de montant, `POST /payments` annule lui-même l'ancien essai encore ouvert ; s'il est déjà payé (`payment_already_completed`) ou qu'une demande est en cours chez l'opérateur (`payment_in_progress`), aucun second paiement n'est créé et l'erreur est rendue à l'app. Votre app Flutter les appelle avec `TechnasPayClient(baseUrl: '…/api/technas-pay')`. Contrat : [`contract/app-contract.v1.json`](contract/app-contract.v1.json), rejoué ici, côté Flutter et dans les SDK Node et Python.

## 4. App Flutter : le paquet `technas_pay_flutter`

Pour faire payer depuis une app, utilisez [`technas_pay_flutter`](technas_pay_flutter/README.md), dans ce même dépôt. Il fait tout ce que l'app doit faire, sans clé :
- demander le paiement à votre backend ;
- ouvrir la page Technas, et elle seule ;
- relire le statut au bon rythme et au retour dans l'app ;
- afficher l'état : payé, refusé (pas définitif), expiré, « payer à nouveau ».

Côté serveur, renvoyez `payment.toAppJson()` : c'est le contrat qu'il lit.

## 5. Tout le reste (serveur)

| Méthode | Rôle |
|---|---|
| `getPayment(id)`, `getPaymentByReference(ref)` | Statut ; rattraper un webhook manqué |
| `cancelPayment(id)` | Annuler un paiement que personne n'a commencé à payer (le client change d'offre) |
| `listTransactions(limit:, status:, cursor:)` | Historique paginé |
| `refund(paymentId, amount:?, fees: 'partner'\|'customer', reference:?)` | Rembourser au numéro qui a payé |
| `recordExternalRefund(paymentId, amount:, method:, note:?, recordedBy:?)` | Noter un remboursement fait hors Technas |
| `getRefund(id)` | Statut d'un remboursement |
| `topUpBalance(amount:, currency:, returnUrl:?)` | Recharger le solde |
| `quote(amount:, country:?, network:?, currency:?, fees:?, method:?)`, `getFees(...)` | Devis : ce que le client paiera, ce que vous recevrez (rien n'est créé) |
| `getBalance()`, `getSettlements()` | Solde par devise, reversements |
| `WebhookHandlers(onSettlement:)` | Issue d'un reversement : avis `settlement.completed`, `settlement.failed` |
| `getAccountKyc()` | Seuil d'identité : cumul, échéance, lien de la console |
| `getFxMode()`, `setFxMode(mode:, acceptRisk:, markupPct:?)` | Clients hors zone franc CFA (option à risque) |
| `setCountryRules(allowed:?, excluded:)` | Où vous vendez |
| `getPayoutNetworks(country)`, `getPayoutDestination()`, `setPayoutDestination(...)` | Numéro de reversement |
| `verifyWebhook(raw, signature)`, `handleWebhook(raw, signature, handlers)` | Webhooks |
| `createTestWebhook(type, reference:, amount:, currency:)` | Webhook signé pour vos tests |
| `simulateTestPayment(id, 'completed'\|'failed'\|'expired')` | Jouer le payeur en test |

Reversements : les avis `settlement.completed` et `settlement.failed` disent l'issue d'un reversement de votre solde vers votre numéro mobile money. `event.settlement!` (`SettlementNotice`) porte `id`, `amount` (ce qui a quitté le solde), `fee` (frais du versement, à votre charge), `netAmount` (ce qui arrive sur le numéro), `currency`, `status`, `createdAt` ; un champ absent se lit `null`. Sur `settlement.failed`, `amount` est recrédité sur le solde.

Erreurs : `TechnasPayException` avec `code` (à tester), `retryable`, et selon le code `missingAmount`, `refundableAmount`, `reason`, `risk`, `accountStatus`, `consoleUrl`, `version`. `kyc_required` (409, `consoleUrl`, `reason` : `amount` | `duration`) et `contract_required` (409, `consoleUrl`, `version` du contrat à accepter dans la console) ne se réessaient jamais. Liste et conduite à tenir : [AGENTS.md](AGENTS.md#erreurs).

## Seuil d'identité

En réel, un compte sans pièce d'identité vérifiée voit ses **nouveaux** paiements mobile money refusés (`kyc_required`) au-delà de 1 000 000 F CFA encaissés en cumul, ou 30 jours après son premier paiement réel encaissé. Rien de ce qui existe n'est bloqué : paiement en cours, remboursement, reversement, lecture. La carte n'est pas concernée. Le responsable du compte dépose sa pièce dans la console (`consoleUrl`).

```dart
final kyc = await pay.getAccountKyc();          // à montrer au marchand, pas au client final
if (kyc.applies && kyc.stage != 'ok') showBanner(kyc.collectedXof, kyc.thresholdXof, kyc.deadline, kyc.consoleUrl);

WebhookHandlers(onKycRequired: (e) => alertOwner(e.kycRequired!.consoleUrl)); // 80 %, J-7, premier refus
```

Les chiffres (`thresholdXof`, `graceDays`) viennent de l'API : ne les écrivez jamais en dur. L'avis `account.kyc_required` porte `reason` (`amount_80`, `deadline_7d`, `blocked`), `collectedXof`, `thresholdXof`, `deadline`, `blocked`, `consoleUrl`, et l'état du compte comme `getAccountKyc()` : `stage`, `blockReason`, `daysElapsed`, `graceDays`, `firstCollectedAt` (facultatifs : `null` sur un avis plus ancien). Sur `kyc_required`, proposez la carte ou expliquez au client que le paiement mobile money n'est pas disponible pour le moment ; ne réessayez jamais.

## Paiement par carte

1. **Compte carte, une fois** : au clic du RESPONSABLE, `final link = await pay.startCardOnboarding(country: 'TG', returnUrl: ..., refreshUrl: ...)`, puis redirigez-le vers `link.url`, sur la page sécurisée de notre partenaire carte (Stripe), qui vous fera accepter son contrat (identité et banque ; le lien expire en minutes).
2. **Attendez `(await pay.getCardAccount()).canAcceptPayments`** (ou `onCardAccountUpdated`). Avant, `method: 'card'` lève `card_account_not_ready` (`e.accountStatus`).
3. **Faire payer** : `pay.askForPayment(method: 'card', amount: 12.5, currency: 'EUR', ...)`. Devise obligatoire, décimales permises.
4. **L'argent va directement sur le compte carte**, commission Technas déjà retirée : il n'apparaît pas dans `getBalance()`. Un remboursement repart sur la carte (`refund.kind == 'card'`).
5. **Tableau de bord** : `pay.getCardDashboardLink()` → le tableau de bord de votre compte carte, identifiants du responsable.
6. **App** : `pay.appRoutes(..., card: true, authorizeAdmin: ...)`. Côté Flutter, `order: {'orderId': id, 'method': 'card'}` ; l'écran du marchand utilise `cardAccount()` et `startCardOnboarding(...)` de `TechnasPayClient`.

## La règle de relance

**Une référence = un essai.** `failed` n'est pas définitif : le client peut encore payer sur la même page pendant une heure. Ne relancez qu'après `payment.expired`, avec `retryReference(orderId, attempt + 1)`.

Le client change d'offre ou revient plus tard : c'est un NOUVEL essai (`retryReference(factureId, n + 1)`), jamais un refus, même si l'essai précédent est encore `pending` ou `failed`. Autre offre : ANNULEZ d'abord l'ancien essai (`pay.cancelPayment(ancienId)`), puis créez le nouveau avec une NOUVELLE référence. Si l'annulation répond `payment_in_progress` (une demande est en cours chez l'opérateur), ne créez PAS de second paiement : attendez l'avis de l'issue ; `payment_already_completed` : le client a payé l'ancienne offre, relisez le paiement et ne créez rien. Un paiement annulé reste `expired` (`canRetry` marche tel quel), avec `canceledAt` et `cancelReason` ; son avis `payment.expired` porte `reason` = `canceled` (`timeout` pour une échéance passée). Réutiliser une référence avec un autre montant lève `reference_conflict` ; les routes toutes faites annulent l'ancien essai et passent seules à l'essai suivant. Au retour du client, relisez le dernier essai (`getPayment`) avant de dire quoi que ce soit. La facture n'est payée que sur `payment.completed` ; si le client a payé deux pages, remboursez l'essai en trop (`refund`).

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

## Développer

```bash
dart pub get
TECHNAS_PAY_SECRET=tps_test_x.y dart test
```

Les tests tournent contre un faux serveur en mémoire ([test/fake_gateway.dart](test/fake_gateway.dart)).

## Licence

MIT.
