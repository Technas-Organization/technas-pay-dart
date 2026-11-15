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
