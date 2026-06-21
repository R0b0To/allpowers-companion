import 'package:flutter/foundation.dart';

import '../models/automation_history_entry.dart';
import 'storage_service.dart';

/// In-memory cache of automation history, backed by [StorageService].
///
/// A [ChangeNotifier] (same pattern as [BleService]) so the History tab
/// updates immediately when [AutomationEngine] logs a new entry, without
/// waiting on a SharedPreferences round-trip.
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
    _entries = [entry, ..._entries];
    notifyListeners();
    await _storage.saveAutomationHistory(_entries);
  }

  Future<void> clear() async {
    _entries = const [];
    notifyListeners();
    await _storage.saveAutomationHistory(_entries);
  }
}