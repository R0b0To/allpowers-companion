import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/main_shell.dart';
import 'services/foreground_service.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Must be called before runApp — registers the inter-isolate communication
  // port that flutter_foreground_task needs to relay messages between the
  // service isolate and the UI isolate.
  ForegroundService.initCommunicationPort();

  // Edge-to-edge rendering.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  AppTheme.applySystemOverlay();

  runApp(const ApCompanionApp());
}

class ApCompanionApp extends StatelessWidget {
  const ApCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AP Companion',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      supportedLocales: const [
        Locale('en'),
        Locale('it'),
      ],
      localeResolutionCallback: (locale, supportedLocales) {
        for (final supported in supportedLocales) {
          if (supported.languageCode == locale?.languageCode) return supported;
        }
        return supportedLocales.first;
      },
      home: const MainShell(),
      //home: const AutomationTestScreen(),
    );
  }
}