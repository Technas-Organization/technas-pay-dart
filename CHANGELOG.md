## 0.1.0 — 2026-11-14

Première version, alignée sur `@technas/pay` 0.9.0 et `technas-pay` (Python) 0.1.0.
- `package:technas_pay/technas_pay.dart` (serveur) : paiements, statut, liste, solde, remboursements Technas et hors plateforme, recharges, numéros de reversement, change hors zone franc CFA, règles de pays, webhooks signés (`handleWebhook`), outils de test. Refuse de se construire dans une app Flutter.
- `package:technas_pay/app.dart` (Flutter, web) : `isTechnasCheckoutUrl`, `canRetry`, `isFinal`, `retryReference`, `currencyForCountry`, sans secret ni `dart:io`.
- Exemple shelf testé ; Dart Frog dans le README.
