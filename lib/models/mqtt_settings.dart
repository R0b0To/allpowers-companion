/// Operating mode of the app with respect to MQTT.
///
/// [standalone] — classic BLE-only behaviour, no MQTT involvement.
/// [gateway]    — holds the BLE connection; publishes status and subscribes
///                to commands so other phones can monitor/control remotely.
/// [client]     — no BLE required; subscribes to the gateway's status topic
///                and publishes commands for the gateway to execute.
enum AppMode { standalone, gateway, client }

/// Immutable MQTT configuration bundle.
final class MqttSettings {
  const MqttSettings({
    this.mode = AppMode.standalone,
    this.brokerHost = '',
    this.port = 1883,
    this.username = '',
    this.password = '',
    this.topicPrefix = 'ap/station',
    this.useTls = false,
    this.clientId = '',
  });

  final AppMode mode;

  /// Hostname or IP of the MQTT broker (e.g. "broker.hivemq.com").
  final String brokerHost;

  /// TCP port — typically 1883 (plain) or 8883 (TLS).
  final int port;

  final String username;
  final String password;

  /// Prefix for all topics, e.g. "ap/garage" → "ap/garage/status".
  /// Gateway and client phones must use the same prefix to talk to each other.
  final String topicPrefix;

  final bool useTls;

  /// MQTT client identifier. Leave empty to auto-generate a unique ID.
  final String clientId;

  /// True if enough info is present to attempt a connection.
  bool get isConfigured =>
      brokerHost.trim().isNotEmpty && topicPrefix.trim().isNotEmpty;

  // ── Derived topic names ───────────────────────────────────────────────────

  /// The gateway publishes station telemetry here; clients subscribe.
  String get statusTopic => '$topicPrefix/status';

  String get commandTopic => '$topicPrefix/cmd';

  /// The gateway subscribes to config updates here; clients publish.
  String get configTopic => '$topicPrefix/config';

  /// Retained; both gateway and client publish/subscribe to keep flows in sync.
  String get flowsTopic => '$topicPrefix/flows';

  /// RPC request topic — client publishes, gateway subscribes.
  String get rpcRequestTopic => '$topicPrefix/rpc/request';

  /// RPC response topic — gateway publishes, client subscribes.
  String get rpcResponseTopic => '$topicPrefix/rpc/response';

  /// Retained; gateway publishes full Tapo device list (with runtime state),
  /// client subscribes to display and interact with plugs remotely.
  String get tapoDevicesTopic => '$topicPrefix/tapo/devices';

  /// Single new history entry (not retained) — gateway publishes on each
  /// automation action so clients get live events.
  String get historyTopic => '$topicPrefix/history';

  /// Full history snapshot (retained) — gateway publishes on connect so
  /// freshly-connected clients receive the complete log immediately.
  String get historySnapshotTopic => '$topicPrefix/history/snapshot';

  // ── Mutation ──────────────────────────────────────────────────────────────

  MqttSettings copyWith({
    AppMode? mode,
    String? brokerHost,
    int? port,
    String? username,
    String? password,
    String? topicPrefix,
    bool? useTls,
    String? clientId,
  }) {
    return MqttSettings(
      mode: mode ?? this.mode,
      brokerHost: brokerHost ?? this.brokerHost,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      topicPrefix: topicPrefix ?? this.topicPrefix,
      useTls: useTls ?? this.useTls,
      clientId: clientId ?? this.clientId,
    );
  }

  // ── Equality ──────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MqttSettings &&
          other.mode == mode &&
          other.brokerHost == brokerHost &&
          other.port == port &&
          other.username == username &&
          other.password == password &&
          other.topicPrefix == topicPrefix &&
          other.useTls == useTls &&
          other.clientId == clientId;

  @override
  int get hashCode => Object.hash(
        mode,
        brokerHost,
        port,
        username,
        password,
        topicPrefix,
        useTls,
        clientId,
      );
}