

/// Represents a saved TP-Link Tapo smart plug.
final class TapoDevice {
  const TapoDevice({
    required this.id,
    required this.name,
    required this.ip,
    required this.email,
    required this.password,
    this.isOnline = false,
    this.isOn = false,
    this.model = '',
  });

  final String id;
  final String name;
  final String ip;
  final String email;
  final String password;

  /// Runtime-only (not persisted) — updated by [TapoDeviceService].
  final bool isOnline;
  final bool isOn;
  final String model;

  TapoDevice copyWith({
    String? id,
    String? name,
    String? ip,
    String? email,
    String? password,
    bool? isOnline,
    bool? isOn,
    String? model,
  }) {
    return TapoDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      email: email ?? this.email,
      password: password ?? this.password,
      isOnline: isOnline ?? this.isOnline,
      isOn: isOn ?? this.isOn,
      model: model ?? this.model,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ip': ip,
        'email': email,
        'password': password,
      };

  static TapoDevice? tryFromJson(Map<String, dynamic> j) {
    try {
      return TapoDevice(
        id: j['id'] as String,
        name: j['name'] as String,
        ip: j['ip'] as String,
        email: j['email'] as String,
        password: j['password'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  static TapoDevice fromJson(Map<String, dynamic> j) =>
      TapoDevice(
        id: j['id'] as String,
        name: j['name'] as String,
        ip: j['ip'] as String,
        email: j['email'] as String,
        password: j['password'] as String,
      );
}

/// Generates a unique device ID.
String newDeviceId() =>
    'dev_${DateTime.now().millisecondsSinceEpoch}_${_idCounter++}';

var _idCounter = 0;