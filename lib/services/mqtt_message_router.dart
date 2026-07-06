import 'dart:convert';

import '../models/automation_flow.dart';
import '../models/automation_history_entry.dart';
import '../models/mqtt_rpc.dart';
import '../models/mqtt_settings.dart';
import '../models/power_station_status.dart';
import '../models/tapo_device.dart';

/// Result of routing a single incoming MQTT message.
sealed class MqttInboundMessage {
  const MqttInboundMessage();
}

/// A full replacement flow list, retained on [MqttSettings.flowsTopic].
final class FlowsSyncMessage extends MqttInboundMessage {
  const FlowsSyncMessage(this.flows);
  final List<AutomationFlow> flows;
}

/// A full replacement Tapo device list, retained on
/// [MqttSettings.tapoDevicesTopic].
final class TapoDevicesMessage extends MqttInboundMessage {
  const TapoDevicesMessage(this.devices);
  final List<TapoDevice> devices;
}

/// An RPC call arriving on [MqttSettings.rpcRequestTopic] (gateway-side).
final class RpcRequestMessage extends MqttInboundMessage {
  const RpcRequestMessage(this.request);
  final RpcRequest request;
}

/// An RPC result arriving on [MqttSettings.rpcResponseTopic] (client-side).
final class RpcResponseMessage extends MqttInboundMessage {
  const RpcResponseMessage(this.response);
  final RpcResponse response;
}

/// A single new history entry on [MqttSettings.historyTopic] (not retained).
final class HistoryEntryMessage extends MqttInboundMessage {
  const HistoryEntryMessage(this.entry);
  final AutomationHistoryEntry entry;
}

/// A full history snapshot on [MqttSettings.historySnapshotTopic] (retained).
final class HistorySnapshotMessage extends MqttInboundMessage {
  const HistorySnapshotMessage(this.entries);
  final List<AutomationHistoryEntry> entries;
}

/// Station telemetry on [MqttSettings.statusTopic] — only routed while in
/// [AppMode.client] (a gateway publishes this topic, it never subscribes to
/// its own status).
final class StatusMessage extends MqttInboundMessage {
  const StatusMessage({required this.status, required this.bleConnected});
  final PowerStationStatus status;
  final bool bleConnected;
}

/// An outlet command on `<prefix>/cmd/<outlet>` — only routed while in
/// [AppMode.gateway] (a client publishes commands, it never subscribes to
/// the command topic itself).
final class CommandMessage extends MqttInboundMessage {
  const CommandMessage({required this.outlet, required this.value});
  final String outlet;
  final bool value;
}

/// The topic didn't match anything this app cares about. In practice this
/// should be rare — subscriptions are already scoped per [AppMode] — but
/// [MqttMessageRouter.route] checks defensively rather than assuming the
/// broker never delivers anything unsubscribed-to.
final class UnrecognizedMessage extends MqttInboundMessage {
  const UnrecognizedMessage();
}

/// The topic matched, but the payload didn't parse into the expected shape
/// (invalid JSON, wrong types, missing required fields). Carries the
/// original error for logging; callers should never let this crash the app
/// — a malformed message from a flaky connection or a version mismatch
/// between gateway and client should be dropped, not fatal.
final class MalformedMessage extends MqttInboundMessage {
  const MalformedMessage(this.error);
  final Object error;
}

