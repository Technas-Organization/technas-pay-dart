// Exemple minimal : un bouton « Payer » qui ouvre le paiement d'une commande.
// Votre backend expose POST /technas-pay/payments et GET /technas-pay/payments/{id}.
import 'package:flutter/material.dart';
import 'package:technas_pay_flutter/technas_pay_flutter.dart';

void main() => runApp(const MaterialApp(home: CommandeScreen(orderId: '42')));

final backend = TechnasPayHttpBackend(
  baseUrl: 'https://api.votre-app.example',
  // Le jeton de session de VOTRE utilisateur, jamais une clé Technas.
  headers: () async => {'Authorization': 'Bearer jeton-de-session'},
);

class CommandeScreen extends StatelessWidget {
  const CommandeScreen({super.key, required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Commande 42')),
      body: Center(
        child: FilledButton(
          onPressed: () async {
            final result = await showTechnasPayment(context, backend: backend, order: {'orderId': orderId});
            if (!context.mounted) return;
            if (result?.isPaid ?? false) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Commande payée')));
            }
          },
          child: const Text('Payer'),
        ),
      ),
    );
  }
}
