## 0.7.0 — 2026-11-16

- Annuler un paiement : `cancelPayment(id)` (`POST /v1/payments/{id}/cancel`) annule DÉFINITIVEMENT un paiement que personne n'a commencé à payer ; rend le paiement (`status` `expired`, `checkoutUrl` null). Idempotent. Identifiant vide refusé avant tout appel. `Payment` : `canceledAt`, `cancelReason` ; `Payment` et `EventPayment` : `reason` (avis `payment.expired` : `canceled` ou `timeout`, null dans un avis plus ancien). Nouvelle erreur `payment_already_completed` (409, non rejouable).
- Routes toutes faites : `POST /payments/{id}/cancel` (même contrôle de propriété que `GET /payments/{id}`), et sur `reference_conflict` l'ancien essai est relu par sa référence puis annulé avant l'essai suivant ; payé ou demande en cours chez l'opérateur : aucun second paiement, l'erreur est rendue à l'app. Si l'annulation répond 404 (serveur qui ne l'a pas encore), le démarrage passe à l'essai suivant comme avant. Contrat v1 : 31 cas (`query_includes` vérifié).
- `technas_pay_flutter` 0.4.0 : `TechnasPayClient.cancelPayment(id)` (`POST {baseUrl}/payments/{id}/cancel`). Quand le client change d'offre : `cancelPayment(paiementAffiche.id)` puis `startPayment(...)` ; sur `payment_in_progress`, ne pas démarrer de second paiement ; sur `payment_already_completed`, relire et afficher « payé ». Rejoue le contrat à 31 cas.

## 0.6.0 — 2026-11-15

- Le client change d'offre ou revient plus tard. Routes toutes faites (`appRoutes`) : un `reference_conflict` (la référence d'un essai existe avec un autre montant : le client a changé d'offre) fait passer à l'essai suivant, comme `payment_expired`, dans la même borne `maxAttempts` : jamais un refus. Contrat v1 : 24 cas.
- Documentation : section « Le client change d'offre ou revient plus tard » (AGENTS.md, README, llms.txt) avec un exemple Dart ; test de scénario (essai expiré, puis nouvel essai d'un autre montant).
- `technas_pay_flutter` 0.3.2 : rejoue le contrat à 24 cas, aucun changement de code. Documentation : au retour du client, relire le paiement (`GET /payments/{id}`) avant d'afficher quoi que ce soit ; un changement d'offre est un nouvel appel de démarrage, jamais un refus.

## 0.5.1 — 2026-11-15

- Avis `account.kyc_required` : `KycRequiredNotice` porte aussi l'état du compte, comme `getAccountKyc()` : `stage`, `blockReason` (`amount` | `duration`), `daysElapsed`, `graceDays`, `firstCollectedAt`. Tous facultatifs (`null` sur un avis plus ancien). `reason` ne change pas de sens. `technas_pay_flutter` inchangé.

## 0.5.0 — 2026-11-15

- Seuil d'identité : `getAccountKyc()` (`GET /v1/account/kyc`) rend un `AccountKyc` typé (étape, cumul, seuil, échéance, `consoleUrl`). Valeurs inconnues de `stage`, `level`, `reason` gardées telles quelles.
- Avis `account.kyc_required` : `WebhookHandlers(onKycRequired:)`, contenu typé `event.kycRequired` (`KycRequiredNotice`).
- Erreurs `kyc_required` et `contract_required` (409, non rejouables) : `TechnasPayException.consoleUrl` et `.version`. Les précisions sont lues au premier niveau ou dans `details`.
- README et AGENTS.md : section « Seuil d'identité ». `technas_pay_flutter` inchangé (0.3.1) : le code `kyc_required` lui arrive tel quel par les routes de l'app.

## 0.4.1 — 2026-11-15

- Remboursement par carte : `Refund.kind` vaut désormais `card` (au lieu de `stripe`). Pendant la transition, un `stripe` reçu de l'API est lu `card`.
- Documentation : les frais de la carte s'écrivent « frais de votre compte carte » ; le tableau de bord est celui de votre compte carte. `technas_pay_flutter` 0.3.1 : textes alignés, aucun changement de code.

## 0.4.0 — 2026-11-15

- Paiement par carte : `askForPayment(method: 'card', currency:)` (décimales), `startCardOnboarding`, `getCardAccount`, `getCardDashboardLink`, `accountStatus` sur `card_account_not_ready`, `onCardAccountUpdated`, `Payment.method`, remboursement par carte.
- Routes de l'app : `card: true`, `authorizeAdmin` (`GET /card/account`, `POST /card/onboarding`), `POST /payments {method: 'card'}` (références `orderId-card-N`). `toAppJson` porte `method`.
- `technas_pay_flutter` 0.3.0 : `TechnasPaymentState.method`, `cardAccount()`, `startCardOnboarding()`. Contrat v1 : 23 cas, rejoués des deux côtés.

## 0.3.0 — 2026-11-15

- `pay.appRoutes(authorize:, resolveOrder:, returnUrl:, webhooks:)` et `technasPayShelfHandler` (`package:technas_pay/shelf.dart`, Dart Frog via `fromShelfHandler`) : les routes toutes faites que lit l'app. Essais expirés sautés automatiquement, propriété de la commande vérifiée à chaque lecture. `shelf` devient une dépendance.
- `technas_pay_flutter` 0.2.0 : `TechnasPayClient(baseUrl:)` sur ces routes, `methods(orderId)`. `TechnasPayHttpBackend` reste pour l'ancien chemin.
- Contrat partagé `contract/app-contract.v1.json` (13 cas), rejoué par le serveur et par le client.

## 0.2.0 — 2026-11-14

- `Payment.toAppJson()` : la vue sans secret qu'un backend renvoie à son app (contrat de `technas_pay_flutter`).
- Exemple shelf : routes `POST /technas-pay/payments` et `GET /technas-pay/payments/{id}`.
- Nouveau paquet `technas_pay_flutter/` (0.1.0) : faire payer depuis une app Flutter sans clé, avec l'attente, la relecture et les écrans d'état en 6 langues.

## 0.1.0 — 2026-11-14

Première version, alignée sur `@technas/pay` 0.9.0 et `technas-pay` (Python) 0.1.0.
- `package:technas_pay/technas_pay.dart` (serveur) : paiements, statut, liste, solde, remboursements Technas et hors plateforme, recharges, numéros de reversement, change hors zone franc CFA, règles de pays, webhooks signés (`handleWebhook`), outils de test. Refuse de se construire dans une app Flutter.
- `package:technas_pay/app.dart` (Flutter, web) : `isTechnasCheckoutUrl`, `canRetry`, `isFinal`, `retryReference`, `currencyForCountry`, sans secret ni `dart:io`.
- Exemple shelf testé ; Dart Frog dans le README.
