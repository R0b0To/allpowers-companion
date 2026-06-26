/// What the automation engine was trying to do.
enum HistoryAction { turnOn, turnOff, tapoOn, tapoOff, webhookFired, outletToggled }

/// Which path actually carried out the action (or none, if nothing was configured).
enum ActivationMethod { localTapo, webhook, bleOutlet, none }

/// Immutable record of a single automation action — used to populate the History tab.
///
/// [batteryLevel] is the level that *triggered* the action, captured at the
/// start of the sequence rather than after any delays.
/// [flowName] identifies which automation triggered this entry.
final class AutomationHistoryEntry {
  const AutomationHistoryEntry({
    required this.timestamp,
    required this.action,
    required this.batteryLevel,
    required this.success,
    required this.method,
    this.flowName = '',
    this.deviceName = '',
  });

  final DateTime timestamp;
  final HistoryAction action;
  final int batteryLevel;
  final bool success;
  final ActivationMethod method;

  /// Display name of the flow that created this entry.
  final String flowName;

  /// For Tapo actions, the name of the device targeted.
  final String deviceName;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'action': action.name,
        'batteryLevel': batteryLevel,
        'success': success,
        'method': method.name,
        'flowName': flowName,
        'deviceName': deviceName,
      };

  /// Parses a single stored entry, returning null on any malformed data.
  static AutomationHistoryEntry? tryFromJson(Map<String, dynamic> json) {
    try {
      // Support legacy entries that used the old 2-value action enum.
      HistoryAction parseAction(String name) {
        switch (name) {
          case 'turnOn':
            return HistoryAction.turnOn;
          case 'turnOff':
            return HistoryAction.turnOff;
          case 'tapoOn':
            return HistoryAction.tapoOn;
          case 'tapoOff':
            return HistoryAction.tapoOff;
          case 'webhookFired':
            return HistoryAction.webhookFired;
          case 'outletToggled':
            return HistoryAction.outletToggled;
          default:
            return HistoryAction.turnOn;
        }
      }

      ActivationMethod parseMethod(String name) {
        switch (name) {
          case 'localTapo':
            return ActivationMethod.localTapo;
          case 'webhook':
            return ActivationMethod.webhook;
          case 'bleOutlet':
            return ActivationMethod.bleOutlet;
          default:
            return ActivationMethod.none;
        }
      }

      return AutomationHistoryEntry(
        timestamp: DateTime.parse(json['timestamp'] as String),
        action: parseAction(json['action'] as String),
        batteryLevel: (json['batteryLevel'] as num).toInt().clamp(0, 100),
        success: json['success'] as bool,
        method: parseMethod(json['method'] as String),
        flowName: json['flowName'] as String? ?? '',
        deviceName: json['deviceName'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}