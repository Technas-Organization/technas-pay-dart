# technas_pay_flutter : règles pour un agent de code

Consignes pour un assistant de code (Codex, Claude Code…). Appliquez-les dans l'application de l'utilisateur, pas dans ce dépôt. Le README détaille la configuration.

## Le principe, à ne jamais contourner

- **L'app Flutter ne contient AUCUNE clé Technas.** Ni en dur, ni dans `--dart-define`, ni dans un `.env` embarqué, ni dans Remote Config. Le secret (`tps_test_…` / `tps_live_…`) vit sur le BACKEND de l'utilisateur.
- L'app ne parle **qu'à ce backend** : il crée le paiement et l'app affiche l'état.
- Si l'utilisateur n'a pas de backend, il en faut un : une fonction serverless suffit (SDK [Node](https://github.com/Technas-Organization/technas-pay-node) ou [Python](https://github.com/Technas-Organization/technas-pay-python)). Dites-le-lui. Ne mettez pas la clé dans l'app « pour tester ».

## Étapes

1. **Backend : n'écrivez PAS de routes.** Montez celles du SDK serveur sous `/api/technas-pay` (tableau du README) : `pay.appRoutes({ authorize, resolveOrder, returnUrl, webhooks })` (Node/Next), `pay.app_routes(...)` (Python), `technasPayShelfHandler(pay.appRoutes(...))` (Dart).
   - `authorize(request)` : l'authentification EXISTANTE de l'app (jeton de session) ; `null` → 401.
   - `resolveOrder(orderId, user)` : relire la commande EN BASE, vérifier qu'elle est à `user`, rendre `{amount, customer: {email, name}}` ; sinon `null`.
   - `webhooks.onCompleted` marque la commande payée. Donnez à l'utilisateur l'adresse `…/api/technas-pay/webhook` à transmettre à Technas.
2. **App** : `TechnasPayClient(baseUrl: '…/api/technas-pay', headers: () async => {...jeton de session...})`, puis `showTechnasPayment(context, backend: technasPay, order: {'orderId': id})`.
3. **Lien de retour** : `returnUrl` https en App Link / Universal Link (README, § 4). Optionnel : le SDK relit au retour au premier plan.
4. **Test** : un test de widget avec un faux `TechnasPayBackend` (modèle : `test/flow_test.dart`), puis un vrai essai avec le secret `tps_test_` du backend.

## À respecter

- **L'app n'envoie jamais le montant**, seulement l'identifiant de la commande. Le backend le relit.
- **Seul le statut relu auprès du backend prouve le paiement**, jamais le retour du navigateur ni l'ouverture de `returnUrl`.
- **`failed` n'est pas définitif.** Ne proposez jamais un nouveau paiement sur `failed` : le client pourrait payer deux fois. « Payer à nouveau » n'existe qu'après `expired`, et c'est le backend qui crée le nouvel essai.
- **N'ouvrez que des pages Technas.** Le SDK refuse tout autre lien (`isTechnasCheckoutUrl`). N'ajoutez pas d'hôte à `trustedHosts` sans l'accord de Technas.
- **Biens numériques dans une app iOS ou Android** (abonnement, crédits, contenu débloqué) : le store est obligatoire (Apple 3.1.1, Google Play Billing). N'utilisez Technas Pay dans l'app que pour des **biens et services réels** (livraison, prestation, réservation). Sur le web, tout est permis. En cas de doute, demandez à l'utilisateur ce qu'il vend.
- **Ne baissez pas le rythme de relecture sous 2 s** : chaque relecture appelle le backend.
- Gardez les textes du SDK, ou passez des `TechnasPayTexts` complets. Ne mélangez pas les langues.

## Carte

- Si le serveur monte les routes avec `card: true` : `technasPay.methods(orderId)` dit si la carte est ouverte (`available`). Puis `showTechnasPayment(..., order: {'orderId': id, 'method': 'card'})` : la page Technas encaisse la carte, le reste du flux est le même.
- Écran du MARCHAND seulement (jamais celui d'un client) : `technasPay.cardAccount()` et `technasPay.startCardOnboarding(returnUrl:, refreshUrl:, country:)`. Le serveur les refuse (403) à tout autre que le marchand (`authorizeAdmin`).

## À venir

- Feuille de paiement par carte native (PaymentSheet, Apple Pay, Google Pay) : d'ici là, la carte passe par la page hébergée, avec le même code.
