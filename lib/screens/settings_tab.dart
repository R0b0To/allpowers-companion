import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../models/automation_settings.dart';
import '../models/mqtt_settings.dart';
import '../services/mqtt_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mqtt_settings_card.dart';


/// The 5th bottom navigation tab for global system, MQTT and Tapo settings.
class SettingsTab extends StatefulWidget {
  const SettingsTab({
    super.key,
    required this.settings,
    required this.mqttSettings,
    required this.mqtt,
    required this.strings,
    required this.onSettingsChanged,
    required this.onMqttSettingsChanged,
  });

  final AutomationSettings settings;
  final MqttSettings mqttSettings;
  final MqttService mqtt;
  final AppStrings strings;
  final ValueChanged<AutomationSettings> onSettingsChanged;
  final ValueChanged<MqttSettings> onMqttSettingsChanged;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;

    return SafeArea(
      // bottom is false because system navigation offsets are managed 
      // by the BottomNavigationBar inside MainShell
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.sm),
                  
                  // ── Local Tapo card ─────────────────────────────────────────

                  const SizedBox(height: AppSpacing.lg),

                  // ── Remote Access / MQTT card ─────────────────────────────────
                  MqttSettingsCard(
                    settings: widget.mqttSettings,
                    mqtt: widget.mqtt,
                    strings: s,
                    onSettingsChanged: widget.onMqttSettingsChanged,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}