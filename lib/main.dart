import 'package:flutter/material.dart';
import 'screens/main_shell.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AP Companion',
      themeMode: ThemeMode.dark,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      supportedLocales: const [
        Locale('en', ''),
        Locale('it', ''),
      ],
      localeResolutionCallback: (locale, supportedLocales) {
        for (final supported in supportedLocales) {
          if (supported.languageCode == locale?.languageCode) return supported;
        }
        return supportedLocales.first;
      },
      home: const MainShell(),
    );
  }
}