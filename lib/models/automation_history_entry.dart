/// What the automation engine was trying to do.
enum HistoryAction { turnOn, turnOff }

/// Which path actually carried out the action (or none, if nothing was
/// configured).
enum ActivationMethod { localTapo, webhook, none }

/// Immutable record of a single automation action — used to populate the
/// History tab.
///
/// [batteryLevel] is the level that *triggered* the action, captured at the
/// start of the sequence rather than after any delays, so it reflects the
/// reading the user would expect to see (e.g. "10% → charging started"),
/// not whatever the level happened to drift to during the 5s/10s sequence
/// delays in [AutomationEngine].
final class AutomationHistoryEntry {
  const AutomationHistoryEntry({
    required this.timestamp,
    required this.action,
    required this.batteryLevel,
    required this.success,
    required this.method,
  });

  final DateTime timestamp;
  final HistoryAction action;
  final int batteryLevel;
  final bool success;
  final ActivationMethod method;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'action': action.name,
        'batteryLevel': batteryLevel,
        'success': success,
        'method': method.name,
      };

  /// Parses a single stored entry, returning null on any malformed data so
  /// one corrupt entry can't take down the whole history list.
  static AutomationHistoryEntry? tryFromJson(Map<String, dynamic> json) {
    try {
      return AutomationHistoryEntry(
        timestamp: DateTime.parse(json['timestamp'] as String),
        action: HistoryAction.values.byName(json['action'] as String),
        batteryLevel: (json['batteryLevel'] as num).toInt().clamp(0, 100),
        success: json['success'] as bool,
        method: ActivationMethod.values.byName(json['method'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}