import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_shell.dart';
import '../core/aram_engine_bridge.dart';
import '../core/linux_runtime_service.dart';
import '../core/nexus_theme.dart';

/// Mandatory first-run gate. Existing validated resources work without a network;
/// internet is needed only when a missing model or Ubuntu runtime must be obtained.
class StartupGateScreen extends StatefulWidget {
  const StartupGateScreen({super.key});

  @override
  State<StartupGateScreen> createState() => _StartupGateScreenState();
}

class _StartupGateScreenState extends State<StartupGateScreen> {
  static const MethodChannel _engineChannel = MethodChannel('termai/aram-engine');
  final AramEngineBridge _engine = AramEngineBridge();
  final LinuxRuntimeService _linux = LinuxRuntimeService();
  StreamSubscription<Map<String, dynamic>>? _linuxEvents;
  Timer? _poller;
  bool _working = false;
  bool _autoRecoveryStarted = false;
  bool _refreshing = false;
  bool _inferenceVerified = false;
  bool _inferenceCheckRunning = false;
  bool _modelReady = false;
  bool _linuxReady = false;
  bool _canEnter = false;
  String _modelState = 'لم يُفحص النموذج بعد';
  String _linuxState = 'لم تُفحص بيئة Linux بعد';
  String _overall = 'اضغط «تحميل الأدوات» لفحص وتجهيز متطلبات التشغيل.';
  double? _modelProgress;
  double? _linuxProgress;
  String _modelBytes = '';
  String _linuxBytes = '';
  String _failure = '';

  @override
  void initState() {
    super.initState();
    _linuxEvents = _linux.installEvents.listen(_onLinuxEvent, onError: (Object error) {
      if (mounted) setState(() => _linuxState = 'تعذر استقبال تقدم Linux: $error');
    });
    _poller = Timer.periodic(const Duration(seconds: 2), (_) => _refreshStatus(silent: true));
    unawaited(_refreshStatus());
  }

  @override
  void dispose() {
    _poller?.cancel();
    _linuxEvents?.cancel();
    super.dispose();
  }

