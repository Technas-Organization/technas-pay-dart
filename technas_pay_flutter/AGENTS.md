# technas_pay_flutter : règles pour un agent de code

Consignes pour un assistant de code (Codex, Claude Code…). Appliquez-les dans l'application de l'utilisateur, pas dans ce dépôt. Le README détaille la configuration.

## Le principe, à ne jamais contourner

- **L'app Flutter ne contient AUCUNE clé Technas.** Ni en dur, ni dans `--dart-define`, ni dans un `.env` embarqué, ni dans Remote Config. Le secret (`tps_test_…` / `tps_live_…`) vit sur le BACKEND de l'utilisateur.
- L'app ne parle **qu'à ce backend** : il crée le paiement et l'app affiche l'état.
- Si l'utilisateur n'a pas de backend, il en faut un : une fonction serverless suffit (SDK [Node](https://github.com/Technas-Organization/technas-pay-node) ou [Python](https://github.com/Technas-Organization/technas-pay-python)). Dites-le-lui. Ne mettez pas la clé dans l'app « pour tester ».

## Étapes

1. **Backend** : ajoutez les deux routes du contrat (voir le README, § 2).
   - `POST /technas-pay/payments` avec `{"orderId"}` : relire la commande et son montant EN BASE ; `askForPayment(reference: retryReference(orderId, attempt))` ; garder `payment.id` ; rendre `{"payment": payment.toAppJson()}`.
   - `GET /technas-pay/payments/{id}` : vérifier que le paiement appartient à l'utilisateur connecté ; rendre `{"payment": payment.toAppJson()}`.
   - Le webhook (`handleWebhook`, `onCompleted`) marque la commande payée ; `onExpired` incrémente `attempt`.
2. **App** : `TechnasPayHttpBackend(baseUrl:, headers: () async => {...jeton de session de l'utilisateur...})`, puis `showTechnasPayment(context, backend:, order: {'orderId': id})`.
3. **Lien de retour** : un `returnUrl` https en App Link / Universal Link vers l'app (README, § 4). Optionnel : le SDK relit le statut au retour au premier plan dans tous les cas.
4. **Test** : un test de widget avec un faux `TechnasPayBackend` (modèle : `test/flow_test.dart`), puis un vrai essai avec le secret `tps_test_` du backend (page de test : « réussi », « refusé », « expiration »).

## À respecter

- **L'app n'envoie jamais le montant**, seulement l'identifiant de la commande. Le backend le relit.
- **Seul le statut relu auprès du backend prouve le paiement**, jamais le retour du navigateur ni l'ouverture de `returnUrl`.
- **`failed` n'est pas définitif.** Ne proposez jamais un nouveau paiement sur `failed` : le client pourrait payer deux fois. « Payer à nouveau » n'existe qu'après `expired`, et c'est le backend qui crée le nouvel essai.
- **N'ouvrez que des pages Technas.** Le SDK refuse tout autre lien (`isTechnasCheckoutUrl`). N'ajoutez pas d'hôte à `trustedHosts` sans l'accord de Technas.
- **Biens numériques dans une app iOS ou Android** (abonnement, crédits, contenu débloqué) : le store est obligatoire (Apple 3.1.1, Google Play Billing). N'utilisez Technas Pay dans l'app que pour des **biens et services réels** (livraison, prestation, réservation). Sur le web, tout est permis. En cas de doute, demandez à l'utilisateur ce qu'il vend.
- **Ne baissez pas le rythme de relecture sous 2 s** : chaque relecture appelle le backend.
- Gardez les textes du SDK, ou passez des `TechnasPayTexts` complets. Ne mélangez pas les langues.

## À venir

- Paiement par carte natif (PaymentSheet, Apple Pay, Google Pay) : dans une prochaine version. D'ici là, la carte passe par la page hébergée, avec le même code.
- Champ téléphone avec indicatif et vérification par SMS : paquet `technas_phone`.
