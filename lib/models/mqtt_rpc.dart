// lib/models/mqtt_rpc.dart
import 'dart:convert';

final class RpcRequest {
  const RpcRequest({
    required this.id,
    required this.method,
    this.params = const {},
  });

  final String id;
  final String method;
  final Map<String, dynamic> params;

  Map<String, dynamic> toJson() => {
    'id': id,
    'method': method,
    'params': params,
  };

  String toJsonString() => jsonEncode(toJson());
}

final class RpcResponse {
  const RpcResponse({
    required this.id,
    required this.ok,
    this.result,
    this.error,
  });

  final String id;
  final bool ok;
  final dynamic result;
  final String? error;

  static RpcResponse? tryFromJson(Map<String, dynamic> j) {
    try {
      return RpcResponse(
        id:     j['id']     as String,
        ok:     j['ok']     as bool,
        result: j['result'],
        error:  j['error']  as String?,
      );
    } catch (_) {
      return null;
    }
  }
}