/// Minimal hand-rolled localisation for English / Italian.
///
/// The app only has ~50 strings so the full `flutter gen-l10n` / ARB pipeline
/// would be overkill. If the string list grows significantly, migrating to
/// `flutter_localizations` + ARB files is worthwhile for translator tooling
/// and proper pluralisation support.
final class AppStrings {
  AppStrings(this.isItalian);

  final bool isItalian;

  String t(String key) => _translations[key]?[isItalian ? 'it' : 'en'] ?? key;

  static const Map<String, Map<String, String>> _translations = {
    // ── Navigation ──────────────────────────────────────────────────────────
    'tab_control': {'en': 'Control', 'it': 'Controllo'},
    'tab_automations': {'en': 'Automation', 'it': 'Automazione'},
    'tab_history': {'en': 'History', 'it': 'Cronologia'},

    // ── Connection states ───────────────────────────────────────────────────
    'connecting': {
      'en': 'Connecting to saved station…',
      'it': 'Connessione alla stazione salvata…',
    },
    'connected': {'en': 'Connected', 'it': 'Connesso'},
    'forget': {'en': 'Forget Device', 'it': 'Scollega dispositivo'},
    'cancel_forget': {'en': 'Cancel & Forget', 'it': 'Annulla e scollega'},
    'scan': {'en': 'Scan for Station', 'it': 'Cerca stazione'},
    'scanning': {'en': 'Scanning…', 'it': 'Ricerca…'},
    'no_devices_found': {
      'en': 'No devices found. Make sure your station is powered on and nearby.',
      'it': 'Nessun dispositivo trovato. Assicurati che la stazione sia accesa e vicina.',
    },

    // ── Bluetooth ───────────────────────────────────────────────────────────
    'bluetooth_off_title': {
      'en': 'Bluetooth is disabled',
      'it': 'Bluetooth disattivato',
    },
    'bluetooth_off_body': {
      'en': 'Please enable Bluetooth to connect to your Allpowers station.',
      'it': 'Attiva il Bluetooth per connetterti alla tua stazione Allpowers.',
    },

    // ── Permissions ─────────────────────────────────────────────────────────
    'permissions_required_title': {
      'en': 'Bluetooth & location permissions needed',
      'it': 'Permessi Bluetooth e posizione necessari',
    },
    'permissions_required_body': {
      'en': 'This app needs Bluetooth and location permissions to find your power station.',
      'it': "L'app necessita dei permessi Bluetooth e posizione per trovare la tua power station.",
    },
    'open_settings': {'en': 'Open Settings', 'it': 'Apri impostazioni'},
    'cancel': {'en': 'Cancel', 'it': 'Annulla'},

    // ── Metrics ─────────────────────────────────────────────────────────────
    'charging': {'en': 'Charging In', 'it': 'Ingresso'},
    'discharging': {'en': 'Discharging Out', 'it': 'Uscita'},

    // ── Energy tab ──────────────────────────────────────────────────────────
    'tab_energy': {'en': 'Energy', 'it': 'Energia'},
    'energy_description': {
      'en': 'Battery and power trends recorded from your station over time.',
      'it': 'Andamento di batteria e potenza registrato nel tempo dalla tua stazione.',
    },
    'no_energy_data': {
      'en': 'No data yet. Samples are recorded automatically while connected.',
      'it': 'Nessun dato ancora. I campioni vengono registrati automaticamente da connesso.',
    },
    'range_day': {'en': '24h', 'it': '24h'},
    'range_week': {'en': '7d', 'it': '7g'},
    'range_month': {'en': '30d', 'it': '30g'},
    'range_all': {'en': 'All', 'it': 'Tutto'},
    'battery_trend': {'en': 'Battery Level', 'it': 'Livello batteria'},
    'power_flow': {'en': 'Power Flow', 'it': 'Flusso di potenza'},
    'avg_input': {'en': 'Avg In', 'it': 'Media ingresso'},
    'avg_output': {'en': 'Avg Out', 'it': 'Media uscita'},
    'peak_input': {'en': 'Peak In', 'it': 'Picco ingresso'},
    'peak_output': {'en': 'Peak Out', 'it': 'Picco uscita'},
    'clear_energy_log': {'en': 'Clear Data', 'it': 'Cancella dati'},
    'clear_energy_log_confirm': {
      'en': 'This permanently deletes all recorded energy samples. This cannot be undone.',
      'it': 'Questo elimina permanentemente tutti i campioni energetici registrati. Non può essere annullato.',
    },

    // ── Outlet controls ─────────────────────────────────────────────────────
    'controls': {'en': 'Outlet Controls', 'it': 'Controllo Prese'},
    'usb': {'en': 'USB', 'it': 'USB'},
    'ac': {'en': 'AC', 'it': 'AC'},
    'dc': {'en': '12V DC', 'it': 'DC 12V'},
    'on': {'en': 'ON', 'it': 'ON'},
    'off': {'en': 'OFF', 'it': 'OFF'},
    'active': {'en': 'Active', 'it': 'Attivo'},
    'disabled': {'en': 'Off', 'it': 'Spento'},

    // ── Automation ──────────────────────────────────────────────────────────
    'automation': {'en': 'Smart Charging', 'it': 'Ricarica automatica'},
    'automation_description': {
      'en': 'Automatically manages AC outlets and a smart plug based on battery level.',
      'it': 'Gestisce automaticamente le prese AC e una presa smart in base al livello della batteria.',
    },
    'start_time': {'en': 'Window Start', 'it': 'Inizio finestra'},
    'end_time': {'en': 'Window End', 'it': 'Fine finestra'},
    'low_limit': {'en': 'Charge Below %', 'it': 'Carica sotto %'},
    'high_limit': {'en': 'Stop At %', 'it': 'Ferma a %'},
    'threshold_error': {
      'en': 'Must be 0–100',
      'it': 'Deve essere 0–100',
    },
    'low_high_error': {
      'en': 'Low must be less than high',
      'it': 'Il minimo deve essere minore del massimo',
    },

    // ── Plug control ────────────────────────────────────────────────────────
    'plug_control_actions': {'en': 'Plug Control Actions', 'it': 'Azioni di controllo presa'},
    'on_webhook_url': {'en': 'Charger ON Webhook URL', 'it': 'URL Webhook ACCENSIONE'},
    'off_webhook_url': {'en': 'Charger OFF Webhook URL', 'it': 'URL Webhook SPEGNIMENTO'},
    'on_webhook_url_fallback': {
      'en': 'Fallback ON Webhook (Optional)',
      'it': 'Webhook ACCENSIONE di riserva (opzionale)',
    },
    'off_webhook_url_fallback': {
      'en': 'Fallback OFF Webhook (Optional)',
      'it': 'Webhook SPEGNIMENTO di riserva (opzionale)',
    },
    'webhook_url_missing': {
      'en': 'Set a webhook URL or configure local Tapo first',
      'it': 'Imposta prima un URL webhook o configura il Tapo locale',
    },

    // ── Local Tapo ──────────────────────────────────────────────────────────
    'local_tapo_title': {'en': 'Local Tapo Control', 'it': 'Controllo Tapo locale'},
    'local_tapo_description': {
      'en': 'Connects directly to the plug on your local network. Falls back to webhooks if unavailable.',
      'it': 'Si connette direttamente alla presa sulla rete locale. Usa i webhook come riserva se non disponibile.',
    },
    'tapo_ip_label': {
      'en': 'Plug IP address (e.g. 192.168.1.75)',
      'it': 'Indirizzo IP presa (es. 192.168.1.75)',
    },
    'tapo_email_label': {'en': 'TP-Link account e-mail', 'it': 'E-mail account TP-Link'},
    'tapo_password_label': {'en': 'TP-Link account password', 'it': 'Password account TP-Link'},
    'test_local_handshake': {'en': 'Test Connection', 'it': 'Testa connessione'},
    'tapo_fields_incomplete': {
      'en': 'Fill in IP, e-mail, and password first.',
      'it': 'Inserisci prima IP, e-mail e password.',
    },

    // ── Action feedback ─────────────────────────────────────────────────────
    'tapo_credentials_incomplete': {
      'en': 'Local Tapo credentials incomplete.',
      'it': 'Credenziali Tapo locale incomplete.',
    },
    'tapo_attempting_connection': {
      'en': 'Connecting to plug…',
      'it': 'Connessione alla presa…',
    },
    'tapo_attempting_local_on': {
      'en': 'Turning ON via local Tapo…',
      'it': 'Accensione via Tapo locale…',
    },
    'tapo_attempting_local_off': {
      'en': 'Turning OFF via local Tapo…',
      'it': 'Spegnimento via Tapo locale…',
    },
    'tapo_local_on_successful': {
      'en': 'Plug turned ON via local Tapo.',
      'it': 'Presa accesa via Tapo locale.',
    },
    'tapo_local_off_successful': {
      'en': 'Plug turned OFF via local Tapo.',
      'it': 'Presa spenta via Tapo locale.',
    },
    'tapo_local_on_failed': {
      'en': 'Local Tapo ON failed — trying webhook fallback…',
      'it': 'Tapo locale ON fallito — tentativo webhook di riserva…',
    },
    'tapo_local_off_failed': {
      'en': 'Local Tapo OFF failed — trying webhook fallback…',
      'it': 'Tapo locale OFF fallito — tentativo webhook di riserva…',
    },
    'executing_webhook': {'en': 'Firing webhook…', 'it': 'Esecuzione webhook…'},
    'webhook_failed': {'en': 'Webhook failed.', 'it': 'Webhook fallito.'},
    'webhook_successful_prefix': {
      'en': 'Webhook OK',
      'it': 'Webhook riuscito',
    },
    'webhook_failed_with_code_prefix': {
      'en': 'Webhook failed',
      'it': 'Webhook fallito',
    },

    // ── History ─────────────────────────────────────────────────────────────
    'history_description': {
      'en': 'A log of every automation action and the battery level that triggered it.',
      'it': 'Un registro di ogni azione automatica e del livello di batteria che l\'ha attivata.',
    },
    'no_history': {
      'en': 'No automation actions yet. They\'ll show up here once the engine fires.',
      'it': 'Nessuna azione automatica ancora. Apparirà qui non appena il motore si attiva.',
    },
    'clear_history': {'en': 'Clear History', 'it': 'Svuota cronologia'},
    'clear_history_confirm': {
      'en': 'This permanently deletes all recorded automation history. This cannot be undone.',
      'it': 'Questo elimina permanentemente tutta la cronologia registrata. Non può essere annullato.',
    },
    'history_action_on': {'en': 'Charger turned ON', 'it': 'Caricatore acceso'},
    'history_action_off': {'en': 'Charger turned OFF', 'it': 'Caricatore spento'},
    'history_success': {'en': 'Success', 'it': 'Riuscito'},
    'history_failed': {'en': 'Failed', 'it': 'Fallito'},
    'history_method_local_tapo': {'en': 'Local Tapo', 'it': 'Tapo locale'},
    'history_method_webhook': {'en': 'Webhook', 'it': 'Webhook'},
    'history_method_none': {'en': 'Not configured', 'it': 'Non configurato'},
  };
}