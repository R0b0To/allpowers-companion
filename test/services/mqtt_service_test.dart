import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:ap_companion/models/automation_flow.dart';
import 'package:ap_companion/models/automation_history_entry.dart';
import 'package:ap_companion/models/mqtt_settings.dart';
import 'package:ap_companion/models/tapo_device.dart';
import 'package:ap_companion/services/mqtt_service.dart';

/// These tests exercise [MqttService]'s dispatch and RPC-correlation logic
/// via [MqttService.debugHandleMessage]/[MqttService.debugAwaitRpcResponse]
/// — test-only seams that run the exact same code a real incoming message
/// would, without needing a live broker connection.
///
/// [MqttService.configure] is called with `brokerHost: ''` throughout so
/// [MqttSettings.isConfigured] is false and no real connection attempt is
/// ever triggered — only the mode needs to change for these tests, not an
/// actual broker.
void main() {
  late MqttService service;

  setUp(() {
    service = MqttService();
  });

  tearDown(() {
    service.dispose();
  });

  group('call() when not connected', () {
    test('returns a "Not connected" error without publishing', () async {
      final resp = await service.call('some.method', {'a': 1});

      expect(resp.ok, isFalse);
      expect(resp.error, 'Not connected');
    });
  });

  group('debugHandleMessage — dispatch to callbacks', () {
    test('flows topic invokes onFlowsReceived with decoded flows', () async {
      await service.configure(
        const MqttSettings(mode: AppMode.gateway, brokerHost: ''),
      );
      List<AutomationFlow>? received;
      service.onFlowsReceived = (flows) => received = flows;

      final flow = AutomationFlow(
        id: 'f1',
        name: 'Test',
        trigger: const FlowTrigger(
            type: FlowTriggerType.batteryFallsBelow, threshold: 10),
        actions: const [],
      );
      service.debugHandleMessage(
        service.settings.flowsTopic,
        jsonEncode([flow.toJson()]),
      );

      expect(received, isNotNull);
      expect(received, hasLength(1));
      expect(received!.single.id, 'f1');
    });

    test('flows topic with an empty list still invokes the callback', () async {
      await service.configure(
        const MqttSettings(mode: AppMode.gateway, brokerHost: ''),
      );
      var callCount = 0;
      service.onFlowsReceived = (_) => callCount++;

      service.debugHandleMessage(service.settings.flowsTopic, jsonEncode([]));

      expect(callCount, 1);
    });

    test('tapo/devices topic invokes onTapoDevicesReceived', () async {
      await service.configure(
        const MqttSettings(mode: AppMode.client, brokerHost: ''),
      );
      List<TapoDevice>? received;
      service.onTapoDevicesReceived = (devices) => received = devices;

      service.debugHandleMessage(
        service.settings.tapoDevicesTopic,
        jsonEncode([
          {
            'id': 'dev1',
            'name': 'Garage',
            'ip': '1.2.3.4',
            'email': 'a@b.com',
            'password': 'x',
            'isOnline': true,
            'isOn': true,
            'model': 'P110',
          }
        ]),
      );

      expect(received, hasLength(1));
      expect(received!.single.name, 'Garage');
      expect(received!.single.isOn, isTrue);
    });

    test('history snapshot topic with entries invokes onHistoryReceived', () async {
      await service.configure(
        const MqttSettings(mode: AppMode.client, brokerHost: ''),
      );
      List<AutomationHistoryEntry>? received;
      service.onHistoryReceived = (entries) => received = entries;

      final entry = AutomationHistoryEntry(
        timestamp: DateTime.utc(2026, 1, 1),
        action: HistoryAction.tapoOn,
        batteryLevel: 50,
        success: true,
        method: ActivationMethod.localTapo,
      );
      service.debugHandleMessage(
        service.settings.historySnapshotTopic,
        jsonEncode([entry.toJson()]),
      );

      expect(received, hasLength(1));
    });

    test('an empty history snapshot does NOT invoke onHistoryReceived', () async {
      await service.configure(
        const MqttSettings(mode: AppMode.client, brokerHost: ''),
      );
      var called = false;
      service.onHistoryReceived = (_) => called = true;

      service.debugHandleMessage(
          service.settings.historySnapshotTopic, jsonEncode([]));

      expect(called, isFalse);
    });

    test('a single history entry topic invokes onHistoryReceived with one entry',
        () async {
      await service.configure(
        const MqttSettings(mode: AppMode.client, brokerHost: ''),
      );
      List<AutomationHistoryEntry>? received;
      service.onHistoryReceived = (entries) => received = entries;

      final entry = AutomationHistoryEntry(
        timestamp: DateTime.utc(2026, 1, 1),
        action: HistoryAction.webhookFired,
        batteryLevel: 40,
        success: false,
        method: ActivationMethod.webhook,
      );
      service.debugHandleMessage(
        service.settings.historyTopic,
        jsonEncode(entry.toJson()),
      );

      expect(received, hasLength(1));
      expect(received!.single.success, isFalse);
    });
  });

  group('debugHandleMessage — status (client mode only)', () {
    test(
        'updates remoteStatus and lastRemoteUpdate on the status topic in '
        'client mode', () async {
      await service.configure(
        const MqttSettings(mode: AppMode.client, brokerHost: ''),
      );

      service.debugHandleMessage(
        service.settings.statusTopic,
        jsonEncode({
          'batteryLevel': 77,
          'inputWatts': 100,
          'outputWatts': 0,
          'minutesRemaining': 60,
          'isUsbOn': true,
          'isAcOn': false,
          'isDcOn': false,
          'bleConnected': true,
        }),
      );

      expect(service.remoteStatus.batteryLevel, 77);
      expect(service.remoteStatus.isUsbOn, isTrue);
      expect(service.bleConnectedRemote, isTrue);
      expect(service.lastRemoteUpdate, isNotNull);
    });

    test('does not notify listeners when the identical status repeats', () async {
      await service.configure(
        const MqttSettings(mode: AppMode.client, brokerHost: ''),
      );
      final payload = jsonEncode({
        'batteryLevel': 50,
        'inputWatts': 0,
        'outputWatts': 0,
        'minutesRemaining': 0,
        'isUsbOn': false,
        'isAcOn': false,
        'isDcOn': false,
        'bleConnected': true,
      });
      service.debugHandleMessage(service.settings.statusTopic, payload);
      final firstUpdate = service.lastRemoteUpdate;

      // Same payload again — _applyRemoteStatus only touches lastRemoteUpdate
      // on an actual change, so it should be unchanged here.
      service.debugHandleMessage(service.settings.statusTopic, payload);

      expect(service.lastRemoteUpdate, firstUpdate);
    });

    test('a status message is ignored (no update) while in gateway mode', () async {
      await service.configure(
        const MqttSettings(mode: AppMode.gateway, brokerHost: ''),
      );

      service.debugHandleMessage(
        service.settings.statusTopic,
        jsonEncode({'batteryLevel': 99}),
      );

      expect(service.remoteStatus.batteryLevel, 0); // untouched default
      expect(service.lastRemoteUpdate, isNull);
    });
  });

  group('debugHandleMessage — command (gateway mode only)', () {
    test('invokes onCommand with the outlet name and value in gateway mode',
        () async {
      await service.configure(
        const MqttSettings(mode: AppMode.gateway, brokerHost: ''),
      );
      String? outlet;
      bool? value;
      service.onCommand = (o, v) {
        outlet = o;
        value = v;
      };

      service.debugHandleMessage(
        '${service.settings.commandTopic}/ac',
        jsonEncode({'value': true}),
      );

      expect(outlet, 'ac');
      expect(value, isTrue);
    });

    test('a command message is ignored while in client mode', () async {
      await service.configure(
        const MqttSettings(mode: AppMode.client, brokerHost: ''),
      );
      var called = false;
      service.onCommand = (_, __) => called = true;

      service.debugHandleMessage(
        '${service.settings.commandTopic}/ac',
        jsonEncode({'value': true}),
      );

      expect(called, isFalse);
    });
  });

  group('debugHandleMessage — RPC request', () {
    test('invokes the registered onRpcRequest handler with method and params',
        () async {
      await service.configure(
        const MqttSettings(mode: AppMode.gateway, brokerHost: ''),
      );
      String? calledMethod;
      Map<String, dynamic>? calledParams;
      service.onRpcRequest = (method, params) async {
        calledMethod = method;
        calledParams = params;
        return {'ok': true};
      };

      service.debugHandleMessage(
        service.settings.rpcRequestTopic,
        jsonEncode({
          'id': 'req_1',
          'method': 'tapo.setOn',
          'params': {'deviceId': 'dev1', 'on': true},
        }),
      );
      // _handleRpcRequest runs unawaited inside _dispatch — flush the
      // microtask queue so the async handler has had a chance to run.
      await Future<void>.delayed(Duration.zero);

      expect(calledMethod, 'tapo.setOn');
      expect(calledParams, {'deviceId': 'dev1', 'on': true});
    });
  });

  group('debugAwaitRpcResponse — RPC correlation', () {
    test('a matching response resolves the pending completer', () async {
      final future = service.debugAwaitRpcResponse('rpc_1');

      service.debugHandleMessage(
        service.settings.rpcResponseTopic,
        jsonEncode({'id': 'rpc_1', 'ok': true, 'result': 42, 'error': null}),
      );

      final resp = await future;
      expect(resp.ok, isTrue);
      expect(resp.result, 42);
    });

    test('an error response resolves with ok=false and the error message',
        () async {
      final future = service.debugAwaitRpcResponse('rpc_2');

      service.debugHandleMessage(
        service.settings.rpcResponseTopic,
        jsonEncode(
            {'id': 'rpc_2', 'ok': false, 'result': null, 'error': 'boom'}),
      );

      final resp = await future;
      expect(resp.ok, isFalse);
      expect(resp.error, 'boom');
    });

    test('a response for an unregistered id is dropped without throwing',
        () async {
      // No debugAwaitRpcResponse call for 'unknown_id' — should just log a
      // warning internally and not throw.
      expect(
        () => service.debugHandleMessage(
          service.settings.rpcResponseTopic,
          jsonEncode(
              {'id': 'unknown_id', 'ok': true, 'result': null, 'error': null}),
        ),
        returnsNormally,
      );
    });
  });

  group('debugHandleMessage — malformed payloads never throw', () {
    test('invalid JSON on a known topic is swallowed', () async {
      await service.configure(
        const MqttSettings(mode: AppMode.gateway, brokerHost: ''),
      );
      expect(
        () => service.debugHandleMessage(
            service.settings.flowsTopic, 'not json at all'),
        returnsNormally,
      );
    });

    test('an unrecognized topic is silently ignored', () async {
      expect(
        () => service.debugHandleMessage('some/unrelated/topic', '{}'),
        returnsNormally,
      );
    });
  });
}