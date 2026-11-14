import 'package:flutter/material.dart';

import 'backend.dart';
import 'controller.dart';
import 'texts.dart';

/// L'écran d'un paiement : un état à la fois, une action claire par état.
///
/// Il suit le thème de l'app (`Theme.of(context)`) ; aucune couleur n'est écrite ici.
class TechnasPaymentView extends StatelessWidget {
  const TechnasPaymentView({super.key, required this.controller, this.texts, this.onClose});

  final TechnasPaymentController controller;

  /// Vos textes ; par défaut ceux de la langue de l'app.
  final TechnasPayTexts? texts;

  /// Bouton « Fermer », montré quand le paiement est terminé.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _content(context, texts ?? TechnasPayTexts.of(context)),
    );
  }

  Widget _content(BuildContext context, TechnasPayTexts t) {
    final scheme = Theme.of(context).colorScheme;
    switch (controller.phase) {
      case TechnasPaymentPhase.preparing:
        return _Etat(key: const ValueKey('technas-pay-preparing'), busy: true, title: t.preparing);
      case TechnasPaymentPhase.waiting:
        return _Etat(
          key: const ValueKey('technas-pay-waiting'),
          busy: true,
          title: t.waitingTitle,
          body: t.waitingBody,
          primary: (t.reopen, controller.reopen),
          secondary: (t.checkNow, controller.checkNow),
        );
      case TechnasPaymentPhase.failed:
        return _Etat(
          key: const ValueKey('technas-pay-failed'),
          icon: Icons.info_outline,
          iconColor: scheme.primary,
          title: t.failedTitle,
          body: t.failedBody,
          primary: (t.reopen, controller.reopen),
          secondary: (t.checkNow, controller.checkNow),
        );
      case TechnasPaymentPhase.paid:
        return _Etat(
          key: const ValueKey('technas-pay-paid'),
          icon: Icons.check_circle,
          iconColor: scheme.primary,
          title: t.paidTitle,
          body: t.paidBody,
          primary: onClose == null ? null : (t.close, onClose!),
        );
      case TechnasPaymentPhase.expired:
        return _Etat(
          key: const ValueKey('technas-pay-expired'),
          icon: Icons.schedule,
          iconColor: scheme.onSurfaceVariant,
          title: t.expiredTitle,
          body: t.expiredBody,
          primary: (t.payAgain, controller.retry),
          secondary: onClose == null ? null : (t.close, onClose!),
        );
      case TechnasPaymentPhase.mismatch:
        return _Etat(
          key: const ValueKey('technas-pay-mismatch'),
          icon: Icons.warning_amber_rounded,
          iconColor: scheme.error,
          title: t.mismatchTitle,
          body: t.mismatchBody,
          primary: onClose == null ? null : (t.close, onClose!),
        );
      case TechnasPaymentPhase.stillChecking:
        return _Etat(
          key: const ValueKey('technas-pay-checking'),
          icon: Icons.hourglass_bottom,
          iconColor: scheme.onSurfaceVariant,
          title: t.checkingTitle,
          body: t.checkingBody,
          primary: (t.checkNow, controller.checkNow),
          secondary: onClose == null ? null : (t.close, onClose!),
        );
      case TechnasPaymentPhase.error:
        final e = controller.error;
        final detail = e is TechnasBackendException && !e.retryable ? e.message : null;
        return _Etat(
          key: const ValueKey('technas-pay-error'),
          icon: Icons.wifi_off,
          iconColor: scheme.error,
          title: t.errorTitle,
          body: detail ?? t.errorBody,
          primary: (t.retry, controller.retry),
          secondary: onClose == null ? null : (t.close, onClose!),
        );
      case TechnasPaymentPhase.untrustedLink:
        return _Etat(
          key: const ValueKey('technas-pay-untrusted'),
          icon: Icons.gpp_bad_outlined,
          iconColor: scheme.error,
          title: t.errorTitle,
          body: t.untrustedLink,
          primary: onClose == null ? null : (t.close, onClose!),
        );
    }
  }
}

class _Etat extends StatelessWidget {
  const _Etat({
    super.key,
    required this.title,
    this.body,
    this.icon,
    this.iconColor,
    this.busy = false,
    this.primary,
    this.secondary,
  });

  final String title;
  final String? body;
  final IconData? icon;
  final Color? iconColor;
  final bool busy;
  final (String, VoidCallback)? primary;
  final (String, VoidCallback)? secondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                const SizedBox(width: 48, height: 48, child: CircularProgressIndicator())
              else if (icon != null)
                Icon(icon, size: 56, color: iconColor),
              const SizedBox(height: 20),
              Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
              if (body != null) ...[
                const SizedBox(height: 12),
                Text(body!, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
              ],
              if (primary != null) ...[
                const SizedBox(height: 24),
                FilledButton(onPressed: primary!.$2, child: Text(primary!.$1)),
              ],
              if (secondary != null) ...[
                const SizedBox(height: 8),
                TextButton(onPressed: secondary!.$2, child: Text(secondary!.$1)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Ouvre un écran de paiement plein écran et rend l'état final (ou le dernier connu si la
/// personne ferme avant). Le contrôleur est créé, lancé et libéré pour vous.
Future<TechnasPaymentState?> showTechnasPayment(
  BuildContext context, {
  required TechnasPayBackend backend,
  required Map<String, Object?> order,
  TechnasPayTexts? texts,
  TechnasLinkLauncher? launcher,
  String? title,
}) {
  return Navigator.of(context).push<TechnasPaymentState?>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _TechnasPaymentPage(backend: backend, order: order, texts: texts, launcher: launcher, title: title),
    ),
  );
}

class _TechnasPaymentPage extends StatefulWidget {
  const _TechnasPaymentPage({required this.backend, required this.order, this.texts, this.launcher, this.title});

  final TechnasPayBackend backend;
  final Map<String, Object?> order;
  final TechnasPayTexts? texts;
  final TechnasLinkLauncher? launcher;
  final String? title;

  @override
  State<_TechnasPaymentPage> createState() => _TechnasPaymentPageState();
}

class _TechnasPaymentPageState extends State<_TechnasPaymentPage> {
  late final controller = TechnasPaymentController(backend: widget.backend, order: widget.order, launcher: widget.launcher);

  @override
  void initState() {
    super.initState();
    controller.start();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop(controller.state);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          title: widget.title == null ? null : Text(widget.title!),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: (widget.texts ?? TechnasPayTexts.of(context)).close,
            onPressed: _close,
          ),
        ),
        body: SafeArea(child: TechnasPaymentView(controller: controller, texts: widget.texts, onClose: _close)),
      ),
    );
  }
}
