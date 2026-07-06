import 'package:flutter_test/flutter_test.dart';

import 'package:ap_companion/models/mqtt_settings.dart';
import 'package:ap_companion/services/mqtt_message_router.dart';

void main() {
  const clientSettings = MqttSettings(mode: AppMode.client, brokerHost: 'x');
  const gatewaySettings = MqttSettings(mode: AppMode.gateway, brokerHost: 'x');

  group('flows topic', () {
    test('decodes a valid flow list', () {
      final result = MqttMessageRouter.route(
        topic: clientSettings.flowsTopic,
        raw: '''
          [{
            "id": "f1", "name": "Test", "enabled": true,
            "trigger": {"type": "batteryFallsBelow", "threshold": 10, "requirePlugState": false},
            "actions": []
          }]
        ''',
        settings: clientSettings,
      );

      expect(result, isA<FlowsSyncMessage>());
      expect((result as FlowsSyncMessage).flows, hasLength(1));
      expect(result.flows.single.id, 'f1');
    });

    test('an entry that fails to parse is dropped, not the whole message', () {
      final result = MqttMessageRouter.route(
        topic: clientSettings.flowsTopic,
        raw: '[{"id": "bad"}, {"garbage": true}]',
        settings: clientSettings,
      );

      expect(result, isA<FlowsSyncMessage>());
      expect((result as FlowsSyncMessage).flows, isEmpty);
    });

    test('invalid JSON is reported as MalformedMessage', () {
      final result = MqttMessageRouter.route(
        topic: clientSettings.flowsTopic,
        raw: 'not json',
        settings: clientSettings,
      );

      expect(result, isA<MalformedMessage>());
    });

    test('a JSON object instead of a list is reported as MalformedMessage', () {
      final result = MqttMessageRouter.route(
        topic: clientSettings.flowsTopic,
        raw: '{"not": "a list"}',
        settings: clientSettings,
      );

      expect(result, isA<MalformedMessage>());
    });
  });

  group('tapo/devices topic', () {
    test('decodes a device list including runtime fields', () {
      final result = MqttMessageRouter.route(
        topic: clientSettings.tapoDevicesTopic,
        raw: '''
          [{"id":"d1","name":"Garage","ip":"1.2.3.4","email":"a@b.com",
            "password":"x","isOnline":true,"isOn":false,"model":"P110"}]
        ''',
        settings: clientSettings,
      );

      expect(result, isA<TapoDevicesMessage>());
      final devices = (result as TapoDevicesMessage).devices;
      expect(devices, hasLength(1));
      expect(devices.single.name, 'Garage');
      expect(devices.single.isOnline, isTrue);
      expect(devices.single.isOn, isFalse);
    });

    test('a malformed device entry is dropped, others still decode', () {
      final result = MqttMessageRouter.route(
        topic: clientSettings.tapoDevicesTopic,
        raw: '''
          [
            {"id":"d1","name":"Garage","ip":"1.2.3.4","email":"a@b.com","password":"x"},
            {"missing":"required fields"}
          ]
        ''',
        settings: clientSettings,
      );

      expect(result, isA<TapoDevicesMessage>());
      expect((result as TapoDevicesMessage).devices, hasLength(1));
    });
  });

  group('rpc/request topic', () {
    test('decodes id, method, and params', () {
      final result = MqttMessageRouter.route(
        topic: gatewaySettings.rpcRequestTopic,
        raw:
            '{"id":"r1","method":"tapo.setOn","params":{"deviceId":"d1","on":true}}',
        settings: gatewaySettings,
      );

      expect(result, isA<RpcRequestMessage>());
      final req = (result as RpcRequestMessage).request;
      expect(req.id, 'r1');
      expect(req.method, 'tapo.setOn');
      expect(req.params, {'deviceId': 'd1', 'on': true});
    });

    test('defaults params to an empty map when omitted', () {
      final result = MqttMessageRouter.route(
        topic: gatewaySettings.rpcRequestTopic,
        raw: '{"id":"r1","method":"tapo.refresh"}',
        settings: gatewaySettings,
      );

      expect((result as RpcRequestMessage).request.params, isEmpty);
    });

    test('a missing method is reported as MalformedMessage', () {
      final result = MqttMessageRouter.route(
        topic: gatewaySettings.rpcRequestTopic,
        raw: '{"id":"r1"}',
        settings: gatewaySettings,
      );

      expect(result, isA<MalformedMessage>());
    });
  });

  group('rpc/response topic', () {
    test('decodes a successful response', () {
      final result = MqttMessageRouter.route(
        topic: clientSettings.rpcResponseTopic,
        raw: '{"id":"r1","ok":true,"result":{"count":3},"error":null}',
        settings: clientSettings,
      );

      expect(result, isA<RpcResponseMessage>());
      final resp = (result as RpcResponseMessage).response;
      expect(resp.ok, isTrue);
      expect(resp.result, {'count': 3});
    });

    test('a response missing required fields is MalformedMessage', () {
      final result = MqttMessageRouter.route(
        topic: clientSettings.rpcResponseTopic,
        raw: '{"id":"r1"}', // missing "ok"
        settings: clientSettings,
      );

      expect(result, isA<MalformedMessage>());
    });
  });

  group('history topic (single entry)', () {
    test('decodes one entry', () {
      final result = MqttMessageRouter.route(
        topic: clientSettings.historyTopic,
        raw: '''
          {"timestamp":"2026-01-01T00:00:00.000Z","action":"tapoOn",
           "batteryLevel":50,"success":true,"method":"localTapo",
           "flowName":"","deviceName":""}
        ''',
        settings: clientSettings,
      );

      expect(result, isA<HistoryEntryMessage>());
      expect((result as HistoryEntryMessage).entry.batteryLevel, 50);
    });

    test('an unparsable entry is MalformedMessage', () {
      final result = MqttMessageRouter.route(
        topic: clientSettings.historyTopic,
        raw: '{"garbage": true}',
        settings: clientSettings,
      );

      expect(result, isA<MalformedMessage>());
    });
  });

  group('history/snapshot topic (list)', () {
    test('decodes multiple entries, dropping any that fail to parse', () {
      final result = MqttMessageRouter.route(
        topic: clientSettings.historySnapshotTopic,
        raw: '''
          [
            {"timestamp":"2026-01-01T00:00:00.000Z","action":"tapoOn",
             "batteryLevel":50,"success":true,"method":"localTapo"},
            {"garbage": true}
          ]
        ''',
        settings: clientSettings,
      );

      expect(result, isA<HistorySnapshotMessage>());
      expect((result as HistorySnapshotMessage).entries, hasLength(1));
    });

    test('an empty list still decodes as an (empty) HistorySnapshotMessage', () {
      final result = MqttMessageRouter.route(
        topic: clientSettings.historySnapshotTopic,
        raw: '[]',
        settings: clientSettings,
      );

      expect(result, isA<HistorySnapshotMessage>());
      expect((result as HistorySnapshotMessage).entries, isEmpty);
    });
  });

  group('status topic — gated to client mode', () {
    test('decodes status fields when mode is client', () {
      final result = MqttMessageRouter.route(
        topic: clientSettings.statusTopic,
        raw: '''
          {"batteryLevel":80,"inputWatts":50,"outputWatts":0,
           "minutesRemaining":30,"isUsbOn":true,"isAcOn":false,"isDcOn":false,
           "bleConnected":true}
        ''',
        settings: clientSettings,
      );

      expect(result, isA<StatusMessage>());
      final msg = result as StatusMessage;
      expect(msg.status.batteryLevel, 80);
      expect(msg.status.isUsbOn, isTrue);
      expect(msg.bleConnected, isTrue);
    });

    test('clamps out-of-range fields via PowerStationStatus.validated', () {
      final result = MqttMessageRouter.route(
        topic: clientSettings.statusTopic,
        raw: '{"batteryLevel": 500, "inputWatts": -10}',
        settings: clientSettings,
      );

      final msg = result as StatusMessage;
      expect(msg.status.batteryLevel, 100);
      expect(msg.status.inputWatts, 0);
    });

    test('is ignored (UnrecognizedMessage) when mode is gateway', () {
      final result = MqttMessageRouter.route(
        topic: gatewaySettings.statusTopic,
        raw: '{"batteryLevel": 80}',
        settings: gatewaySettings,
      );

      expect(result, isA<UnrecognizedMessage>());
    });
  });

  group('command topic — gated to gateway mode', () {
    test('decodes the outlet name from the topic suffix when mode is gateway',
        () {
      final result = MqttMessageRouter.route(
        topic: '${gatewaySettings.commandTopic}/ac',
        raw: '{"value": true}',
        settings: gatewaySettings,
      );

      expect(result, isA<CommandMessage>());
      final msg = result as CommandMessage;
      expect(msg.outlet, 'ac');
      expect(msg.value, isTrue);
    });

    test('defaults value to false when omitted', () {
      final result = MqttMessageRouter.route(
        topic: '${gatewaySettings.commandTopic}/dc',
        raw: '{}',
        settings: gatewaySettings,
      );

      expect((result as CommandMessage).value, isFalse);
    });

    test('is ignored (UnrecognizedMessage) when mode is client', () {
      final result = MqttMessageRouter.route(
        topic: '${clientSettings.commandTopic}/ac',
        raw: '{"value": true}',
        settings: clientSettings,
      );

      expect(result, isA<UnrecognizedMessage>());
    });
  });

  group('unmatched topics', () {
    test('a topic matching nothing configured returns UnrecognizedMessage', () {
      final result = MqttMessageRouter.route(
        topic: 'totally/unrelated/topic',
        raw: '{}',
        settings: clientSettings,
      );

      expect(result, isA<UnrecognizedMessage>());
    });
  });

  group('topic precedence', () {
    test('an exact flowsTopic match is checked before the command-prefix check',
        () {
      // Regression guard for ordering: flows/tapoDevices/rpc/history checks
      // must run before the startsWith(commandTopic) check.
      const settings = MqttSettings(
          mode: AppMode.gateway, brokerHost: 'x', topicPrefix: 'ap');
      final result = MqttMessageRouter.route(
        topic: settings.flowsTopic,
        raw: '[]',
        settings: settings,
      );

      expect(result, isA<FlowsSyncMessage>());
    });
  });
}