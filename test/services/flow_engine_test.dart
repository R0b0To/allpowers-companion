import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ap_companion/models/automation_flow.dart';
import 'package:ap_companion/models/automation_history_entry.dart';
import 'package:ap_companion/models/power_station_status.dart';
import 'package:ap_companion/models/tapo_device.dart';
import 'package:ap_companion/repositories/ble_repository.dart';
import 'package:ap_companion/repositories/flow_repository.dart';
import 'package:ap_companion/repositories/history_repository.dart';
import 'package:ap_companion/repositories/tapo_repository.dart';
import 'package:ap_companion/services/ble_service.dart';
import 'package:ap_companion/services/flow_engine.dart';
import 'package:ap_companion/services/history_service.dart';
import 'package:ap_companion/services/tapo_device_service.dart';
import 'package:ap_companion/services/tapo_service.dart';
import 'package:ap_companion/services/webhook_service.dart';

/// Coverage scope for this file, and what's deliberately excluded:
///
/// [FlowEngine] is exercised end-to-end against real [BleService],
/// [HistoryService], and [TapoDeviceService] instances, but backed by
/// hand-rolled in-memory fakes for their repositories — no SharedPreferences,
/// no platform channels, no real network.
///
/// [BleService.status] is a plain mutable field, so tests drive it directly
/// instead of simulating BLE packets — [BleService.setUsb]/[setAc]/[setDc]
/// are also safe to call for real here: with no write characteristic
/// discovered (no real device connected), they log a warning and return
/// without touching any platform API.
///
/// [TapoDeviceService.replaceAll] (normally used for MQTT client-mode state
/// sync) doubles as a test seam here: it sets device state synchronously
/// with zero network I/O, which is exactly what's needed to test
/// [FlowTrigger.requirePlugState] / [FlowTriggerType.tapoPlugState] without
/// touching [TapoService]'s real KLAP handshake.
///
/// What's NOT covered here, on purpose: any [FlowActionType.controlTapo] or
/// [FlowActionType.fireWebhook] action actually executing. Both would hit
/// real I/O (TapoService's HTTP handshake, WebhookService's HTTP GET) that
/// isn't reachable in a unit test environment, and retrying against an
/// unreachable host would make these tests slow and flaky rather than fast
/// and deterministic. Covering those requires extracting an interface
/// [TapoService]/[WebhookService] can implement so a fake can be injected —
/// tracked as a follow-up rather than solved here.
void main() {
  late FakeFlowRepository flowRepo;
  late FakeHistoryRepository historyRepo;
  late BleService ble;
  late HistoryService history;
  late TapoDeviceService tapoDevices;
  late FlowEngine engine;

  // Flushes pending microtasks so fire-and-forget evaluations (started by
  // FlowEngine.evaluate/evaluateTapoTriggers, which do not await their
  // per-flow futures) have finished before assertions run.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  AutomationFlow makeFlow({
    required FlowTrigger trigger,
    List<FlowAction> actions = const [],
    bool enabled = true,
    String id = 'flow_1',
  }) =>
      AutomationFlow(
        id: id,
        name: 'Test Flow',
        trigger: trigger,
        actions: actions,
        enabled: enabled,
      );

  // A 1-minute window guaranteed not to contain "now", regardless of when
  // the test suite happens to run.
  (TimeOfDay, TimeOfDay) windowExcludingNow() {
    final now = TimeOfDay.now();
    final nowMin = now.hour * 60 + now.minute;
    final startMin = (nowMin + 120) % 1440;
    final endMin = (startMin + 1) % 1440;
    TimeOfDay fromMinutes(int m) => TimeOfDay(hour: m ~/ 60, minute: m % 60);
    return (fromMinutes(startMin), fromMinutes(endMin));
  }

  setUp(() async {
    flowRepo = FakeFlowRepository();
    historyRepo = FakeHistoryRepository();

    ble = BleService(FakeBleRepository());
    history = HistoryService(historyRepo);
    await history.init();
    tapoDevices = TapoDeviceService(TapoService(), FakeTapoRepository());

    engine = FlowEngine(
      ble,
      WebhookService(),
      TapoService(),
      tapoDevices,
      history,
      flowRepo,
    );
  });

  group('batteryFallsBelow trigger', () {
    test('fires once and does not re-fire while still below threshold (edge-trigger guard)',
        () async {
      ble.status = const PowerStationStatus(batteryLevel: 5);
      final flow = makeFlow(
        trigger:
            const FlowTrigger(type: FlowTriggerType.batteryFallsBelow, threshold: 10),
        actions: const [
          FlowAction(
              id: 'a1',
              type: FlowActionType.setBleOutlet,
              outlet: BleOutlet.ac,
              outletOn: true),
        ],
      );
      await engine.init([flow]);

      await engine.evaluate([flow]);
      await settle();
      await engine.evaluate([flow]);
      await settle();

      expect(history.entries, hasLength(1));
      expect(await flowRepo.getFlowTriggered(flow.id), isTrue);
    });

    test('fires again after the condition clears and re-triggers', () async {
      final flow = makeFlow(
        trigger:
            const FlowTrigger(type: FlowTriggerType.batteryFallsBelow, threshold: 10),
        actions: const [
          FlowAction(
              id: 'a1',
              type: FlowActionType.setBleOutlet,
              outlet: BleOutlet.ac,
              outletOn: true),
        ],
      );
      await engine.init([flow]);

      ble.status = const PowerStationStatus(batteryLevel: 5);
      await engine.evaluate([flow]);
      await settle();
      expect(history.entries, hasLength(1));

      // Battery recovers above threshold — guard resets, no new action.
      ble.status = const PowerStationStatus(batteryLevel: 50);
      await engine.evaluate([flow]);
      await settle();
      expect(await flowRepo.getFlowTriggered(flow.id), isFalse);
      expect(history.entries, hasLength(1));

      // Drops below threshold again — fires a second time.
      ble.status = const PowerStationStatus(batteryLevel: 5);
      await engine.evaluate([flow]);
      await settle();
      expect(history.entries, hasLength(2));
    });

    test('does not fire outside the configured time window', () async {
      final (start, end) = windowExcludingNow();
      ble.status = const PowerStationStatus(batteryLevel: 5);
      final flow = makeFlow(
        trigger: FlowTrigger(
          type: FlowTriggerType.batteryFallsBelow,
          threshold: 10,
          windowStart: start,
          windowEnd: end,
        ),
      );
      await engine.init([flow]);

      await engine.evaluate([flow]);
      await settle();

      expect(await flowRepo.getFlowTriggered(flow.id), isFalse);
    });

    test('ignores a bogus zero battery reading', () async {
      ble.status = const PowerStationStatus(batteryLevel: 0);
      final flow = makeFlow(
        trigger:
            const FlowTrigger(type: FlowTriggerType.batteryFallsBelow, threshold: 10),
      );
      await engine.init([flow]);

      await engine.evaluate([flow]);
      await settle();

      expect(await flowRepo.getFlowTriggered(flow.id), isFalse);
    });
  });

  group('batteryRisesAbove trigger', () {
    test('fires once when level reaches the threshold', () async {
      ble.status = const PowerStationStatus(batteryLevel: 96);
      final flow = makeFlow(
        trigger:
            const FlowTrigger(type: FlowTriggerType.batteryRisesAbove, threshold: 95),
        actions: const [
          FlowAction(
              id: 'a1',
              type: FlowActionType.setBleOutlet,
              outlet: BleOutlet.ac,
              outletOn: false),
        ],
      );
      await engine.init([flow]);

      await engine.evaluate([flow]);
      await settle();

      expect(history.entries, hasLength(1));
      expect(await flowRepo.getFlowTriggered(flow.id), isTrue);
    });

    test('resets once level drops back below threshold', () async {
      final flow = makeFlow(
        trigger:
            const FlowTrigger(type: FlowTriggerType.batteryRisesAbove, threshold: 95),
      );
      await engine.init([flow]);

      ble.status = const PowerStationStatus(batteryLevel: 96);
      await engine.evaluate([flow]);
      await settle();
      expect(await flowRepo.getFlowTriggered(flow.id), isTrue);

      ble.status = const PowerStationStatus(batteryLevel: 50);
      await engine.evaluate([flow]);
      await settle();
      expect(await flowRepo.getFlowTriggered(flow.id), isFalse);
    });
  });

  group('combined battery + plug condition (requirePlugState)', () {
    test('fires only once the required device is also in the expected state', () async {
      const device = TapoDevice(
        id: 'dev1',
        name: 'Garage',
        ip: '1.2.3.4',
        email: 'a@b.com',
        password: 'x',
        isOnline: true,
        isOn: true, // plug currently ON
      );
      tapoDevices.replaceAll([device]);

      ble.status = const PowerStationStatus(batteryLevel: 5);
      final flow = makeFlow(
        trigger: const FlowTrigger(
          type: FlowTriggerType.batteryFallsBelow,
          threshold: 10,
          requirePlugState: true,
          tapoDeviceId: 'dev1',
          tapoExpectedOn: false, // requires plug OFF — currently ON
        ),
      );
      await engine.init([flow]);
      await engine.evaluate([flow]);
      await settle();
      expect(await flowRepo.getFlowTriggered(flow.id), isFalse);

      // Plug turns off — condition now satisfied.
      tapoDevices.replaceAll([device.copyWith(isOn: false)]);
      await engine.evaluate([flow]);
      await settle();
      expect(await flowRepo.getFlowTriggered(flow.id), isTrue);
    });

    test('skips evaluation (no fire, no reset) while the device is offline', () async {
      const device = TapoDevice(
        id: 'dev1',
        name: 'Garage',
        ip: '1.2.3.4',
        email: 'a@b.com',
        password: 'x',
        isOnline: false,
        isOn: false,
      );
      tapoDevices.replaceAll([device]);

      ble.status = const PowerStationStatus(batteryLevel: 5);
      final flow = makeFlow(
        trigger: const FlowTrigger(
          type: FlowTriggerType.batteryFallsBelow,
          threshold: 10,
          requirePlugState: true,
          tapoDeviceId: 'dev1',
          tapoExpectedOn: false,
        ),
      );
      await engine.init([flow]);
      await engine.evaluate([flow]);
      await settle();

      expect(await flowRepo.getFlowTriggered(flow.id), isFalse);
      expect(history.entries, isEmpty);
    });

    test('fails closed when requirePlugState is set but no device is selected', () async {
      ble.status = const PowerStationStatus(batteryLevel: 5);
      final flow = makeFlow(
        trigger: const FlowTrigger(
          type: FlowTriggerType.batteryFallsBelow,
          threshold: 10,
          requirePlugState: true,
          // tapoDeviceId intentionally omitted
        ),
      );
      await engine.init([flow]);
      await engine.evaluate([flow]);
      await settle();

      expect(await flowRepo.getFlowTriggered(flow.id), isFalse);
    });
  });

  group('tapoPlugState trigger', () {
    test('fires when the plug is found in the "wrong" state', () async {
      const device = TapoDevice(
        id: 'dev1',
        name: 'Garage',
        ip: '1.2.3.4',
        email: 'a@b.com',
        password: 'x',
        isOnline: true,
        isOn: false, // currently OFF
      );
      tapoDevices.replaceAll([device]);

      final flow = makeFlow(
        trigger: const FlowTrigger(
          type: FlowTriggerType.tapoPlugState,
          threshold: 0,
          tapoDeviceId: 'dev1',
          tapoExpectedOn: true, // desired ON — currently OFF → "wrong"
        ),
      );
      await engine.init([flow]);
      await engine.evaluate([flow]);
      await settle();

      expect(await flowRepo.getFlowTriggered(flow.id), isTrue);
    });

    test('does not fire while the device is offline', () async {
      const device = TapoDevice(
        id: 'dev1',
        name: 'Garage',
        ip: '1.2.3.4',
        email: 'a@b.com',
        password: 'x',
        isOnline: false,
        isOn: true,
      );
      tapoDevices.replaceAll([device]);

      final flow = makeFlow(
        trigger: const FlowTrigger(
          type: FlowTriggerType.tapoPlugState,
          threshold: 0,
          tapoDeviceId: 'dev1',
          tapoExpectedOn: true,
        ),
      );
      await engine.init([flow]);
      await engine.evaluate([flow]);
      await settle();

      expect(await flowRepo.getFlowTriggered(flow.id), isFalse);
    });

    test('resets the guard once the plug matches the expected state', () async {
      const device = TapoDevice(
        id: 'dev1',
        name: 'Garage',
        ip: '1.2.3.4',
        email: 'a@b.com',
        password: 'x',
        isOnline: true,
        isOn: false,
      );
      tapoDevices.replaceAll([device]);

      final flow = makeFlow(
        trigger: const FlowTrigger(
          type: FlowTriggerType.tapoPlugState,
          threshold: 0,
          tapoDeviceId: 'dev1',
          tapoExpectedOn: true,
        ),
      );
      await engine.init([flow]);
      await engine.evaluate([flow]);
      await settle();
      expect(await flowRepo.getFlowTriggered(flow.id), isTrue);

      tapoDevices.replaceAll([device.copyWith(isOn: true)]); // now matches
      await engine.evaluate([flow]);
      await settle();
      expect(await flowRepo.getFlowTriggered(flow.id), isFalse);
    });
  });

  group('action execution (evaluateOnce)', () {
    test('runs actions in order and records history', () async {
      final flow = makeFlow(
        trigger:
            const FlowTrigger(type: FlowTriggerType.batteryFallsBelow, threshold: 10),
        actions: const [
          FlowAction(id: 'a1', type: FlowActionType.wait, waitSeconds: 0),
          FlowAction(
              id: 'a2',
              type: FlowActionType.setBleOutlet,
              outlet: BleOutlet.dc,
              outletOn: true),
        ],
      );
      ble.status = const PowerStationStatus(batteryLevel: 42);
      await engine.init([flow]);

      await engine.evaluateOnce(flow);

      expect(history.entries, hasLength(1));
      expect(history.entries.single.action, HistoryAction.outletToggled);
      expect(history.entries.single.batteryLevel, 42);
      expect(ble.status.isDcOn, isTrue);
    });

    test('the per-flow running lock prevents overlapping execution', () async {
      final flow = makeFlow(
        trigger:
            const FlowTrigger(type: FlowTriggerType.batteryFallsBelow, threshold: 10),
        actions: const [
          FlowAction(id: 'a1', type: FlowActionType.wait, waitSeconds: 0),
          FlowAction(
              id: 'a2',
              type: FlowActionType.setBleOutlet,
              outlet: BleOutlet.usb,
              outletOn: true),
        ],
      );
      await engine.init([flow]);

      // Both calls start synchronously; the second sees the lock already
      // held (set before the first `await`) and returns immediately.
      final first = engine.evaluateOnce(flow);
      final second = engine.evaluateOnce(flow);
      await Future.wait([first, second]);

      expect(history.entries, hasLength(1));
    });
  });

  group('flow lifecycle', () {
    test('onFlowDeleted clears trigger and running state', () async {
      final flow = makeFlow(
        trigger:
            const FlowTrigger(type: FlowTriggerType.batteryFallsBelow, threshold: 10),
      );
      ble.status = const PowerStationStatus(batteryLevel: 5);
      await engine.init([flow]);
      await engine.evaluate([flow]);
      await settle();
      expect(await flowRepo.getFlowTriggered(flow.id), isTrue);

      await engine.onFlowDeleted(flow.id);

      expect(await flowRepo.getFlowTriggered(flow.id), isFalse);
    });

    test('resetTriggeredForFlow allows an immediate re-fire without the condition changing',
        () async {
      final flow = makeFlow(
        trigger:
            const FlowTrigger(type: FlowTriggerType.batteryFallsBelow, threshold: 10),
        actions: const [
          FlowAction(
              id: 'a1',
              type: FlowActionType.setBleOutlet,
              outlet: BleOutlet.ac,
              outletOn: true),
        ],
      );
      ble.status = const PowerStationStatus(batteryLevel: 5);
      await engine.init([flow]);

      await engine.evaluate([flow]);
      await settle();
      expect(history.entries, hasLength(1));

      // Still below threshold — normally suppressed by the guard.
      await engine.evaluate([flow]);
      await settle();
      expect(history.entries, hasLength(1));

      engine.resetTriggeredForFlow(flow.id);
      await settle();
      await engine.evaluate([flow]);
      await settle();

      expect(history.entries, hasLength(2));
    });
  });
}