/// Pure, stateless router for incoming MQTT messages.
///
/// Extracted from `MqttService._onMessages` (and the `_handleXxx` methods it
/// used to call directly) so topic matching and JSON decoding can be unit
/// tested with plain strings — no broker, no `MqttReceivedMessage`, no
/// platform channel. `MqttService` still owns everything stateful that
/// happens *after* a message is decoded: updating `remoteStatus`, resolving
/// pending RPC completers, invoking the public callbacks UI code registers,
/// and deciding whether anything actually changed enough to call
/// `notifyListeners`.
abstract final class MqttMessageRouter {
  static MqttInboundMessage route({
    required String topic,
    required String raw,
    required MqttSettings settings,
  }) {
    try {
      if (topic == settings.flowsTopic) return _decodeFlows(raw);
      if (topic == settings.tapoDevicesTopic) return _decodeTapoDevices(raw);
      if (topic == settings.rpcRequestTopic) return _decodeRpcRequest(raw);
      if (topic == settings.rpcResponseTopic) return _decodeRpcResponse(raw);
      if (topic == settings.historyTopic) return _decodeHistoryEntry(raw);
      if (topic == settings.historySnapshotTopic) {
        return _decodeHistorySnapshot(raw);
      }
      if (settings.mode == AppMode.client && topic == settings.statusTopic) {
        return _decodeStatus(raw);
      }
      if (settings.mode == AppMode.gateway &&
          topic.startsWith(settings.commandTopic)) {
        return _decodeCommand(topic, raw);
      }
      return const UnrecognizedMessage();
    } catch (e) {
      return MalformedMessage(e);
    }
  }

  static MqttInboundMessage _decodeFlows(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    final flows = list
        .map((j) => AutomationFlow.tryFromJson(j as Map<String, dynamic>))
        .whereType<AutomationFlow>()
        .toList();
    return FlowsSyncMessage(flows);
  }

  static MqttInboundMessage _decodeTapoDevices(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    final devices = list
        .map((j) => _tapoDeviceFromJson(j as Map<String, dynamic>))
        .whereType<TapoDevice>()
        .toList();
    return TapoDevicesMessage(devices);
  }

  static TapoDevice? _tapoDeviceFromJson(Map<String, dynamic> j) {
    try {
      return TapoDevice(
        id: j['id'] as String,
        name: j['name'] as String,
        ip: j['ip'] as String,
        email: j['email'] as String,
        password: j['password'] as String,
        isOnline: j['isOnline'] as bool? ?? false,
        isOn: j['isOn'] as bool? ?? false,
        model: j['model'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  static MqttInboundMessage _decodeRpcRequest(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final req = RpcRequest(
      id: j['id'] as String,
      method: j['method'] as String,
      params: (j['params'] as Map<String, dynamic>?) ?? {},
    );
    return RpcRequestMessage(req);
  }

  static MqttInboundMessage _decodeRpcResponse(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final resp = RpcResponse.tryFromJson(j);
    if (resp == null) {
      throw const FormatException('Malformed RPC response payload');
    }
    return RpcResponseMessage(resp);
  }

  static MqttInboundMessage _decodeHistoryEntry(String raw) {
    final entry = AutomationHistoryEntry.tryFromJson(
        jsonDecode(raw) as Map<String, dynamic>);
    if (entry == null) {
      throw const FormatException('Malformed history entry payload');
    }
    return HistoryEntryMessage(entry);
  }

  static MqttInboundMessage _decodeHistorySnapshot(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    final entries = list
        .map((j) =>
            AutomationHistoryEntry.tryFromJson(j as Map<String, dynamic>))
        .whereType<AutomationHistoryEntry>()
        .toList();
    return HistorySnapshotMessage(entries);
  }

  static MqttInboundMessage _decodeStatus(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final status = PowerStationStatus.validated(
      batteryLevel: (j['batteryLevel'] as num? ?? 0).toInt(),
      inputWatts: (j['inputWatts'] as num? ?? 0).toInt(),
      outputWatts: (j['outputWatts'] as num? ?? 0).toInt(),
      minutesRemaining: (j['minutesRemaining'] as num? ?? 0).toInt(),
      isUsbOn: j['isUsbOn'] as bool? ?? false,
      isAcOn: j['isAcOn'] as bool? ?? false,
      isDcOn: j['isDcOn'] as bool? ?? false,
    );
    final bleConnected = j['bleConnected'] as bool? ?? false;
    return StatusMessage(status: status, bleConnected: bleConnected);
  }

  static MqttInboundMessage _decodeCommand(String topic, String raw) {
    final outlet = topic.split('/').last;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final value = j['value'] as bool? ?? false;
    return CommandMessage(outlet: outlet, value: value);
  }
}