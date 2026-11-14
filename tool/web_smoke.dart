// Compilé en JS par la CI : prouve que package:technas_pay/app.dart tient dans une app web/Flutter
// (aucun dart:io, aucun client à secret).
import 'package:technas_pay/app.dart';

void main() {
  print(isTechnasCheckoutUrl('https://pay-api.technas.fr/checkout/x') && canRetry('expired'));
}