// ── Fakes ───────────────────────────────────────────────────────────────────

class FakeFlowRepository implements FlowRepository {
  final Map<String, bool> _triggered = {};
  List<AutomationFlow> savedFlows = [];

  @override
  Future<List<AutomationFlow>> loadFlows() async => savedFlows;

  @override
  Future<void> saveFlows(List<AutomationFlow> flows) async {
    savedFlows = flows;
  }

  @override
  Future<bool> getFlowTriggered(String flowId) async => _triggered[flowId] ?? false;

  @override
  Future<void> setFlowTriggered(String flowId, bool value) async {
    _triggered[flowId] = value;
  }

  @override
  Future<void> clearFlowTriggered(String flowId) async {
    _triggered.remove(flowId);
  }
}

class FakeHistoryRepository implements HistoryRepository {
  List<AutomationHistoryEntry> saved = [];

  @override
  Future<List<AutomationHistoryEntry>> loadHistory() async => saved;

  @override
  Future<void> saveHistory(List<AutomationHistoryEntry> entries) async {
    saved = entries;
  }
}

class FakeBleRepository implements BleRepository {
  String? _id;

  @override
  Future<String?> getSavedDeviceId() async => _id;

  @override
  Future<void> setSavedDeviceId(String id) async => _id = id;

  @override
  Future<void> clearSavedDeviceId() async => _id = null;
}

class FakeTapoRepository implements TapoRepository {
  List<TapoDevice> devices = [];

  @override
  Future<List<TapoDevice>> loadDevices() async => devices;

  @override
  Future<void> saveDevices(List<TapoDevice> d) async => devices = d;
}