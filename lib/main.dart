import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/main_shell.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-edge rendering — content draws behind the system bars and we
  // colour them ourselves in AppTheme.applySystemOverlay().
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
        return supportedLocales.first; // Default to English.
      },
      home: const MainShell(),
    );
  }
}