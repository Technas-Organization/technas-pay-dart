# technas_pay_flutter

Faites payer depuis une app Flutter via Technas Pay (mobile money en zone franc CFA et au-delà) **sans aucune clé dans l'app**.

Votre backend crée le paiement et garde le secret. L'app ouvre la page Technas, relit l'état auprès de **votre** backend et l'affiche : préparation, attente, payé, refusé (pas définitif), expiré, vérification en cours.

Vous intégrez avec un assistant de code ? Dites-lui de lire [AGENTS.md](AGENTS.md).

```
App Flutter ──(1) POST /technas-pay/payments {orderId}──▶ Votre backend ──askForPayment──▶ Technas Pay
            ◀──── {payment: {id, status, checkout_url…}} ──             (secret ici seulement)
App ──(2) ouvre checkout_url (page Technas : pays, opérateur, validation) 
App ──(3) GET /technas-pay/payments/{id} ──▶ Votre backend (statut tenu par le webhook) 
```

## 1. Installer

```yaml
dependencies:
  technas_pay_flutter:
    git:
      url: https://github.com/Technas-Organization/technas-pay-dart.git
      path: technas_pay_flutter
      ref: v0.2.0
```

## 2. Côté backend : deux routes

Votre backend utilise un SDK serveur Technas Pay ([Python](https://github.com/Technas-Organization/technas-pay-python), [Node](https://github.com/Technas-Organization/technas-pay-node), [Dart](../README.md)) et expose :

| Route | Rôle |
|---|---|
| `POST /technas-pay/payments` (corps : `{"orderId": "42"}`) | Relit la commande **en base** (montant compris), appelle `askForPayment` avec `reference = orderId-tentative`, garde `payment.id`, rend `{"payment": payment.toAppJson()}` |
| `GET /technas-pay/payments/{id}` | Vérifie que ce paiement appartient à l'utilisateur connecté, rend `{"payment": (getPayment(id)).toAppJson()}` |

`toAppJson()` (`to_app_json()` en Python) ne rend que `id, reference, status, checkout_url, amount, currency, expires_at`. Ni commission, ni métadonnées. Exemple complet : [example/shelf_server.dart](../example/shelf_server.dart).

Les routes s'appellent autrement chez vous ? Implémentez `TechnasPayBackend` (deux méthodes) au lieu d'utiliser `TechnasPayHttpBackend`.

## 3. Côté app

```dart
import 'package:technas_pay_flutter/technas_pay_flutter.dart';

final backend = TechnasPayHttpBackend(
  baseUrl: 'https://api.votre-app.com',
  headers: () async => {'Authorization': 'Bearer ${await session.token()}'}, // VOTRE session
);

final result = await showTechnasPayment(context, backend: backend, order: {'orderId': order.id});
if (result?.isPaid ?? false) {
  // Affichez la commande payée. Elle l'est en base parce que votre backend a reçu le webhook.
}
```

Pour l'intégrer dans votre propre écran, utilisez `TechnasPaymentController` (`start`, `reopen`, `retry`, `checkNow`, `phase`, `state`) et `TechnasPaymentView`.

## 4. Configuration

### Lien de retour (deep link)

Après un paiement réussi, la page Technas renvoie le navigateur vers le `returnUrl` passé par votre backend. Faites-en un lien qui rouvre votre app :

- **Android (App Links)** : `https://votre-app.com/paiement/retour`, un `intent-filter` `autoVerify="true"` dans `AndroidManifest.xml`, et `/.well-known/assetlinks.json` sur votre domaine.
- **iOS (Universal Links)** : la capacité *Associated Domains* `applinks:votre-app.com`, et `/.well-known/apple-app-site-association` sur votre domaine.
- **Web** : une page de votre site, simplement.

Un schéma maison (`votreapp://`) marche aussi. Un lien https est préférable : il s'ouvre dans votre site si l'app n'est pas installée.

**Le retour ne prouve rien.** Le SDK relit le statut au retour au premier plan, que le lien ait marché ou non (retour arrière, changement d'app). Votre routeur n'a qu'à ramener l'utilisateur sur l'écran de paiement, ou sur la commande.

### Rythme de relecture

Par défaut, l'app relit aussitôt l'app revenue au premier plan, puis après 2, 3, 5, 8 et 13 s, puis toutes les 15 s. Elle s'arrête sur un statut final (`completed`, `expired`, `amount_mismatch`). Au bout de 10 min sans réponse, elle affiche « Vérification en cours » et continue de relire au rythme lent.

```dart
TechnasPaymentController(
  backend: backend,
  order: {'orderId': id},
  rhythm: const [Duration(seconds: 3), Duration(seconds: 10)], // le dernier se répète
  deadline: const Duration(minutes: 5),
);
```

Ne descendez pas sous 2 s : chaque relecture appelle votre backend. Votre backend tient le statut du webhook, et ne relit chez Technas (`getPayment`) que si ce n'est pas le cas.

### Textes et langues

Les textes existent en français, anglais, portugais, espagnol, allemand et italien, au vouvoiement. Le SDK suit la langue de l'app, et prend l'anglais par défaut. Pour un autre ton ou une autre langue, passez `texts: TechnasPayTexts(...)`.

### Thème

Couleurs et typographie viennent de `Theme.of(context)`. Le SDK n'écrit aucune couleur.

## 5. Règles

- **Aucune clé Technas dans l'app**, ni en dur, ni par `--dart-define`, ni dans un `.env` embarqué. Le client serveur `TechnasPay` refuse d'ailleurs de se construire dans Flutter.
- **Biens numériques** (abonnement, crédits, contenu débloqué) vendus **dans une app iOS ou Android** : le store est obligatoire (règle Apple 3.1.1, Google Play Billing). Technas Pay sert aux **biens et services réels** (commande livrée, prestation, réservation), partout, et à tout sur le web.
- **`failed` n'est pas définitif** : la même page peut encore réussir pendant une heure. Le SDK ne propose jamais « Payer à nouveau » sur un refus, seulement après `expired`. C'est alors votre backend qui crée un nouvel essai, avec une nouvelle référence.
- **L'app n'envoie jamais le montant.** Votre backend le relit en base.

## Développer

```bash
flutter pub get
flutter test
```

## Licence

MIT.
