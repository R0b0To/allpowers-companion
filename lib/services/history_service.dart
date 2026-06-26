import 'package:flutter/foundation.dart';

import '../models/automation_history_entry.dart';
import 'storage_service.dart';

/// In-memory cache of automation history, backed by [StorageService].
///
/// A [ChangeNotifier] so the History tab updates immediately when
/// [FlowEngine] logs a new entry, without waiting on a SharedPreferences
/// round-trip.
///
/// ## MQTT history sync
/// On the gateway, [addEntry] is the only writer. [MainShell] listens for
/// new entries and publishes them to MQTT so client phones receive them.
/// On the client, [replaceAll] is called when a history snapshot arrives,
/// and [addEntry] is called for individual live entries.
final class HistoryService extends ChangeNotifier {
  HistoryService(this._storage);

  final StorageService _storage;

  List<AutomationHistoryEntry> _entries = const [];
  bool _isLoaded = false;

  /// Newest first.
  List<AutomationHistoryEntry> get entries => _entries;
  bool get isLoaded => _isLoaded;

  /// Must be called once during app bootstrap to restore persisted history.
  Future<void> init() async {
    _entries = await _storage.loadAutomationHistory();
    _isLoaded = true;
    notifyListeners();
  }

  /// Records a new entry at the top of the list, notifies listeners
  /// immediately, then persists in the background.
  Future<void> addEntry(AutomationHistoryEntry entry) async {
    // Deduplicate: if an identical timestamp+action already exists (e.g. from
    // an MQTT echo), skip it.
    if (_entries.isNotEmpty &&
        _entries.first.timestamp == entry.timestamp &&
        _entries.first.action == entry.action) {
      return;
    }
    _entries = [entry, ..._entries];
    notifyListeners();
    await _storage.saveAutomationHistory(_entries);
  }

  /// Replaces the entire list — used by clients receiving a full gateway
  /// snapshot over MQTT. Entries are expected newest-first.
  Future<void> replaceAll(List<AutomationHistoryEntry> entries) async {
    // Sort newest-first in case the snapshot arrived out of order.
    final sorted = [...entries]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    _entries = sorted;
    _isLoaded = true;
    notifyListeners();
    await _storage.saveAutomationHistory(_entries);
  }

  Future<void> clear() async {
    _entries = const [];
    notifyListeners();
    await _storage.saveAutomationHistory(_entries);
  }
}