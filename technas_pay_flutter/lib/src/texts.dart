import 'package:flutter/widgets.dart';

/// Les textes du SDK, en six langues (fr, en, pt, es, de, it), au vouvoiement : le SDK parle
/// pour VOTRE marque. Pour votre ton (tutoiement…) ou une autre langue, passez vos propres
/// [TechnasPayTexts] (`TechnasPayTexts.fr.copyWith(...)` ou un constructeur complet).
@immutable
class TechnasPayTexts {
  const TechnasPayTexts({
    required this.preparing,
    required this.waitingTitle,
    required this.waitingBody,
    required this.reopen,
    required this.paidTitle,
    required this.paidBody,
    required this.failedTitle,
    required this.failedBody,
    required this.expiredTitle,
    required this.expiredBody,
    required this.payAgain,
    required this.checkingTitle,
    required this.checkingBody,
    required this.checkNow,
    required this.mismatchTitle,
    required this.mismatchBody,
    required this.errorTitle,
    required this.errorBody,
    required this.retry,
    required this.close,
    required this.untrustedLink,
  });

  final String preparing;
  final String waitingTitle;
  final String waitingBody;
  final String reopen;
  final String paidTitle;
  final String paidBody;
  final String failedTitle;
  final String failedBody;
  final String expiredTitle;
  final String expiredBody;
  final String payAgain;
  final String checkingTitle;
  final String checkingBody;
  final String checkNow;
  final String mismatchTitle;
  final String mismatchBody;
  final String errorTitle;
  final String errorBody;
  final String retry;
  final String close;
  final String untrustedLink;

  static const fr = TechnasPayTexts(
    preparing: 'Préparation du paiement…',
    waitingTitle: 'Paiement en cours',
    waitingBody: 'Validez le paiement sur la page qui vient de s\'ouvrir, puis sur votre téléphone si votre opérateur vous le demande.',
    reopen: 'Rouvrir la page',
    paidTitle: 'Paiement reçu',
    paidBody: 'Merci, votre paiement est confirmé.',
    failedTitle: 'Paiement refusé',
    failedBody: 'Rien n\'a été débité. Vous pouvez réessayer sur la même page tant qu\'elle est ouverte.',
    expiredTitle: 'Lien expiré',
    expiredBody: 'Rien n\'a été payé. Vous pouvez relancer le paiement.',
    payAgain: 'Payer à nouveau',
    checkingTitle: 'Vérification en cours',
    checkingBody: 'Nous attendons encore la réponse de l\'opérateur. Si vous avez payé, la confirmation arrivera d\'elle-même.',
    checkNow: 'Vérifier maintenant',
    mismatchTitle: 'Montant différent',
    mismatchBody: 'Le montant reçu ne correspond pas à la commande. Contactez le vendeur avant de payer à nouveau.',
    errorTitle: 'Connexion impossible',
    errorBody: 'Vérifiez votre connexion, puis réessayez.',
    retry: 'Réessayer',
    close: 'Fermer',
    untrustedLink: 'Ce lien de paiement est inattendu : il n\'a pas été ouvert.',
  );

  static const en = TechnasPayTexts(
    preparing: 'Preparing your payment…',
    waitingTitle: 'Payment in progress',
    waitingBody: 'Confirm the payment on the page that just opened, then on your phone if your operator asks you to.',
    reopen: 'Reopen the page',
    paidTitle: 'Payment received',
    paidBody: 'Thank you, your payment is confirmed.',
    failedTitle: 'Payment declined',
    failedBody: 'Nothing was charged. You can try again on the same page while it is open.',
    expiredTitle: 'Link expired',
    expiredBody: 'Nothing was paid. You can start the payment again.',
    payAgain: 'Pay again',
    checkingTitle: 'Still checking',
    checkingBody: 'We are still waiting for the operator. If you paid, the confirmation will arrive on its own.',
    checkNow: 'Check now',
    mismatchTitle: 'Amount mismatch',
    mismatchBody: 'The amount received does not match the order. Contact the seller before paying again.',
    errorTitle: 'Connection failed',
    errorBody: 'Check your connection, then try again.',
    retry: 'Try again',
    close: 'Close',
    untrustedLink: 'This payment link is unexpected: it was not opened.',
  );

  static const pt = TechnasPayTexts(
    preparing: 'A preparar o pagamento…',
    waitingTitle: 'Pagamento em curso',
    waitingBody: 'Confirme o pagamento na página que acabou de abrir e depois no telemóvel, se a operadora o pedir.',
    reopen: 'Reabrir a página',
    paidTitle: 'Pagamento recebido',
    paidBody: 'Obrigado, o seu pagamento está confirmado.',
    failedTitle: 'Pagamento recusado',
    failedBody: 'Nada foi debitado. Pode tentar de novo na mesma página enquanto estiver aberta.',
    expiredTitle: 'Link expirado',
    expiredBody: 'Nada foi pago. Pode iniciar o pagamento de novo.',
    payAgain: 'Pagar de novo',
    checkingTitle: 'A verificar',
    checkingBody: 'Ainda aguardamos a resposta da operadora. Se pagou, a confirmação chegará sozinha.',
    checkNow: 'Verificar agora',
    mismatchTitle: 'Montante diferente',
    mismatchBody: 'O montante recebido não corresponde à encomenda. Contacte o vendedor antes de pagar de novo.',
    errorTitle: 'Sem ligação',
    errorBody: 'Verifique a sua ligação e tente de novo.',
    retry: 'Tentar de novo',
    close: 'Fechar',
    untrustedLink: 'Este link de pagamento é inesperado: não foi aberto.',
  );

