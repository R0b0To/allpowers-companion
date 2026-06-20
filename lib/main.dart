import 'package:flutter/material.dart';
import 'screens/battery_control_screen.dart'; // Import your screen file
import 'theme/app_theme.dart';                // Import your custom theme

void main() async {
  // 1. Ensure Flutter bindings are established before executing async code
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AP Companion',
      themeMode: ThemeMode.dark, // Enforce dark mode
      
      // Use the global theme you defined in your app_theme.dart
      theme: AppTheme.dark, 
      darkTheme: AppTheme.dark,
      
      // Automatic system language resolution (English/Italian)
      supportedLocales: const [
        Locale('en', ''),
        Locale('it', ''),
      ],
      localeResolutionCallback: (locale, supportedLocales) {
        for (var supportedLocale in supportedLocales) {
          if (supportedLocale.languageCode == locale?.languageCode) {
            return supportedLocale;
          }
        }
        return supportedLocales.first; // Default fallback (English)
      },
      
      // Load your newly modularized screen
      home: const BatteryControlScreen(),
    );
  }
}