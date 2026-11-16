// TERMAI_GITHUB_AUTOMATION_UPDATE_20261116_V1
import 'dart:async';
import 'package:flutter/services.dart';

/// Controls the app-private Ubuntu/PRoot runtime installed by Android native code.
class LinuxRuntimeService {
  static const MethodChannel _channel = MethodChannel('termai/linux');

  static const EventChannel _installEventsChannel =
      EventChannel('termai/linux/install-events');

  static const EventChannel _deploymentEventsChannel =
      EventChannel('termai/linux/deployment-events');

  late final Stream<Map<String, dynamic>> deploymentEvents =
      _deploymentEventsChannel.receiveBroadcastStream().map(
        (event) => Map<String, dynamic>.from(event as Map),
      ).asBroadcastStream();

  late final Stream<Map<String, dynamic>> installEvents =
      _installEventsChannel
          .receiveBroadcastStream()
          .map((event) => Map<String, dynamic>.from(event as Map))
          .asBroadcastStream();

  Future<bool> isInstalled() async =>
      await _channel.invokeMethod<bool>('isInstalled') ?? false;

  // ARAM_NEXUS_SOURCE_UPDATE_20261116: query persisted installation state after reconnecting.
  Future<Map<String, dynamic>> installStatus() async {
    final value = await _channel.invokeMapMethod<String, dynamic>('installStatus');
    return value ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> publishWorkspace({
    required String projectId,
    required String workspacePath,
    required String repository,
    required String token,
    required String commitMessage,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'publishWorkspace',
      <String, Object?>{
        'projectId': projectId,
        'workspacePath': workspacePath,
        'repository': repository,
        'token': token,
        'commitMessage': commitMessage,
      },
    );
    if (result == null) {
      throw StateError('Linux returned no Git publishing result.');
    }
    return result;
  }

  Future<Map<String, dynamic>> install() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('install');
    if (result == null || result['installed'] != true) {
      throw StateError('لم يؤكد محرك Android اكتمال تثبيت Ubuntu.');
    }
    return result;
  }
}
