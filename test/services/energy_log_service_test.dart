import 'package:flutter_test/flutter_test.dart';

import 'package:ap_companion/models/energy_log_entry.dart';
import 'package:ap_companion/models/power_station_status.dart';
import 'package:ap_companion/repositories/energy_log_repository.dart';
import 'package:ap_companion/services/energy_log_service.dart';

void main() {
  late FakeEnergyLogRepository repo;
  late EnergyLogService service;

  setUp(() {
    repo = FakeEnergyLogRepository();
  });

  PowerStationStatus status({int battery = 50, int inputWatts = 10}) =>
      PowerStationStatus.validated(
        batteryLevel: battery,
        inputWatts: inputWatts,
        outputWatts: 0,
        minutesRemaining: 0,
        isUsbOn: true,
        isAcOn: false,
        isDcOn: false,
      );

  group('init', () {
    test('loads persisted entries and marks isLoaded', () async {
      repo.stored = [
        EnergyLogEntry(
          timestamp: DateTime.utc(2026, 1, 1),
          batteryLevel: 40,
          inputWatts: 0,
          outputWatts: 0,
          isUsbOn: false,
          isAcOn: false,
          isDcOn: false,
        ),
      ];
      service = EnergyLogService(repo);

      expect(service.isLoaded, isFalse);
      await service.init();

      expect(service.isLoaded, isTrue);
      expect(service.entries, hasLength(1));
    });
  });

  group('recordSample', () {
    test('ignores samples recorded before init completes', () async {
      service = EnergyLogService(repo);
      await service.recordSample(status());

      expect(service.entries, isEmpty);
      expect(repo.appendCount, 0);
    });

    test('ignores a bogus zero battery reading', () async {
      service = EnergyLogService(repo);
      await service.init();
      await service.recordSample(status(battery: 0));

      expect(service.entries, isEmpty);
      expect(repo.appendCount, 0);
    });

    test('records the first sample unconditionally', () async {
      service = EnergyLogService(repo);
      await service.init();
      await service.recordSample(status());

      expect(service.entries, hasLength(1));
      expect(repo.appendCount, 1);
    });

    test('throttles: a second sample within the interval is dropped',
        () async {
      service = EnergyLogService(repo, interval: const Duration(minutes: 5));
      await service.init();
      await service.recordSample(status());
      await service.recordSample(status(battery: 60));

      expect(service.entries, hasLength(1));
      expect(repo.appendCount, 1);
    });

    test(
        'the in-memory list is capped at maxEntries even though '
        'appendEntry no longer truncates on every write', () async {
      // Regression test: previously the in-memory `_entries` list grew
      // unbounded for the life of the app session — only the on-disk
      // SharedPreferences write truncated, via a whole-list rewrite. The
      // SQLite repository appends single rows instead, so EnergyLogService
      // must enforce this cap itself now.
      service = EnergyLogService(
        repo,
        interval: Duration.zero, // no throttling — every call records
      );
      await service.init();

      const cap = EnergyLogRepository.maxEntries;
      for (var i = 0; i < cap + 10; i++) {
        await service.recordSample(status(battery: 1 + (i % 99)));
      }

      expect(service.entries.length, cap);
      // The oldest 10 samples should have fallen off the front.
      expect(repo.appendCount, cap + 10);
    });
  });

  group('since', () {
    test('returns only entries within the requested duration', () async {
      final now = DateTime.now().toUtc();
      repo.stored = [
        EnergyLogEntry(
          timestamp: now.subtract(const Duration(hours: 2)),
          batteryLevel: 10,
          inputWatts: 0,
          outputWatts: 0,
          isUsbOn: false,
          isAcOn: false,
          isDcOn: false,
        ),
        EnergyLogEntry(
          timestamp: now.subtract(const Duration(minutes: 10)),
          batteryLevel: 20,
          inputWatts: 0,
          outputWatts: 0,
          isUsbOn: false,
          isAcOn: false,
          isDcOn: false,
        ),
      ];
      service = EnergyLogService(repo);
      await service.init();

      final recent = service.since(const Duration(hours: 1));

      expect(recent, hasLength(1));
      expect(recent.single.batteryLevel, 20);
    });

    test('returns an empty list when there are no entries', () async {
      service = EnergyLogService(repo);
      await service.init();

      expect(service.since(const Duration(hours: 1)), isEmpty);
    });
  });

  group('clear', () {
    test('empties both the in-memory list and the repository', () async {
      service = EnergyLogService(repo);
      await service.init();
      await service.recordSample(status());
      expect(service.entries, isNotEmpty);

      await service.clear();

      expect(service.entries, isEmpty);
      expect(repo.stored, isEmpty);
    });
  });
}

class FakeEnergyLogRepository implements EnergyLogRepository {
  List<EnergyLogEntry> stored = [];
  int appendCount = 0;

  @override
  Future<List<EnergyLogEntry>> loadLog() async => stored;

  @override
  Future<void> appendEntry(EnergyLogEntry entry) async {
    appendCount++;
    stored = [...stored, entry];
  }

  @override
  Future<void> clearLog() async {
    stored = [];
  }
}