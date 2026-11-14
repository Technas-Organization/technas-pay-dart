// Technas Pay avec shelf.
//   TECHNAS_PAY_SECRET=tps_test_... dart run example/shelf_server.dart
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:technas_pay/technas_pay.dart';

final pay = TechnasPay(); // lit TECHNAS_PAY_SECRET au premier appel ; côté serveur uniquement

// Remplacez par votre base de données.
final orders = <String, Map<String, Object?>>{
  '42': {'amount': 5000, 'attempt': 1, 'paid': false, 'paymentId': null},
};

String orderOf(String reference) => reference.substring(0, reference.lastIndexOf('-'));

final handlers = WebhookHandlers(
  onCompleted: (event) => orders[orderOf(event.payment!.reference)]!['paid'] = true, // idempotent
  onExpired: (event) {
    // Seul moment où relancer : NOUVELLE référence (tentative + 1).
    final order = orders[orderOf(event.payment!.reference)]!;
    order['attempt'] = (order['attempt'] as int) + 1;
  },
);

Future<Response> router(Request request) async {
  if (request.method == 'POST' && request.url.path == 'api/technas-pay') {
    final raw = await request.readAsString(); // corps BRUT
    final result = await pay.handleWebhook(raw, request.headers[signatureHeader], handlers);
    // Une exception de vos fonctions remonte : shelf répond 500, Technas relivre.
    return Response(result.status, body: result.jsonBody, headers: {'content-type': 'application/json'});
  }
  final payRoute = RegExp(r'^orders/([^/]+)/pay$').firstMatch(request.url.path);
  if (request.method == 'POST' && payRoute != null) {
    final id = payRoute.group(1)!;
    final order = orders[id]!; // le montant vient de VOTRE base, jamais du client
    final payment = await pay.askForPayment(
      amount: order['amount'] as int,
      reference: retryReference(id, order['attempt'] as int),
      customer: {'email': 'awa@exemple.tg', 'name': 'Awa Mensah'},
      returnUrl: 'https://votre-site.example/merci',
    );
    order['paymentId'] = payment.id;
    return Response(303, headers: {'location': payment.checkoutUrl!});
  }
  return Response.notFound('');
}

Future<void> main() async {
  final server = await io.serve(router, InternetAddress.loopbackIPv4, 8080);
  stdout.writeln('http://${server.address.host}:${server.port}');
}
