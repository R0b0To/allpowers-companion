/// Minimal hand-rolled localization for English/Italian.
///
/// This intentionally avoids the full `flutter gen-l10n` / ARB pipeline
/// since the app only has a couple dozen strings. If the string list grows
/// much further, migrating to `flutter_localizations` + ARB files is
/// worth it for translator tooling and pluralization support.
class AppStrings {
  AppStrings(this.isItalian);

  final bool isItalian;

  static const Map<String, Map<String, String>> _translations = {
    'connecting': {
      'en': 'Connecting to saved Allpowers station...',
      'it': 'Connessione alla stazione Allpowers salvata...',
    },
    'forget': {'en': 'Forget Device', 'it': 'Scollega dispositivo'},
    'cancel_forget': {'en': 'Cancel & Forget Device', 'it': 'Annulla e scollega'},
    'charging': {'en': 'Charging In', 'it': 'Ingresso'},
    'discharging': {'en': 'Discharging Out', 'it': 'Uscita'},
    'usb': {'en': 'USB Ports', 'it': 'Porte USB'},
    'ac': {'en': 'AC Outlets', 'it': 'Prese AC'},
    'dc': {'en': '12V DC Sockets', 'it': 'Prese DC 12V'},
    'active': {'en': 'Active', 'it': 'Attivo'},
    'disabled': {'en': 'Disabled', 'it': 'Disattivato'},
    'controls': {'en': 'Outlet Controls', 'it': 'Controllo Prese'},
    'automation': {'en': 'Automation', 'it': 'Automazione'},
    'on_webhook': {'en': 'ON Webhook', 'it': 'Webhook ACCENSIONE'},
    'off_webhook': {'en': 'OFF Webhook', 'it': 'Webhook SPEGNIMENTO'},
    'low_limit': {'en': 'Min Limit %', 'it': 'Limite min %'},
    'high_limit': {'en': 'Max Limit %', 'it': 'Limite max %'},
    'scan': {'en': 'Scan for Battery', 'it': 'Scansiona batteria'},
    'scanning': {'en': 'Scanning...', 'it': 'Scansione...'},
    'connected': {'en': 'Connected:', 'it': 'Connesso:'},
    'start_time': {'en': 'Start Time', 'it': 'Ora inizio'},
    'end_time': {'en': 'End Time', 'it': 'Ora fine'},
    'webhook_url_missing': {'en': 'Set a webhook URL first', 'it': 'Imposta prima un URL webhook'},
    'permissions_required_title': {
      'en': 'Bluetooth & location permissions needed',
      'it': 'Permessi Bluetooth e posizione necessari',
    },
    'permissions_required_body': {
      'en': 'This app needs Bluetooth and location permissions to find your power station. '
          'Please enable them in system settings.',
      'it': "L'app necessita dei permessi Bluetooth e posizione per trovare la tua power "
          'station. Abilitali nelle impostazioni di sistema.',
    },
    'open_settings': {'en': 'Open Settings', 'it': 'Apri impostazioni'},
    'no_devices_found': {
      'en': 'No devices found yet. Make sure your station is powered on and nearby.',
      'it': 'Nessun dispositivo trovato. Assicurati che la stazione sia accesa e vicina.',
    },
  };

  String t(String key) => _translations[key]?[isItalian ? 'it' : 'en'] ?? key;
}