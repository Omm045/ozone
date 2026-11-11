import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() {
  return integrationDriver(
    responseDataCallback: (data) async {
      if (data != null) {
        final buildDir = Directory('build');
        if (!buildDir.existsSync()) {
          buildDir.createSync(recursive: true);
        }
        for (final entry in data.entries) {
          final file = File('build/${entry.key}.json');
          await file.writeAsString(entry.value.toString());
        }
      }
    },
  );
}
