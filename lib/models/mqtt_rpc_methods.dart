// lib/models/mqtt_rpc_methods.dart
abstract final class RpcMethod {
  // Outlet control (replaces the current ad-hoc cmd/+ topics)
  static const String setOutlet     = 'outlet.set';      // {outlet, value}

  // Tapo device control
  static const String tapoSetOn     = 'tapo.setOn';      // {deviceId, on}
  static const String tapoRefresh   = 'tapo.refresh';    // {}

  // Flow management
  static const String flowsReplace  = 'flows.replace';   // {flows: [...]}
  static const String flowSetEnabled = 'flow.setEnabled'; // {flowId, enabled}
  static const String flowDelete    = 'flow.delete';      // {flowId}
  static const String flowRun       = 'flow.run';         // {flowId}  (manual trigger)

  // History
  static const String historyClear  = 'history.clear';   // {}
}