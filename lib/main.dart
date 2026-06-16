import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:genui_shopping_assistant/app/view/app.dart';
import 'package:genui_shopping_assistant/firebase_options.dart';
import 'package:logging/logging.dart';

void main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen(
    (r) => debugPrint('[${r.loggerName}] ${r.level.name}: ${r.message}'),
  );
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on UnsupportedError {
    // Firebase not configured for this platform (e.g. macOS desktop).
    // The app still loads; the Gemini provider will be unavailable.
  }
  runApp(const App());
}
