# technas_pay (Dart)

Encaissez des paiements mobile money via Technas depuis un serveur Dart (shelf, Dart Frog, serverpod), et ouvrez la page de paiement depuis une app Flutter **sans jamais y mettre de clé**.

Vous intégrez avec un assistant de code (Codex, Claude Code…) ? Dites-lui de lire [AGENTS.md](AGENTS.md).

C'est la même API que le SDK TypeScript [`@technas/pay`](https://github.com/Technas-Organization/technas-pay-node) et le SDK [Python](https://github.com/Technas-Organization/technas-pay-python).

Deux bibliothèques dans un paquet :

| Import | Où | Contenu |
|---|---|---|
| `package:technas_pay/technas_pay.dart` | **Serveur** uniquement | Client complet avec le secret : paiements, remboursements, change, webhooks |
| `package:technas_pay/app.dart` | App Flutter, web | Sans secret : statuts (`canRetry`, `isFinal`), `retryReference`, `isTechnasCheckoutUrl` |

Le client serveur **refuse de se construire dans une app Flutter** : un secret embarqué dans une app se lit en quelques minutes.

## 1. Installer

```yaml
dependencies:
  technas_pay:
    git:
      url: https://github.com/Technas-Organization/technas-pay-dart.git
      ref: v0.1.0
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

## 4. App Flutter : ouvrir la page de paiement

L'app ne parle **qu'à votre backend**. Exemple avec `url_launcher` :

```dart
import 'package:technas_pay/app.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> payer(String orderId) async {
  // 1. Votre backend crée le paiement (avec TechnasPay) et rend checkoutUrl.
  final checkoutUrl = await monBackend.payerCommande(orderId);
  // 2. On n'ouvre qu'une vraie page Technas.
  if (!isTechnasCheckoutUrl(checkoutUrl)) throw StateError('Lien de paiement inattendu');
  await launchUrl(Uri.parse(checkoutUrl!), mode: LaunchMode.externalApplication);
}

// 3. Au retour (returnUrl en lien profond, ou reprise de l'app), relisez le statut
//    auprès de VOTRE backend, qui le tient du webhook.
final status = await monBackend.statutCommande(orderId);
if (canRetry(status)) { /* lien expiré : proposer de payer à nouveau */ }
```

La page `returnUrl` ne prouve rien : seul le webhook reçu par votre backend prouve le paiement.

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
