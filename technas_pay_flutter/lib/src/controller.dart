import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:technas_pay/app.dart' as tp;
import 'package:url_launcher/url_launcher.dart';

import 'backend.dart';

/// Où en est le paiement, vu de l'app.
enum TechnasPaymentPhase {
  /// Le backend crée le paiement.
  preparing,

  /// La page de paiement est ouverte ; on attend la réponse.
  waiting,

  /// Refus de l'opérateur, PAS définitif : la même page peut encore réussir.
  failed,

  /// Payé (statut `completed`, relu auprès du backend).
  paid,

  /// Définitif, rien payé : on peut relancer (nouvel essai côté backend).
  expired,

  /// Montant reçu différent de celui demandé : définitif, à régler avec le vendeur.
  mismatch,

  /// Pas de réponse au bout de [TechnasPaymentController.deadline] : on n'affirme rien.
  stillChecking,

  /// Le backend n'a pas pu créer le paiement (réseau, refus…).
  error,

  /// Le lien reçu n'est pas une page Technas : il n'a pas été ouvert.
  untrustedLink,
}

typedef TechnasLinkLauncher = Future<bool> Function(Uri uri);

Future<bool> _defaultLauncher(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// Rythme de relecture par défaut : aussitôt, puis 2, 3, 5, 8, 13 s, puis toutes les 15 s.
const technasDefaultRhythm = [
  Duration(seconds: 2),
  Duration(seconds: 3),
  Duration(seconds: 5),
  Duration(seconds: 8),
  Duration(seconds: 13),
  Duration(seconds: 15),
];

/// Pilote un paiement de bout en bout : demande au backend, ouvre la page Technas, relit
/// le statut à un rythme raisonnable et AU RETOUR dans l'app, s'arrête sur un statut final.
///
/// Règles tenues ici (les mêmes que les SDK serveur) :
/// - `failed` n'est pas définitif : on continue de relire, la page peut encore réussir ;
/// - `expired` est définitif : [retry] demande au backend un NOUVEL essai ;
/// - « payé » ne s'affiche que sur un statut relu auprès du backend, jamais sur le retour du
///   navigateur ;
/// - une relecture impossible n'est pas un échec : on réessaie, et au-delà de [deadline] on
///   dit « vérification en cours », sans rien affirmer.
class TechnasPaymentController extends ChangeNotifier with WidgetsBindingObserver {
  TechnasPaymentController({
    required this.backend,
    required this.order,
    TechnasLinkLauncher? launcher,
    this.rhythm = technasDefaultRhythm,
    this.deadline = const Duration(minutes: 10),
    this.trustedHosts = const {'pay-api.technas.fr'},
    this.openAutomatically = true,
  }) : _launcher = launcher ?? _defaultLauncher;

  final TechnasPayBackend backend;

  /// Ce que le backend reçoit pour retrouver la commande (son identifiant, pas son montant).
  final Map<String, Object?> order;
  final List<Duration> rhythm;
  final Duration deadline;

  /// Hôtes acceptés pour la page de paiement (`isTechnasCheckoutUrl`).
  final Set<String> trustedHosts;

  /// Ouvrir la page dès qu'elle est prête (sinon, l'écran montre « Rouvrir la page »).
  final bool openAutomatically;
  final TechnasLinkLauncher _launcher;

  TechnasPaymentPhase _phase = TechnasPaymentPhase.preparing;
  TechnasPaymentState? _state;
  Object? _error;
  Timer? _timer;
  Timer? _deadlineTimer;
  int _step = 0;
  bool _disposed = false;
  bool _reading = false;
  bool _observing = false;

  TechnasPaymentPhase get phase => _phase;
  TechnasPaymentState? get state => _state;
  Object? get error => _error;
  bool get isOver => const {
        TechnasPaymentPhase.paid,
        TechnasPaymentPhase.expired,
        TechnasPaymentPhase.mismatch,
      }.contains(_phase);

  /// Crée le paiement et ouvre la page. Sans effet si déjà lancé.
  Future<void> start() async {
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _cancel();
    _set(TechnasPaymentPhase.preparing);
    try {
      _state = await backend.startPayment(order);
    } catch (e) {
      _error = e;
      _set(TechnasPaymentPhase.error);
      return;
    }
    if (_disposed) return;
    _step = 0;
    // Au-delà du délai sans réponse finale : « vérification en cours », sans rien affirmer.
    // Les relectures continuent (au rythme lent) ; un statut final les arrête.
    _deadlineTimer?.cancel();
    _deadlineTimer = Timer(deadline, () {
      if (!isOver && _phase != TechnasPaymentPhase.untrustedLink) _set(TechnasPaymentPhase.stillChecking);
    });
    if (_applyStatus()) return;
    if (openAutomatically) await reopen();
    if (_phase != TechnasPaymentPhase.untrustedLink) {
      if (_phase == TechnasPaymentPhase.preparing) _set(TechnasPaymentPhase.waiting);
      _schedule();
    }
  }

  /// Rouvre la page de paiement en cours (jamais un lien expiré ni étranger).
  Future<void> reopen() async {
    final url = _state?.checkoutUrl;
    if (!tp.isTechnasCheckoutUrl(url, hosts: trustedHosts)) {
      _cancel();
      _set(TechnasPaymentPhase.untrustedLink);
      return;
    }
    await _launcher(Uri.parse(url!));
  }

  /// Après `expired` (ou une erreur de création) : demande au backend un NOUVEL essai.
  Future<void> retry() => start();

  /// Relit tout de suite (bouton « Vérifier maintenant », retour dans l'app).
  Future<void> checkNow() async {
    final id = _state?.id;
    if (id == null || _reading || isOver) return;
    _reading = true;
    try {
      final fresh = await backend.readPayment(id);
      if (_disposed) return;
      _state = fresh;
      _applyStatus();
    } catch (_) {
      // Relecture impossible : on n'en conclut rien, la suivante dira.
    } finally {
      _reading = false;
    }
  }

  /// Applique le statut relu ; vrai si le paiement est terminé.
  bool _applyStatus() {
    final s = _state!;
    switch (s.status) {
      case tp.PaymentStatus.completed:
        _cancel();
        _set(TechnasPaymentPhase.paid);
        return true;
      case tp.PaymentStatus.expired:
        _cancel();
        _set(TechnasPaymentPhase.expired);
        return true;
      case tp.PaymentStatus.amountMismatch:
        _cancel();
        _set(TechnasPaymentPhase.mismatch);
        return true;
      case tp.PaymentStatus.failed:
        _set(TechnasPaymentPhase.failed);
        return false;
      default:
        // Un refus suivi d'un nouvel essai sur la même page : on attend de nouveau.
        if (_phase == TechnasPaymentPhase.failed) _set(TechnasPaymentPhase.waiting);
        return false;
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (_disposed || isOver) return;
    final delay = rhythm[_step < rhythm.length ? _step : rhythm.length - 1];
    _step++;
    _timer = Timer(delay, () async {
      await checkNow();
      _schedule();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour dans l'app (lien de retour, bouton retour du navigateur) : on relit aussitôt et
    // on reprend le rythme rapide, c'est là que la réponse a le plus de chances d'être là.
    if (state == AppLifecycleState.resumed && _state != null && !isOver) {
      _step = 0;
      checkNow().then((_) => _schedule());
    }
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
  }

  void _set(TechnasPaymentPhase phase) {
    if (_disposed) return;
    _phase = phase;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
