# technas_pay_flutter

Faites payer depuis une app Flutter via Technas Pay (mobile money en zone franc CFA et au-delà) **sans aucune clé dans l'app**.

Votre backend crée le paiement et garde le secret. L'app ouvre la page Technas, relit l'état auprès de **votre** backend et l'affiche : préparation, attente, payé, refusé (pas définitif), expiré, vérification en cours.

Vous intégrez avec un assistant de code ? Dites-lui de lire [AGENTS.md](AGENTS.md).

## Intégration complète

**Côté serveur** (ici Node/Express ; Python, Next.js et Dart plus bas), les routes sont toutes faites. Vous ne fournissez que votre authentification et la lecture de la commande en base :

```js
const routes = pay.appRoutes({
  authorize: (req) => verifierSession(req.headers.authorization),        // null → 401
  resolveOrder: async (orderId, user) => {                                // relue EN BASE, null → 404
    const o = await db.orders.find({ id: orderId, userId: user.id });
    return o && { amount: o.total, customer: { email: user.email, name: user.name } };
  },
  returnUrl: "https://votre-app.com/paiement/retour",
  webhooks: { onCompleted: (e) => db.orders.markPaid(e.payment.reference) },
});
app.use("/api/technas-pay", routes.node);
```

**Côté app** :

```dart
import 'package:technas_pay_flutter/technas_pay_flutter.dart';

final technasPay = TechnasPayClient(
  baseUrl: 'https://api.votre-app.com/api/technas-pay',
  headers: () async => {'Authorization': 'Bearer ${await session.token()}'}, // VOTRE session
);

final result = await showTechnasPayment(context, backend: technasPay, order: {'orderId': order.id});
if (result?.isPaid ?? false) { /* la commande est payée (votre backend a reçu le webhook) */ }
```

C'est tout. L'app ouvre la page Technas, relit le statut, gère le refus, l'expiration et le nouvel essai. Elle n'a jamais la clé et n'envoie jamais le montant.

| Serveur | Montage des routes |
|---|---|
| Node / Express / Nest | `app.use("/api/technas-pay", pay.appRoutes({...}).node)` (avant `express.json()`) |
| Next.js | `app/api/technas-pay/[...path]/route.ts` : `export const { GET, POST } = pay.appRoutes({...}).nextHandlers("/api/technas-pay")` |
| Python FastAPI | `app.include_router(pay.app_routes(authorize=..., resolve_order=...).fastapi_router())` |
| Python Flask / Django | `.flask_blueprint()` / `path("api/technas-pay/<path:rest>", routes.django_view())` |
| Dart shelf / Dart Frog | `technasPayShelfHandler(pay.appRoutes(...))` monté sur `/api/technas-pay/` (`package:technas_pay/shelf.dart`) |

Routes : `GET /methods?orderId=`, `POST /payments` `{orderId}`, `GET /payments/{id}`, `POST /webhook`. La dernière est l'adresse de webhook à déclarer à Technas. Les essais expirés sont sautés tout seuls (`42-1`, `42-2`…) : rien à stocker côté serveur. Le contrat [`contract/app-contract.v1.json`](../contract/app-contract.v1.json) est rejoué par ce client et par chaque SDK serveur.

`technasPay.methods(orderId)` rend les moyens ouverts pour une commande (mobile money ; la carte arrive avec le compte carte du marchand).

Vos routes s'appellent autrement ? Implémentez `TechnasPayBackend` (deux méthodes).

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
