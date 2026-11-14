/// Technas Pay, côté SERVEUR (shelf, Dart Frog, serverpod…) : encaisser du mobile money,
/// rembourser, recharger son solde, recevoir les webhooks signés.
///
/// Jamais dans une app Flutter (le constructeur refuse) : importez `package:technas_pay/app.dart`.
/// Assistants de code : lisez AGENTS.md.
library;

export 'src/app_routes.dart';
export 'src/client.dart' show TechnasPay, defaultBaseUrl, secretEnv;
export 'src/errors.dart';
export 'src/models.dart';
export 'src/status.dart';
export 'src/webhooks.dart';
