# technas_pay (Dart)

Encaissez des paiements mobile money et par carte via Technas depuis un serveur Dart (shelf, Dart Frog, serverpod), et ouvrez la page de paiement depuis une app Flutter **sans jamais y mettre de clé**.

**Technas Pay réunit le mobile money et la carte dans un seul SDK, du serveur jusqu'à l'app Flutter.** Carte : 1 % (plus les frais de votre compte carte). Mobile money : 2 % (les frais de l'opérateur sont payés par le client). Sans abonnement, et une clé de test sans papier pour commencer.

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
      ref: v0.4.1
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

Votre app Flutter les appelle avec `TechnasPayClient(baseUrl: '…/api/technas-pay')`. Contrat : [`contract/app-contract.v1.json`](contract/app-contract.v1.json), rejoué ici, côté Flutter et dans les SDK Node et Python.

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
| `listTransactions(limit:, status:, cursor:)` | Historique paginé |
| `refund(paymentId, amount:?, fees: 'partner'\|'customer', reference:?)` | Rembourser au numéro qui a payé |
| `recordExternalRefund(paymentId, amount:, method:, note:?, recordedBy:?)` | Noter un remboursement fait hors Technas |
| `getRefund(id)` | Statut d'un remboursement |
| `topUpBalance(amount:, currency:, returnUrl:?)` | Recharger le solde |
| `getBalance()`, `getSettlements()` | Solde par devise, reversements |
| `getFxMode()`, `setFxMode(mode:, acceptRisk:, markupPct:?)` | Clients hors zone franc CFA (option à risque) |
| `setCountryRules(allowed:?, excluded:)` | Où vous vendez |
| `getPayoutNetworks(country)`, `getPayoutDestination()`, `setPayoutDestination(...)` | Numéro de reversement |
| `verifyWebhook(raw, signature)`, `handleWebhook(raw, signature, handlers)` | Webhooks |
| `createTestWebhook(type, reference:, amount:, currency:)` | Webhook signé pour vos tests |
| `simulateTestPayment(id, 'completed'\|'failed'\|'expired')` | Jouer le payeur en test |

Erreurs : `TechnasPayException` avec `code` (à tester), `retryable`, et selon le code `missingAmount`, `refundableAmount`, `reason`, `risk`. Liste et conduite à tenir : [AGENTS.md](AGENTS.md#erreurs).

## Paiement par carte

1. **Compte carte, une fois** : au clic du RESPONSABLE, `final link = await pay.startCardOnboarding(country: 'TG', returnUrl: ..., refreshUrl: ...)`, puis redirigez-le vers `link.url`, sur la page sécurisée de notre partenaire carte (Stripe), qui vous fera accepter son contrat (identité et banque ; le lien expire en minutes).
2. **Attendez `(await pay.getCardAccount()).canAcceptPayments`** (ou `onCardAccountUpdated`). Avant, `method: 'card'` lève `card_account_not_ready` (`e.accountStatus`).
3. **Faire payer** : `pay.askForPayment(method: 'card', amount: 12.5, currency: 'EUR', ...)`. Devise obligatoire, décimales permises.
4. **L'argent va directement sur le compte carte**, commission Technas déjà retirée : il n'apparaît pas dans `getBalance()`. Un remboursement repart sur la carte (`refund.kind == 'card'`).
5. **Tableau de bord** : `pay.getCardDashboardLink()` → le tableau de bord de votre compte carte, identifiants du responsable.
6. **App** : `pay.appRoutes(..., card: true, authorizeAdmin: ...)`. Côté Flutter, `order: {'orderId': id, 'method': 'card'}` ; l'écran du marchand utilise `cardAccount()` et `startCardOnboarding(...)` de `TechnasPayClient`.

## La règle de relance

**Une référence = un essai.** `failed` n'est pas définitif : le client peut encore payer sur la même page pendant une heure. Ne relancez qu'après `payment.expired`, avec `retryReference(orderId, attempt + 1)`.

## Développer

```bash
dart pub get
TECHNAS_PAY_SECRET=tps_test_x.y dart test
```

Les tests tournent contre un faux serveur en mémoire ([test/fake_gateway.dart](test/fake_gateway.dart)).

## Licence

MIT.