  void _onLinuxEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final stage = event['stage']?.toString() ?? '';
    final message = event['message']?.toString() ?? '';
    final received = event['downloadedBytes'];
    final total = event['totalBytes'];
    final pct = event['percent'];
    setState(() {
      if (message.isNotEmpty) _linuxState = message;
      if (event['active'] == true) _overall = 'جارٍ إعداد Ubuntu وأدوات Linux…';
      if (stage == 'complete') _linuxReady = true;
      if (stage == 'error' || stage == 'interrupted') _failure = message;
      _linuxProgress = stage == 'download' && pct is num
          ? (pct.toDouble() / 100).clamp(0.0, 1.0).toDouble()
          : null;
      if (received is num && total is num && total > 0) {
        final remaining = (total.toInt() - received.toInt()).clamp(0, total.toInt()).toInt();
        final transferPercent = pct is num ? ' • ${pct.toStringAsFixed(1)}%' : '';
        _linuxBytes = '${_bytes(received.toInt())} / ${_bytes(total.toInt())} • المتبقي ${_bytes(remaining)}$transferPercent';
      } else if (stage.isNotEmpty) {
        _linuxBytes = 'مرحلة: $stage';
      }
    });
  }

  String _bytes(int value) {
    if (value >= 1024 * 1024 * 1024) return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    if (value >= 1024 * 1024) return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(value / 1024).toStringAsFixed(0)} KB';
  }

  Future<bool> _verifyModelInference() async {
    if (_inferenceVerified) return true;
    if (_inferenceCheckRunning) return false;
    _inferenceCheckRunning = true;
    try {
      final output = await _engineChannel.invokeMethod<String>('generate', <String, Object?>{
        'system': 'أنت اختبار جاهزية داخلي لمحرك Aram AI. أجب بكلمة واحدة فقط.',
        'user': 'اكتب: جاهز',
        'temperature': 0.0,
        'maxTokens': 16,
        'requestId': 'startup-smoke-${DateTime.now().microsecondsSinceEpoch}',
      });
      if (output == null || output.trim().isEmpty) {
        throw StateError('لم يُرجع محرك Aram AI ناتج استدلال فعليًا.');
      }
      _inferenceVerified = true;
      return true;
    } finally {
      _inferenceCheckRunning = false;
    }
  }

  Future<void> _refreshStatus({bool silent = false}) async {
    if (_refreshing) {
      while (_refreshing && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      return;
    }
    _refreshing = true;
    try {
      final engineStatus = await _engine.status();
      final modelAvailable = engineStatus['modelAvailable'] == true;
      final loaded = engineStatus['loaded'] == true;
      final engineState = engineStatus['state']?.toString() ?? 'UNKNOWN';
      final transferBytes = (engineStatus['transferBytes'] as num?)?.toInt() ?? 0;
      final transferTotal = (engineStatus['transferTotalBytes'] as num?)?.toInt() ?? -1;
      final transferStage = engineStatus['transferStage']?.toString() ?? '';
      final inferenceReady = modelAvailable && loaded && engineState == 'READY'
          ? await _verifyModelInference()
          : _inferenceVerified;
      final linuxStatus = await _linux.installStatus();
      final installed = linuxStatus['installed'] == true || await _linux.isInstalled();
      final engineOperationActive = <String>{
        'DOWNLOADING_MODEL', 'IMPORTING_MODEL', 'STARTING', 'LOADING_MODEL', 'STARTING_SERVER'
      }.contains(engineState);
      final interruptedLinux = linuxStatus['stage']?.toString() == 'interrupted';
      final activeLinux = linuxStatus['active'] == true;
      if (!mounted) return;
      setState(() {
        _modelReady = modelAvailable && loaded && engineState == 'READY' && inferenceReady;
        _linuxReady = installed;
        _modelState = switch (engineState) {
          'READY' => loaded ? 'نموذج Aram AI محمّل وجاهز' : 'ملف النموذج موجود؛ يحتاج تشغيل المحرك',
          'DOWNLOADING_MODEL' => 'جارٍ تنزيل نموذج Aram AI ($transferStage)',
          'IMPORTING_MODEL' => 'جارٍ استيراد نموذج GGUF والتحقق منه',
          'LOADING_MODEL' => 'جارٍ تحميل أوزان النموذج في الذاكرة',
          'STARTING' || 'STARTING_SERVER' => 'جارٍ تشغيل محرك Aram AI',
          'ERROR' => 'تعذر تجهيز النموذج: ${engineStatus['message'] ?? ''}',
          _ => modelAvailable ? 'ملف GGUF صالح؛ المحرك متوقف' : 'نموذج Aram AI غير موجود',
        };
        if (engineState == 'READY' && loaded && !inferenceReady) {
          _modelState = 'لم يكتمل اختبار الاستدلال الفعلي بعد';
        }
        if (transferTotal > 0) {
          _modelProgress = (transferBytes / transferTotal).clamp(0.0, 1.0).toDouble();
          final remaining = (transferTotal - transferBytes).clamp(0, transferTotal).toInt();
          final percent = (transferBytes / transferTotal * 100).clamp(0, 100);
          _modelBytes = '${_bytes(transferBytes)} / ${_bytes(transferTotal)} • المتبقي ${_bytes(remaining)} • ${percent.toStringAsFixed(1)}%';
        } else {
          _modelProgress = null;
          _modelBytes = transferStage.isEmpty ? 'لا يوجد نقل جارٍ' : 'مرحلة: $transferStage';
        }
        if (installed) _linuxState = 'Ubuntu وأدوات Linux اجتازت فحص الجاهزية';
        if (linuxStatus['active'] == true && !_linuxReady) {
          _linuxState = linuxStatus['message']?.toString() ?? 'تهيئة Linux مستمرة';
        }
        _canEnter = _modelReady && _linuxReady;
        if (_canEnter) _overall = 'اكتمل فحص الموارد والمحرك. يمكنك الدخول إلى التطبيق.';
        else if (!silent && !_working) _overall = 'لم تكتمل جميع متطلبات التشغيل بعد.';
      });
      // Resume an interrupted install or attach to a still-running native download/install.
      // A fresh first run remains opt-in so it never starts a large download unexpectedly.
      if (!_canEnter && !_working && !_autoRecoveryStarted &&
          (interruptedLinux || activeLinux || engineOperationActive)) {
        _autoRecoveryStarted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_working && !_canEnter) unawaited(_runSetup());
        });
      }
    } catch (error) {
      if (mounted && !silent) setState(() => _failure = 'فشل فحص الجاهزية: $error');
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _prepareModel() async {
    var status = await _engine.status();
    var state = status['state']?.toString() ?? 'UNKNOWN';
    if (status['modelAvailable'] != true) {
      if (state != 'DOWNLOADING_MODEL') {
        await _engine.downloadModel();
      }
      while (true) {
        await Future<void>.delayed(const Duration(seconds: 2));
        status = await _engine.status();
        state = status['state']?.toString() ?? 'UNKNOWN';
        if (status['modelAvailable'] == true) break;
        if (state == 'ERROR') {
          throw StateError(status['message']?.toString() ?? 'فشل تنزيل نموذج Aram AI.');
        }
      }
    }
    if (status['loaded'] != true &&
        !{'STARTING', 'LOADING_MODEL', 'STARTING_SERVER'}.contains(state)) {
      await _engine.start();
    }
    while (true) {
      await Future<void>.delayed(const Duration(seconds: 2));
      status = await _engine.status();
      state = status['state']?.toString() ?? 'UNKNOWN';
      if (status['modelAvailable'] == true && status['loaded'] == true && state == 'READY') return;
      if (state == 'ERROR') {
        throw StateError(status['message']?.toString() ?? 'فشل تشغيل نموذج Aram AI.');
      }
    }
  }

  Future<void> _prepareLinux() async {
    if (await _linux.isInstalled()) return;
    // If the same Android process still owns a live installation worker, attach by
    // polling its persisted status instead of issuing a second install() call.
    while (true) {
      final status = await _linux.installStatus();
      if (status['installed'] == true || await _linux.isInstalled()) return;
      if (status['active'] != true) break;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    final result = await _linux.install();
    if (result['installed'] != true || !await _linux.isInstalled()) {
      throw StateError('لم يجتز Ubuntu وأدوات Linux فحص التثبيت النهائي.');
    }
  }

  Future<void> _runSetup() async {
    if (_working || _canEnter) return;
    setState(() {
      _working = true;
      _failure = '';
      _overall = 'بدأ فحص الموارد وتجهيزها. تظهر حالة كل مكوّن بصورة مستقلة.';
    });
    try {
      // Independent resources are prepared concurrently to avoid serial wait time.
      await Future.wait<void>(<Future<void>>[
        _prepareModel(),
        _prepareLinux(),
      ]);
      await _refreshStatus(silent: true);
      if (!_canEnter) throw StateError('لم تكتمل الجاهزية النهائية للنموذج وUbuntu.');
    } catch (error) {
      if (mounted) setState(() {
        _failure = error.toString();
        _overall = 'لم تكتمل التهيئة. عالج السبب الظاهر ثم أعد المحاولة.';
      });
    } finally {
      if (mounted) setState(() => _working = false);
      await _refreshStatus(silent: true);
    }
  }

  Future<void> _importModel() async {
    if (_working) return;
    setState(() { _working = true; _failure = ''; });
    var imported = false;
    try {
      imported = await _engineChannel.invokeMethod<bool>('importModel') == true;
      if (imported && mounted) setState(() => _overall = 'تم استيراد GGUF والتحقق منه؛ جارٍ تشغيله.');
    } on PlatformException catch (error) {
      if (mounted) setState(() => _failure = error.message ?? error.code);
    } catch (error) {
      if (mounted) setState(() => _failure = '$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
    if (imported && mounted) await _runSetup();
  }

  void _enter() {
    if (!_canEnter || _working) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const AppShell()),
    );
  }

  Widget _resourceCard({required String title, required String description,
      required String state, required double? progress, required String details,
      required IconData icon, required bool ready}) => NexusGlassPanel(
    padding: const EdgeInsets.all(15),
    radius: 18,
    borderColor: ready ? NexusPalette.success.withValues(alpha: 0.42) : NexusPalette.border,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        NexusIconTile(icon, size: 38),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w900, fontSize: 13)),
          Text(description, style: const TextStyle(color: NexusPalette.muted, fontSize: 10)),
        ])),
        Icon(ready ? Icons.check_circle_rounded : Icons.pending_rounded,
            color: ready ? NexusPalette.success : NexusPalette.warning),
      ]),
      const SizedBox(height: 12),
      Text(state, style: const TextStyle(color: NexusPalette.text, fontSize: 11, fontWeight: FontWeight.w700)),
      const SizedBox(height: 7),
      LinearProgressIndicator(value: ready ? 1 : progress, minHeight: 5),
      const SizedBox(height: 5),
      Text(details, style: const TextStyle(color: NexusPalette.muted, fontSize: 9)),
    ]),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: NexusPalette.background,
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: ListView(padding: const EdgeInsets.all(18), children: [
        const SizedBox(height: 18),
        const Center(child: NexusIconTile(Icons.hub_rounded, size: 64)),
        const SizedBox(height: 14),
        const Text('مرحبًا بك في Termi Ai Nexus', textAlign: TextAlign.center,
          style: TextStyle(color: NexusPalette.text, fontSize: 21, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        const Text('لإكمال الدخول للخدمة المجانية يجب عليك تثبيت بعض الأدوات لضمان عمل التطبيق بشكل ناجح وبدون أخطاء',
          textAlign: TextAlign.center, style: TextStyle(color: NexusPalette.muted, fontSize: 12, height: 1.7)),
        const SizedBox(height: 22),
        _resourceCard(title: 'نموذج Aram AI', description: 'تنزيل GGUF أو استخدام النموذج المستورد، ثم تحميله والتحقق من جاهزيته',
          state: _modelState, progress: _modelProgress, details: _modelBytes,
          icon: Icons.memory_rounded, ready: _modelReady),
        const SizedBox(height: 10),
        _resourceCard(title: 'Ubuntu وأدوات Linux', description: 'تنزيل النظام، فحصه، ثم إعداد Git وGitHub CLI وPython وأدوات البناء والشبكة',
          state: _linuxState, progress: _linuxProgress, details: _linuxBytes,
          icon: Icons.terminal_rounded, ready: _linuxReady),
        const SizedBox(height: 15),
        Text(_overall, textAlign: TextAlign.center, style: const TextStyle(color: NexusPalette.text, fontSize: 11)),
        if (_failure.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_failure, textAlign: TextAlign.center, style: const TextStyle(color: NexusPalette.danger, fontSize: 10)),
        ],
        const SizedBox(height: 15),
        FilledButton.icon(onPressed: _working || _canEnter ? null : _runSetup,
          icon: _working ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_rounded),
          label: Text(_working ? 'جارٍ تجهيز الأدوات والتحقق…' : 'تحميل الأدوات')),
        if (!_modelReady) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _working ? null : _importModel,
            icon: const Icon(Icons.folder_open_rounded), label: const Text('استيراد نموذج GGUF من الهاتف')),
        ],
        if (_canEnter) ...[
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: _enter, icon: const Icon(Icons.login_rounded),
            label: const Text('الدخول لـ Termi Ai nexus')),
        ],
        const SizedBox(height: 18),
        const Text('إذا كانت الموارد مثبتة وصالحة فلن يعاد تنزيلها لمجرد فتح التطبيق. يحتاج الاتصال بالإنترنت فقط عند غياب مورد مطلوب.',
          textAlign: TextAlign.center, style: TextStyle(color: NexusPalette.subtle, fontSize: 9, height: 1.6)),
      ]),
    ))),
  );
}
