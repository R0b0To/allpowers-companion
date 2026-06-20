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
    'tab_control': {'en': 'Control', 'it': 'Controllo'},
    'tab_automations': {'en': 'Automation', 'it': 'Automazione'},
    'automation_description': {
      'en': 'Automatically manage AC outlets and a smart plug based on '
          'battery level.',
      'it': 'Gestisce automaticamente le prese AC e una presa smart in base '
          'al livello della batteria.',
    },
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
    'on': {'en': 'ON', 'it': 'ON'},
    'off': {'en': 'OFF', 'it': 'OFF'},
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
    'webhook_url_missing': {
      'en': 'Set a webhook URL first',
      'it': 'Imposta prima un URL webhook',
    },
    'permissions_required_title': {
      'en': 'Bluetooth & location permissions needed',
      'it': 'Permessi Bluetooth e posizione necessari',
    },
    'permissions_required_body': {
      'en': 'This app needs Bluetooth and location permissions to find your '
          'power station. Please enable them in system settings.',
      'it': "L'app necessita dei permessi Bluetooth e posizione per trovare "
          'la tua power station. Abilitali nelle impostazioni di sistema.',
    },
    'open_settings': {'en': 'Open Settings', 'it': 'Apri impostazioni'},
    'no_devices_found': {
      'en': 'No devices found yet. Make sure your station is powered on and nearby.',
      'it': 'Nessun dispositivo trovato. Assicurati che la stazione sia accesa e vicina.',
    },
    'bluetooth_off_title': {
      'en': 'Bluetooth is disabled',
      'it': 'Bluetooth disattivato',
    },
    'bluetooth_off_body': {
      'en': 'Please enable Bluetooth to connect to your Allpowers station.',
      'it': 'Attiva il Bluetooth per connetterti alla tua stazione Allpowers.',
    },

    // ── Automations tab: plug control & local Tapo card ──────────────────
    'plug_control_actions': {'en': 'Plug Control Actions', 'it': 'Azioni di controllo presa'},
    'on_webhook_url': {'en': 'ON Webhook URL', 'it': 'URL Webhook ACCENSIONE'},
    'off_webhook_url': {'en': 'OFF Webhook URL', 'it': 'URL Webhook SPEGNIMENTO'},
    'on_webhook_url_fallback': {
      'en': 'Fallback ON Webhook (Optional)',
      'it': 'Webhook ACCENSIONE di riserva (opzionale)',
    },
    'off_webhook_url_fallback': {
      'en': 'Fallback OFF Webhook (Optional)',
      'it': 'Webhook SPEGNIMENTO di riserva (opzionale)',
    },
    'local_tapo_title': {'en': 'Local Tapo Plug Control', 'it': 'Controllo presa Tapo locale'},
    'local_tapo_description': {
      'en': 'Attempts to connect directly to the plug on your local network. '
          'Falls back to webhooks if direct connection is offline or fails.',
      'it': 'Tenta la connessione diretta alla presa sulla tua rete locale. '
          'In caso di errore o presa non raggiungibile, usa i webhook come riserva.',
    },
    'tapo_ip_label': {
      'en': 'Plug IP address (e.g. 192.168.1.75)',
      'it': 'Indirizzo IP presa (es. 192.168.1.75)',
    },
    'tapo_email_label': {'en': 'TP-Link account e-mail', 'it': 'E-mail account TP-Link'},
    'tapo_password_label': {'en': 'TP-Link account password', 'it': 'Password account TP-Link'},
    'test_local_handshake': {'en': 'Test Local Handshake', 'it': 'Testa connessione locale'},
    'tapo_fields_incomplete': {
      'en': 'Fill in Tapo IP, E-mail, and Password first.',
      'it': 'Inserisci prima IP, E-mail e Password del Tapo.',
    },
    'tapo_attempting_connection': {
      'en': 'Attempting local connection...',
      'it': 'Tentativo di connessione locale...',
    },
    'tapo_credentials_incomplete': {
      'en': 'Local Tapo: credentials incomplete.',
      'it': 'Tapo locale: credenziali incomplete.',
    },
    'tapo_attempting_local_on': {'en': 'Attempting local Tapo ON...', 'it': 'Tentativo Tapo locale ON...'},
    'tapo_attempting_local_off': {'en': 'Attempting local Tapo OFF...', 'it': 'Tentativo Tapo locale OFF...'},
    'tapo_local_on_successful': {'en': 'Local Tapo ON successful.', 'it': 'Tapo locale ON riuscito.'},
    'tapo_local_off_successful': {'en': 'Local Tapo OFF successful.', 'it': 'Tapo locale OFF riuscito.'},
    'tapo_local_on_failed': {
      'en': 'Local Tapo ON failed. Falling back to webhook.',
      'it': 'Tapo locale ON fallito. Uso il webhook di riserva.',
    },
    'tapo_local_off_failed': {
      'en': 'Local Tapo OFF failed. Falling back to webhook.',
      'it': 'Tapo locale OFF fallito. Uso il webhook di riserva.',
    },
    'executing_webhook': {'en': 'Executing webhook...', 'it': 'Esecuzione webhook...'},
    'webhook_failed': {'en': 'Webhook failed.', 'it': 'Webhook fallito.'},
    'webhook_successful_prefix': {'en': 'Webhook successful (Code:', 'it': 'Webhook riuscito (Codice:'},
    'webhook_failed_with_code_prefix': {'en': 'Webhook failed (Code:', 'it': 'Webhook fallito (Codice:'},
  };

  String t(String key) => _translations[key]?[isItalian ? 'it' : 'en'] ?? key;
}