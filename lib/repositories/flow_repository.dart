import 'dart:convert';

import '../models/automation_flow.dart';
import '../utils/logger.dart';
import 'shared_preferences_source.dart';

/// Persists automation flows and their runtime edge-trigger state.
///
/// ## Two concerns in one repository — intentional
/// The trigger-state keys (`flow_triggered_<id>`) are tightly coupled to the
/// flow list: if a flow is deleted, its trigger state must be cleared atomically
/// (see [clearFlowTriggered]).  Splitting these into separate repositories
/// would require cross-repository coordination on delete, introducing more
/// coupling than it removes.
///
/// ## Testing
/// ```dart
/// SharedPreferences.setMockInitialValues({});
/// final repo = SharedPrefsFlowRepository(SharedPreferencesSource());
/// await repo.saveFlows([myFlow]);
/// expect(await repo.loadFlows(), hasLength(1));
///
/// await repo.setFlowTriggered(myFlow.id, true);
/// expect(await repo.getFlowTriggered(myFlow.id), isTrue);
/// ```
abstract class FlowRepository {
  Future<List<AutomationFlow>> loadFlows();
  Future<void> saveFlows(List<AutomationFlow> flows);

  Future<bool>  getFlowTriggered(String flowId);
  Future<void>  setFlowTriggered(String flowId, bool value);
  Future<void>  clearFlowTriggered(String flowId);
}

final class SharedPrefsFlowRepository implements FlowRepository {
  SharedPrefsFlowRepository(this._source);

  final SharedPreferencesSource _source;

  static const _keyFlows = 'automation_flows';

  static String _triggerKey(String id) => 'flow_triggered_$id';

  // ── Flows ─────────────────────────────────────────────────────────────────

  @override
  Future<List<AutomationFlow>> loadFlows() async {
    try {
      final prefs = await _source.prefs;
      final raw   = prefs.getStringList(_keyFlows) ?? [];
      final flows = <AutomationFlow>[];
      for (final s in raw) {
        try {
          final f = AutomationFlow.tryFromJson(jsonDecode(s) as Map<String, dynamic>);
          if (f != null) flows.add(f);
        } catch (_) {
          // Skip corrupt entries; one bad record does not invalidate the rest.
        }
      }
      return flows;
    } catch (e) {
      Log.e('FlowRepository', 'loadFlows failed', e);
      return [];
    }
  }

  @override
  Future<void> saveFlows(List<AutomationFlow> flows) async {
    try {
      final prefs = await _source.prefs;
      await prefs.setStringList(
        _keyFlows,
        flows.map((f) => jsonEncode(f.toJson())).toList(),
      );
    } catch (e) {
      Log.e('FlowRepository', 'saveFlows failed', e);
    }
  }

  // ── Edge-trigger state ────────────────────────────────────────────────────

  @override
  Future<bool> getFlowTriggered(String flowId) async {
    try {
      return (await _source.prefs).getBool(_triggerKey(flowId)) ?? false;
    } catch (e) {
      Log.e('FlowRepository', 'getFlowTriggered($flowId) failed', e);
      return false;
    }
  }

  @override
  Future<void> setFlowTriggered(String flowId, bool value) async {
    try {
      await (await _source.prefs).setBool(_triggerKey(flowId), value);
    } catch (e) {
      Log.e('FlowRepository', 'setFlowTriggered($flowId) failed', e);
    }
  }

  @override
  Future<void> clearFlowTriggered(String flowId) async {
    try {
      await (await _source.prefs).remove(_triggerKey(flowId));
    } catch (e) {
      Log.e('FlowRepository', 'clearFlowTriggered($flowId) failed', e);
    }
  }
}