  static const es = TechnasPayTexts(
    preparing: 'Preparando el pago…',
    waitingTitle: 'Pago en curso',
    waitingBody: 'Confirme el pago en la página que se acaba de abrir y luego en su teléfono si su operador se lo pide.',
    reopen: 'Volver a abrir',
    paidTitle: 'Pago recibido',
    paidBody: 'Gracias, su pago está confirmado.',
    failedTitle: 'Pago rechazado',
    failedBody: 'No se ha cobrado nada. Puede volver a intentarlo en la misma página mientras siga abierta.',
    expiredTitle: 'Enlace caducado',
    expiredBody: 'No se ha pagado nada. Puede iniciar el pago de nuevo.',
    payAgain: 'Pagar de nuevo',
    checkingTitle: 'Comprobando',
    checkingBody: 'Seguimos esperando la respuesta del operador. Si ha pagado, la confirmación llegará sola.',
    checkNow: 'Comprobar ahora',
    mismatchTitle: 'Importe distinto',
    mismatchBody: 'El importe recibido no coincide con el pedido. Contacte con el vendedor antes de volver a pagar.',
    errorTitle: 'Sin conexión',
    errorBody: 'Compruebe su conexión y vuelva a intentarlo.',
    retry: 'Reintentar',
    close: 'Cerrar',
    untrustedLink: 'Este enlace de pago es inesperado: no se ha abierto.',
  );

  static const de = TechnasPayTexts(
    preparing: 'Zahlung wird vorbereitet…',
    waitingTitle: 'Zahlung läuft',
    waitingBody: 'Bestätigen Sie die Zahlung auf der geöffneten Seite und danach auf Ihrem Handy, falls Ihr Anbieter das verlangt.',
    reopen: 'Seite öffnen',
    paidTitle: 'Zahlung erhalten',
    paidBody: 'Danke, Ihre Zahlung ist bestätigt.',
    failedTitle: 'Zahlung abgelehnt',
    failedBody: 'Es wurde nichts abgebucht. Sie können es auf derselben Seite erneut versuchen, solange sie offen ist.',
    expiredTitle: 'Link abgelaufen',
    expiredBody: 'Es wurde nichts bezahlt. Sie können die Zahlung neu starten.',
    payAgain: 'Erneut zahlen',
    checkingTitle: 'Wird geprüft',
    checkingBody: 'Wir warten noch auf die Antwort des Anbieters. Wenn Sie bezahlt haben, kommt die Bestätigung von selbst.',
    checkNow: 'Jetzt prüfen',
    mismatchTitle: 'Betrag abweichend',
    mismatchBody: 'Der erhaltene Betrag passt nicht zur Bestellung. Wenden Sie sich an den Verkäufer, bevor Sie erneut zahlen.',
    errorTitle: 'Keine Verbindung',
    errorBody: 'Prüfen Sie Ihre Verbindung und versuchen Sie es erneut.',
    retry: 'Erneut versuchen',
    close: 'Schließen',
    untrustedLink: 'Dieser Zahlungslink ist unerwartet und wurde nicht geöffnet.',
  );

  static const it = TechnasPayTexts(
    preparing: 'Preparazione del pagamento…',
    waitingTitle: 'Pagamento in corso',
    waitingBody: 'Confermi il pagamento sulla pagina appena aperta, poi sul telefono se l\'operatore lo chiede.',
    reopen: 'Riapri la pagina',
    paidTitle: 'Pagamento ricevuto',
    paidBody: 'Grazie, il pagamento è confermato.',
    failedTitle: 'Pagamento rifiutato',
    failedBody: 'Non è stato addebitato nulla. Può riprovare sulla stessa pagina finché resta aperta.',
    expiredTitle: 'Link scaduto',
    expiredBody: 'Non è stato pagato nulla. Può avviare di nuovo il pagamento.',
    payAgain: 'Paga di nuovo',
    checkingTitle: 'Verifica in corso',
    checkingBody: 'Attendiamo ancora la risposta dell\'operatore. Se ha pagato, la conferma arriverà da sola.',
    checkNow: 'Verifica ora',
    mismatchTitle: 'Importo diverso',
    mismatchBody: 'L\'importo ricevuto non corrisponde all\'ordine. Contatti il venditore prima di pagare di nuovo.',
    errorTitle: 'Connessione assente',
    errorBody: 'Controlli la connessione e riprovi.',
    retry: 'Riprova',
    close: 'Chiudi',
    untrustedLink: 'Questo link di pagamento è inatteso: non è stato aperto.',
  );

  static const byLanguage = {'fr': fr, 'en': en, 'pt': pt, 'es': es, 'de': de, 'it': it};

  /// Les textes de la langue de l'app ; l'anglais pour une langue non couverte.
  static TechnasPayTexts of(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context);
    return byLanguage[locale?.languageCode] ?? en;
  }
}
