/// Minimal hand-rolled localisation for English / Italian.
final class AppStrings {
  AppStrings(this.isItalian);

  final bool isItalian;

  /// Returns the localised string for [key]. If [params] is provided, any
  /// `{name}`-style placeholder in the translation is replaced with the
  /// corresponding value — e.g. `t('devices_remove_title', {'name': 'Garage'})`
  /// turns `'Remove "{name}"?'` into `'Remove "Garage"?'`.
  String t(String key, [Map<String, String>? params]) {
    var value = _translations[key]?[isItalian ? 'it' : 'en'] ?? key;
    if (params != null) {
      for (final entry in params.entries) {
        value = value.replaceAll('{${entry.key}}', entry.value);
      }
    }
    return value;
  }

  static const Map<String, Map<String, String>> _translations = {
    // ── Navigation ──────────────────────────────────────────────────────────
    'tab_control': {'en': 'Control', 'it': 'Controllo'},
    'tab_automations': {'en': 'Automation', 'it': 'Automazione'},
    'tab_history': {'en': 'History', 'it': 'Cronologia'},
    'tab_devices': {'en': 'Devices', 'it': 'Dispositivi'},
    'tab_energy': {'en': 'Energy', 'it': 'Energia'},

    // ── Devices tab ──────────────────────────────────────────────────────────
    'devices_description': {
      'en': 'Manage your TP-Link Tapo smart plugs.',
      'it': 'Gestisci le tue prese smart TP-Link Tapo.',
    },
    'devices_add': {'en': 'Add device', 'it': 'Aggiungi dispositivo'},
    'devices_refresh': {'en': 'Refresh', 'it': 'Aggiorna'},
    'plug_power': {'en': 'Power', 'it': 'Alimentazione'},

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
      'en': 'Automatically manages AC outlets and smart plugs based on battery level.',
      'it': 'Gestisce automaticamente le prese AC e smart in base al livello della batteria.',
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

    // ── Local Tapo (kept for settings legacy) ───────────────────────────────
    'local_tapo_title': {'en': 'Local Tapo Control', 'it': 'Controllo Tapo locale'},
    'local_tapo_description': {
      'en': 'Connects directly to the plug on your local network.',
      'it': 'Si connette direttamente alla presa sulla rete locale.',
    },
    'tapo_ip_label': {
      'en': 'Plug IP address (e.g. 192.168.1.75)',
      'it': 'Indirizzo IP presa (es. 192.168.1.75)',
    },
    'tapo_email_label': {
      'en': 'TP-Link account e-mail',
      'it': 'E-mail account TP-Link',
    },
    'tapo_password_label': {
      'en': 'TP-Link account password',
      'it': 'Password account TP-Link',
    },
    'test_local_handshake': {
      'en': 'Test Connection',
      'it': 'Testa connessione',
    },
    'tapo_fields_incomplete': {
      'en': 'Fill in IP, e-mail, and password first.',
      'it': 'Inserisci prima IP, e-mail e password.',
    },
    'tapo_credentials_incomplete': {
      'en': 'Local Tapo credentials incomplete.',
      'it': 'Credenziali Tapo locale incomplete.',
    },

    // ── History ─────────────────────────────────────────────────────────────
    'history_description': {
      'en': 'A log of every automation action and the battery level that triggered it.',
      'it': "Un registro di ogni azione automatica e del livello di batteria che l'ha attivata.",
    },
    'no_history': {
      'en': "No automation actions yet. They'll show up here once the engine fires.",
      'it': "Nessuna azione automatica ancora. Apparirà qui non appena il motore si attiva.",
    },
    'clear_history': {'en': 'Clear History', 'it': 'Svuota cronologia'},
    'clear_history_confirm': {
      'en': 'This permanently deletes all recorded automation history. This cannot be undone.',
      'it': 'Questo elimina permanentemente tutta la cronologia registrata. Non può essere annullato.',
    },
    'history_action_on': {'en': 'Charger turned ON', 'it': 'Caricatore acceso'},
    'history_action_off': {
      'en': 'Charger turned OFF',
      'it': 'Caricatore spento',
    },
    'history_success': {'en': 'Success', 'it': 'Riuscito'},
    'history_failed': {'en': 'Failed', 'it': 'Fallito'},
    'history_method_local_tapo': {'en': 'Local Tapo', 'it': 'Tapo locale'},
    'history_method_webhook': {'en': 'Webhook', 'it': 'Webhook'},
    'history_method_none': {
      'en': 'Not configured',
      'it': 'Non configurato',
    },
    'history_synced_badge': {
      'en': 'From gateway',
      'it': 'Dal gateway',
    },

    // ── MQTT / Remote Access ─────────────────────────────────────────────────
    'mqtt_section_title': {'en': 'Remote Access', 'it': 'Accesso remoto'},
    'mqtt_mode_label': {'en': 'App Mode', 'it': 'Modalità app'},
    'mqtt_mode_standalone': {'en': 'Standalone', 'it': 'Autonomo'},
    'mqtt_mode_standalone_sub': {
      'en': 'Direct BLE only — no MQTT',
      'it': 'Solo BLE diretto — nessun MQTT',
    },
    'mqtt_mode_standalone_desc': {
      'en': 'Classic mode: this phone holds the BLE connection and controls the station directly.',
      'it': 'Modalità classica: questo telefono gestisce la connessione BLE e controlla la stazione direttamente.',
    },
    'mqtt_mode_gateway': {'en': 'Gateway', 'it': 'Gateway'},
    'mqtt_mode_gateway_sub': {
      'en': 'Share station data via MQTT broker',
      'it': 'Condividi i dati via broker MQTT',
    },
    'mqtt_mode_gateway_desc': {
      'en': 'This phone keeps the BLE connection and publishes telemetry to the broker. Other phones in Client mode can monitor and control the station from anywhere.',
      'it': 'Questo telefono mantiene la connessione BLE e pubblica la telemetria sul broker. Altri telefoni in modalità Client possono monitorare e controllare la stazione ovunque.',
    },
    'mqtt_mode_client': {'en': 'Client', 'it': 'Client'},
    'mqtt_mode_client_sub': {
      'en': 'Monitor & control via MQTT — no BLE needed',
      'it': 'Monitora e controlla via MQTT — BLE non necessario',
    },
    'mqtt_mode_client_desc': {
      'en': "No BLE required. This phone subscribes to the gateway's data stream and sends outlet commands back through the broker.",
      'it': "BLE non richiesto. Questo telefono riceve il flusso dati del gateway e invia comandi presa tramite il broker.",
    },
    'mqtt_broker_host': {'en': 'Broker host', 'it': 'Host broker'},
    'mqtt_port': {'en': 'Port', 'it': 'Porta'},
    'mqtt_username': {
      'en': 'Username (optional)',
      'it': 'Nome utente (opzionale)',
    },
    'mqtt_password': {
      'en': 'Password (optional)',
      'it': 'Password (opzionale)',
    },
    'mqtt_topic_prefix': {'en': 'Topic prefix', 'it': 'Prefisso topic'},
    'mqtt_use_tls': {'en': 'TLS / SSL', 'it': 'TLS / SSL'},
    'mqtt_client_id': {
      'en': 'Client ID (optional)',
      'it': 'Client ID (opzionale)',
    },
    'mqtt_client_id_hint': {
      'en': 'Auto-generated if blank',
      'it': 'Generato automaticamente se vuoto',
    },
    'mqtt_status_topic': {'en': 'Status', 'it': 'Stato'},
    'mqtt_cmd_topic': {'en': 'Commands', 'it': 'Comandi'},
    'mqtt_test_connection': {
      'en': 'Test Broker Connection',
      'it': 'Testa connessione broker',
    },
    'mqtt_connecting': {
      'en': 'Connecting to MQTT broker…',
      'it': 'Connessione al broker MQTT…',
    },
    'mqtt_connected': {'en': 'MQTT connected', 'it': 'MQTT connesso'},
    'mqtt_disconnected': {
      'en': 'MQTT disconnected',
      'it': 'MQTT disconnesso',
    },
    'mqtt_broker_offline': {
      'en': 'Cannot reach broker',
      'it': 'Broker non raggiungibile',
    },
    'mqtt_check_settings': {
      'en': 'Check your broker settings in the Settings tab.',
      'it': 'Controlla le impostazioni broker nella scheda Impostazioni.',
    },
    'mqtt_configure_hint': {
      'en': 'Go to Settings → Remote Access to configure.',
      'it': 'Vai in Impostazioni → Accesso remoto per configurare.',
    },
    'mqtt_gateway_ble_offline': {
      'en': 'Gateway has no BLE connection',
      'it': 'Il gateway non ha connessione BLE',
    },
    'mqtt_gateway_ble_offline_body': {
      'en': 'The gateway phone is connected to the broker but its Bluetooth link to the station is down. Make sure the gateway phone is near the station.',
      'it': 'Il telefono gateway è connesso al broker ma la connessione Bluetooth alla stazione è interrotta. Assicurati che il telefono gateway sia vicino alla stazione.',
    },
    'mqtt_remote_label': {'en': 'REMOTE', 'it': 'REMOTO'},
    'mqtt_command_latency_note': {
      'en': 'Commands relay via MQTT — allow ~1 s for the gateway to respond.',
      'it': 'I comandi transitano via MQTT — attendi ~1 s per la risposta del gateway.',
    },

    // ── Generic / shared ─────────────────────────────────────────────────────
    'connect': {'en': 'Connect', 'it': 'Connetti'},
    'remove': {'en': 'Remove', 'it': 'Rimuovi'},
    'delete': {'en': 'Delete', 'it': 'Elimina'},
    'save': {'en': 'Save', 'it': 'Salva'},
    'test_button': {'en': 'Test', 'it': 'Testa'},
    'network_label': {'en': 'Network', 'it': 'Rete'},
    'device_name_label': {'en': 'Device name', 'it': 'Nome dispositivo'},
    'device_name_hint': {
      'en': 'e.g. Garage Charger',
      'it': 'es. Caricatore garage',
    },
    'ip_address_label': {'en': 'IP address', 'it': 'Indirizzo IP'},

    // ── Control tab ──────────────────────────────────────────────────────────
    'control_find_station': {
      'en': 'Find your Allpowers station',
      'it': 'Trova la tua stazione Allpowers',
    },

    // ── Devices tab (additions) ──────────────────────────────────────────────
    'devices_client_description': {
      'en': 'Plug state synced from the gateway. Toggle plugs remotely via the gateway.',
      'it': 'Lo stato delle prese è sincronizzato dal gateway. Attiva le prese da remoto tramite il gateway.',
    },
    'devices_client_banner': {
      'en': 'Device list synced from gateway. Add or remove plugs on the gateway phone.',
      'it': "L'elenco dei dispositivi è sincronizzato dal gateway. Aggiungi o rimuovi prese dal telefono gateway.",
    },
    'devices_remove_title': {
      'en': 'Remove "{name}"?',
      'it': 'Rimuovere "{name}"?',
    },
    'devices_remove_body': {
      'en': 'This device will be removed from your list. Any automations referencing it will no longer work.',
      'it': 'Questo dispositivo verrà rimosso dal tuo elenco. Le automazioni che lo utilizzano smetteranno di funzionare.',
    },
    'devices_refresh_failed': {'en': 'Refresh failed', 'it': 'Aggiornamento fallito'},
    'devices_toggle_failed': {
      'en': 'Failed to toggle {name}',
      'it': 'Impossibile attivare/disattivare {name}',
    },
    'devices_add_title': {'en': 'Add Tapo Device', 'it': 'Aggiungi dispositivo Tapo'},
    'devices_edit_title': {'en': 'Edit {name}', 'it': 'Modifica {name}'},
    'devices_empty_client_title': {
      'en': 'No plugs synced yet',
      'it': 'Nessuna presa sincronizzata',
    },
    'devices_empty_title': {
      'en': 'No smart plugs yet',
      'it': 'Nessuna presa smart ancora',
    },
    'devices_empty_client_body': {
      'en': 'Plug state is synced from the gateway. Make sure the gateway phone has at least one Tapo device configured and is connected to the broker.',
      'it': 'Lo stato delle prese è sincronizzato dal gateway. Assicurati che il telefono gateway abbia almeno un dispositivo Tapo configurato e sia connesso al broker.',
    },
    'devices_empty_body': {
      'en': 'Add a TP-Link Tapo plug to control it from here and use it in automations.',
      'it': 'Aggiungi una presa TP-Link Tapo per controllarla da qui e usarla nelle automazioni.',
    },
    'devices_add_button': {'en': 'Add Tapo device', 'it': 'Aggiungi presa Tapo'},

    // ── Flow editor ──────────────────────────────────────────────────────────
    'flow_new_automation': {'en': 'New Automation', 'it': 'Nuova automazione'},
    'flow_name_hint': {'en': 'Automation name', 'it': 'Nome automazione'},
    'flow_trigger_label': {'en': 'Trigger', 'it': 'Attivazione'},
    'flow_action_steps_label': {'en': 'Action steps', 'it': 'Passaggi azione'},
    'flow_step_singular': {'en': 'step', 'it': 'passaggio'},
    'flow_step_plural': {'en': 'steps', 'it': 'passaggi'},
    'flow_falls_below': {'en': 'Falls Below', 'it': 'Scende sotto'},
    'flow_rises_above': {'en': 'Rises Above', 'it': 'Sale sopra'},
    'flow_plug_state': {'en': 'Plug State', 'it': 'Stato presa'},
    'flow_battery_threshold': {'en': 'Battery threshold', 'it': 'Soglia batteria'},
    'flow_require_plug_state': {
      'en': 'Also require plug state',
      'it': 'Richiedi anche lo stato della presa',
    },
    'flow_plug_condition_hint': {
      'en': 'e.g. battery below {threshold}% AND plug is {state}',
      'it': 'es. batteria sotto {threshold}% E presa {state}',
    },
    'flow_no_tapo_devices': {
      'en': 'No Tapo devices found. Add one in the Devices tab.',
      'it': 'Nessun dispositivo Tapo trovato. Aggiungine uno nella scheda Dispositivi.',
    },
    'flow_select_plug': {'en': 'Select plug', 'it': 'Seleziona presa'},
    'flow_plug_must_be': {'en': 'Plug must be', 'it': 'La presa deve essere'},
    'flow_plug_to_monitor': {'en': 'Plug to monitor', 'it': 'Presa da monitorare'},
    'flow_trigger_when_plug_is': {
      'en': 'Trigger when plug is',
      'it': 'Attiva quando la presa è',
    },
    'flow_fires_off_wanted_on': {
      'en': 'Fires when plug is OFF and you want it ON (inside window)',
      'it': 'Si attiva quando la presa è OFF e la vuoi ON (nella finestra oraria)',
    },
    'flow_fires_on_wanted_off': {
      'en': 'Fires when plug is ON and you want it OFF (inside window)',
      'it': 'Si attiva quando la presa è ON e la vuoi OFF (nella finestra oraria)',
    },
    'flow_choose_expected_state': {
      'en': 'Choose the expected plug state',
      'it': 'Scegli lo stato atteso della presa',
    },
    'flow_window_required': {
      'en': 'Active window (required)',
      'it': 'Finestra attiva (obbligatoria)',
    },
    'flow_window_optional': {
      'en': 'Time window (optional)',
      'it': 'Finestra oraria (opzionale)',
    },
    'flow_time_from': {'en': 'From', 'it': 'Da'},
    'flow_time_to': {'en': 'To', 'it': 'A'},
    'flow_action_wait': {'en': 'Wait', 'it': 'Attendi'},
    'flow_action_set_outlet': {'en': 'Set outlet', 'it': 'Imposta presa'},
    'flow_action_webhook': {'en': 'Webhook', 'it': 'Webhook'},
    'flow_action_tapo_plug': {'en': 'Tapo plug', 'it': 'Presa Tapo'},
    'flow_pause_for': {'en': 'Pause for', 'it': 'Pausa di'},
    'flow_seconds': {'en': 'seconds', 'it': 'secondi'},
    'add_step': {'en': 'Add step', 'it': 'Aggiungi passaggio'},
    'flow_no_steps_title': {'en': 'No steps yet', 'it': 'Nessun passaggio ancora'},
    'flow_no_steps_body': {
      'en': 'Steps run in order when the trigger fires.',
      'it': 'I passaggi vengono eseguiti in ordine quando si attiva il trigger.',
    },
    'flow_add_first_step': {
      'en': 'Add first step',
      'it': 'Aggiungi il primo passaggio',
    },
    'flow_action_wait_desc': {
      'en': 'Pause for N seconds before the next step',
      'it': 'Metti in pausa per N secondi prima del passaggio successivo',
    },
    'flow_action_set_outlet_title': {
      'en': 'Set BLE outlet',
      'it': 'Imposta presa BLE',
    },
    'flow_action_set_outlet_desc': {
      'en': 'Toggle USB, AC, or DC output directly via Bluetooth',
      'it': 'Attiva/disattiva USB, AC o DC direttamente via Bluetooth',
    },
    'flow_action_webhook_title': {'en': 'Fire webhook', 'it': 'Attiva webhook'},
    'flow_action_webhook_desc': {
      'en': 'Send an HTTP GET request to any URL',
      'it': 'Invia una richiesta HTTP GET a qualsiasi URL',
    },
    'flow_action_control_tapo_title': {
      'en': 'Control Tapo',
      'it': 'Controlla Tapo',
    },
    'flow_action_control_tapo_desc': {
      'en': 'Turn a TP-Link Tapo plug on or off',
      'it': 'Accendi o spegni una presa TP-Link Tapo',
    },
    'flow_device_label': {'en': 'Device', 'it': 'Dispositivo'},
    'flow_new_automation_tooltip': {
      'en': 'New automation',
      'it': 'Nuova automazione',
    },
    'flow_no_tapo_configured': {
      'en': 'No Tapo devices configured. Add one in the Devices tab.',
      'it': 'Nessun dispositivo Tapo configurato. Aggiungine uno nella scheda Dispositivi.',
    },

    // ── Automations tab ──────────────────────────────────────────────────────
    'flow_delete_title': {'en': 'Delete "{name}"?', 'it': 'Eliminare "{name}"?'},
    'flow_delete_body': {
      'en': 'This automation will be permanently removed.',
      'it': 'Questa automazione verrà rimossa permanentemente.',
    },
    'automations_description': {
      'en': 'Custom sequences triggered by battery or plug events.',
      'it': 'Sequenze personalizzate attivate da eventi di batteria o presa.',
    },
    'automations_templates_added': {
      'en': '2 starter automations added — tap to customise',
      'it': '2 automazioni iniziali aggiunte — tocca per personalizzarle',
    },
    'automations_client_banner': {
      'en': 'Automations sync to the gateway and run there. Changes publish automatically when connected.',
      'it': 'Le automazioni si sincronizzano con il gateway e vengono eseguite lì. Le modifiche vengono pubblicate automaticamente quando connesso.',
    },
    'automations_empty_title': {
      'en': 'No automations yet',
      'it': 'Nessuna automazione ancora',
    },
    'automations_empty_body': {
      'en': 'Build custom step sequences or start from the charging template.',
      'it': 'Crea sequenze di passaggi personalizzate o parti dal modello di ricarica.',
    },
    'automations_use_templates': {
      'en': 'Use charging templates',
      'it': 'Usa modelli di ricarica',
    },
    'automations_build_from_scratch': {
      'en': 'Build from scratch',
      'it': 'Crea da zero',
    },
    'flow_falls_below_pct': {
      'en': 'Falls below {threshold}%',
      'it': 'Scende sotto {threshold}%',
    },
    'flow_rises_above_pct': {
      'en': 'Rises above {threshold}%',
      'it': 'Sale sopra {threshold}%',
    },
    'flow_found_off': {'en': 'found OFF', 'it': 'trovato OFF'},
    'flow_found_on': {'en': 'found ON', 'it': 'trovato ON'},
    'flow_plug_state_summary': {
      'en': 'Plug "{device}" {state}',
      'it': 'Presa "{device}" {state}',
    },
    'flow_plug_generic': {'en': 'Plug', 'it': 'Presa'},
    'flow_unknown_plug': {'en': 'Unknown plug', 'it': 'Presa sconosciuta'},

    // ── History tile (additions) ─────────────────────────────────────────────
    'history_tapo_on': {'en': 'Tapo turned ON', 'it': 'Tapo acceso'},
    'history_tapo_off': {'en': 'Tapo turned OFF', 'it': 'Tapo spento'},
    'history_webhook_fired': {'en': 'Webhook fired', 'it': 'Webhook attivato'},
    'history_outlet_toggled': {
      'en': 'Outlet {name} toggled',
      'it': 'Presa {name} attivata/disattivata',
    },
    'history_method_ble_outlet': {'en': 'BLE outlet', 'it': 'Presa BLE'},
  };
}