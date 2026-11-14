import 'dart:async';
import 'package:flutter/services.dart';

class PtyService {
  static const MethodChannel _methods = MethodChannel('termai/pty');
  static const EventChannel _events = EventChannel('termai/pty-events');
  Stream<Map<String, dynamic>>? _stream;
  int? _sessionId;

  int? get sessionId => _sessionId;
  Stream<Map<String, dynamic>> get events => _stream ??= _events.receiveBroadcastStream().map((event) => Map<String, dynamic>.from(event as Map));

  Future<int> start({String? workingDirectory, String? workspacePath, String? githubToken, int rows = 28, int columns = 100}) async {
    final id = await _methods.invokeMethod<int>('start', {'workingDirectory': workingDirectory ?? '', 'workspacePath': workspacePath ?? '', 'githubToken': githubToken ?? '', 'rows': rows, 'columns': columns});
    if (id == null) throw StateError('Native PTY did not return a session id.');
    _sessionId = id;
    return id;
  }

  Future<void> write(String text) async {
    final id = _sessionId;
    if (id == null) throw StateError('لا توجد جلسة طرفية نشطة.');
    await _methods.invokeMethod<void>('write', {'id': id, 'data': text});
  }

  Future<void> resize(int rows, int columns) async {
    final id = _sessionId;
    if (id != null) await _methods.invokeMethod<void>('resize', {'id': id, 'rows': rows, 'columns': columns});
  }

  Future<void> close() async {
    final id = _sessionId;
    _sessionId = null;
    if (id != null) await _methods.invokeMethod<void>('close', {'id': id});
  }
}
