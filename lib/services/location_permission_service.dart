import 'package:flutter/services.dart';

class LocationPermissionService {
  const LocationPermissionService();

  static const _channel = MethodChannel('cn.sjtu.jiaotong_course/permissions');

  Future<bool> request() async {
    try {
      return await _channel.invokeMethod<bool>('requestLocationPermission') ??
          false;
    } catch (_) {
      return false;
    }
  }
}
