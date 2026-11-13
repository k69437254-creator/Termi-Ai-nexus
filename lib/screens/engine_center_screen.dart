import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../core/nexus_theme.dart';

class EngineCenterScreen extends StatefulWidget {
  const EngineCenterScreen({super.key});

  @override
  State<EngineCenterScreen> createState() => _EngineCenterScreenState();
}

class _EngineCenterScreenState extends State<EngineCenterScreen> {
  static const MethodChannel _channel = MethodChannel('termai/aram-engine');
  Timer? _pollTimer;
  bool _loading = false;
  bool _refreshing = false;
  bool _busy = false;
  bool _autoStartAfterDownload = false;
  String _state = 'UNKNOWN';
  String _message = 'لم يتم جلب حالة المحرك بعد';
  String _apiBaseUrl = 'http://127.0.0.1:8766/v1';
  bool _loaded = false;
  bool _modelAvailable = false;
  int _modelSizeBytes = 0;
  int _queuedRequests = 0;
  int _updatedAt = 0;
  String _transferOperation = '';
  String _transferStage = '';
  int _transferBytes = 0;
  int _transferTotalBytes = -1;
  double _transferSpeed = 0;
  bool _transferPaused = false;
  DateTime? _lastProgressAt;
  int _lastProgressBytes = 0;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _refreshStatus(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  bool get _isReady => _loaded && _state == 'READY';
  bool get _isImporting => _state == 'IMPORTING_MODEL';
  bool get _isDownloading => _state == 'DOWNLOADING_MODEL';
  bool get _isStarting => _state == 'STARTING' || _state == 'LOADING_MODEL' || _state == 'STARTING_SERVER';
  bool get _showProgress => _busy || _isImporting || _isDownloading || _isStarting || _state == 'STOPPING';

  double? get _transferPercent {
    if (_transferOperation.isEmpty || _transferTotalBytes <= 0) return null;
    return (_transferBytes / _transferTotalBytes).clamp(0.0, 1.0).toDouble();
  }

  int? get _etaSeconds {
    if (_transferTotalBytes <= 0 || _transferSpeed < 1 || _transferBytes >= _transferTotalBytes) return null;
    return ((_transferTotalBytes - _transferBytes) / _transferSpeed).ceil();
  }

  Color get _stateColor {
    if (_isReady) return NexusPalette.success;
    if (_isImporting || _isDownloading || _isStarting || _state == 'STOPPING') return NexusPalette.warning;
    if (_state == 'ERROR') return NexusPalette.danger;
    return NexusPalette.muted;
  }

  String get _stateLabel => switch (_state) {
        'READY' => _loaded ? 'جاهز ويعمل' : 'الملف موجود · يحتاج تشغيل',
        'STOPPED' => 'متوقف',
        'STARTING' => 'تهيئة المحرك',
        'DOWNLOADING_MODEL' => _transferPaused ? 'التنزيل متوقف مؤقتًا' : 'تنزيل النموذج',
        'IMPORTING_MODEL' => 'استيراد النموذج',
        'LOADING_MODEL' => 'تحميل النموذج في الذاكرة',
        'STARTING_SERVER' => 'تشغيل واجهة API',
        'STOPPING' => 'جارٍ الإيقاف',
        'ERROR' => 'تعذر إكمال العملية',
        _ => 'غير معروف',
      };

  Future<void> _refreshStatus({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final status = await _channel.invokeMapMethod<String, dynamic>('status');
      if (!mounted || status == null) return;

      final operation = status['transferOperation']?.toString() ?? '';
      final bytes = (status['transferBytes'] as num?)?.toInt() ?? 0;
      final total = (status['transferTotalBytes'] as num?)?.toInt() ?? -1;
      final paused = status['transferPaused'] == true;
      final statusState = status['state']?.toString() ?? 'UNKNOWN';
      final statusMessage = status['message']?.toString() ?? '';
      final statusModelAvailable = status['modelAvailable'] == true;
      final now = DateTime.now();
      var speed = _transferSpeed;

      if (operation != _transferOperation || bytes < _lastProgressBytes) {
        speed = 0;
        _lastProgressAt = now;
        _lastProgressBytes = bytes;
      } else if (bytes > _lastProgressBytes) {
        final elapsedMs = _lastProgressAt == null ? 0 : now.difference(_lastProgressAt!).inMilliseconds;
        if (elapsedMs > 0) {
          final instantSpeed = (bytes - _lastProgressBytes) * 1000 / elapsedMs;
          speed = speed <= 0 ? instantSpeed : (speed * 0.6) + (instantSpeed * 0.4);
        }
        _lastProgressAt = now;
        _lastProgressBytes = bytes;
      } else if (_lastProgressAt != null && now.difference(_lastProgressAt!).inSeconds >= 8) {
        speed = 0;
      }
      if (paused || operation.isEmpty) speed = 0;

      setState(() {
        _state = statusState;
        _message = statusMessage;
        _loaded = status['loaded'] == true;
        _modelAvailable = statusModelAvailable;
        _modelSizeBytes = (status['modelSizeBytes'] as num?)?.toInt() ?? 0;
        _queuedRequests = (status['queuedRequests'] as num?)?.toInt() ?? 0;
        _apiBaseUrl = status['apiBaseUrl']?.toString() ?? _apiBaseUrl;
        _updatedAt = (status['updatedAt'] as num?)?.toInt() ?? 0;
        _transferOperation = operation;
        _transferStage = status['transferStage']?.toString() ?? '';
        _transferBytes = bytes;
        _transferTotalBytes = total;
        _transferPaused = paused;
        _transferSpeed = speed;
      });
      if (statusState == 'DOWNLOADING_MODEL') _autoStartAfterDownload = false;
      if (statusState == 'STOPPED' &&
          statusModelAvailable &&
          statusMessage.contains('اكتمل تنزيل النموذج والتحقق من ملف GGUF') &&
          !_autoStartAfterDownload) {
        _autoStartAfterDownload = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_busy) {
            _autoStartAfterDownload = false;
            return;
          }
          _runAction('start');
        });
      }
    } catch (error) {
      if (mounted && !silent) _showMessage('تعذر قراءة حالة المحرك: $error');
    } finally {
      _refreshing = false;
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _runAction(String method) async {
    if (_busy) return;
    if (method == 'downloadModel') _autoStartAfterDownload = false;
    setState(() => _busy = true);
    try {
      await _channel.invokeMethod<bool>(method);
      await _refreshStatus(silent: true);
    } on PlatformException catch (error) {
      if (mounted) _showMessage(error.message ?? 'تعذر تنفيذ العملية');
    } catch (error) {
      if (mounted) _showMessage('حدث خطأ: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importModel() async {
    if (_busy || _isReady || _isImporting || _isDownloading || _isStarting) return;
    setState(() => _busy = true);
    try {
      final imported = await _channel.invokeMethod<bool>('importModel');
      if (imported == true) {
        if (mounted) _showMessage('تم استيراد ملف GGUF والتحقق منه. بدأ تشغيل النموذج الآن.');
        await _channel.invokeMethod<bool>('start');
      } else if (mounted) {
        _showMessage('تم إلغاء اختيار ملف النموذج.');
      }
      await _refreshStatus(silent: true);
    } on PlatformException catch (error) {
      if (mounted) _showMessage(error.message ?? 'تعذر فتح منتقي الملفات');
    } catch (error) {
      if (mounted) _showMessage('فشل استيراد أو تشغيل النموذج: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelDownload() async {
    if (_busy || !_isDownloading) return;
    setState(() => _busy = true);
    try {
      final cancelled = await _channel.invokeMethod<bool>('cancelDownload');
      if (mounted) {
        _showMessage(cancelled == true ? 'تم إلغاء التنزيل وحذف مهمة Download Manager.' : 'لم يتمكن Android من العثور على مهمة التنزيل.');
      }
      await _refreshStatus(silent: true);
    } on PlatformException catch (error) {
      if (mounted) _showMessage(error.message ?? 'تعذر إلغاء التنزيل');
    } catch (error) {
      if (mounted) _showMessage('حدث خطأ أثناء إلغاء التنزيل: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  String _formatBytes(num bytes) {
    if (bytes < 0) return 'غير محدد';
    if (bytes < 1024) return '${bytes.toInt()} B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = -1;
    do {
      value /= 1024;
      unit++;
    } while (value >= 1024 && unit < units.length - 1);
    return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '$seconds ث';
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    if (minutes < 60) return '$minutes د $remainingSeconds ث';
    final hours = minutes ~/ 60;
    return '$hours س ${minutes % 60} د';
  }

  String get _progressTitle {
    if (_state == 'DOWNLOADING_MODEL') {
      if (_transferPaused) return 'التنزيل متوقف مؤقتًا بانتظار الشبكة';
      if (_transferStage == 'VERIFYING') return 'اكتمل نقل الملف · جارٍ التحقق منه';
      return 'تنزيل Spark-X2.6-1.7B إلى مساحة التطبيق';
    }
    if (_state == 'IMPORTING_MODEL') {
      return _transferStage == 'VERIFYING' ? 'فحص سلامة ملف GGUF' : 'نسخ النموذج من الهاتف إلى مساحة التطبيق';
    }
    if (_state == 'LOADING_MODEL') return 'تحميل أوزان النموذج في ذاكرة الجهاز';
    if (_state == 'STARTING_SERVER') return 'تشغيل خدمة Aram AI وواجهة API المحلية';
    if (_state == 'STARTING') return 'تهيئة محرك الاستدلال المحلي';
    if (_state == 'STOPPING') return 'إيقاف المحرك وتحرير الذاكرة';
    return 'بدء عملية تجهيز النموذج';
  }

  Widget _sectionCard({required String title, required IconData icon, required Widget child}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: NexusGlassPanel(
          padding: const EdgeInsets.all(15),
          radius: 21,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [NexusIconTile(icon, size: 39), const SizedBox(width: 10), Text(title, style: const TextStyle(color: NexusPalette.text, fontSize: 13, fontWeight: FontWeight.w900))]),
            const SizedBox(height: 14),
            child,
          ]),
        ),
      );

  Widget _statusRow(String title, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Expanded(child: Text(title, style: const TextStyle(color: NexusPalette.muted, fontSize: 11))),
          Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(color: NexusPalette.text, fontSize: 11, fontWeight: FontWeight.w800))),
        ]),
      );

  Widget _progressCard() {
    final ratio = _transferPercent;
    final hasTransfer = _transferOperation.isNotEmpty;
    final eta = _etaSeconds;
    return _sectionCard(
      title: 'متابعة تجهيز النموذج',
      icon: Icons.downloading_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(_progressTitle, style: const TextStyle(color: NexusPalette.text, fontSize: 12, fontWeight: FontWeight.w800))),
          if (ratio != null)
            Text('${(ratio * 100).round()}%', style: const TextStyle(color: NexusPalette.primaryLight, fontSize: 13, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LinearProgressIndicator(value: ratio, minHeight: 8, backgroundColor: Colors.white.withValues(alpha: 0.07)),
        ),
        const SizedBox(height: 12),
        if (hasTransfer) ...[
          _statusRow('المنقول', _formatBytes(_transferBytes)),
          _statusRow('الحجم الإجمالي', _transferTotalBytes > 0 ? _formatBytes(_transferTotalBytes) : 'يحدده مصدر الملف'),
          _statusRow('السرعة', _transferPaused ? 'متوقف مؤقتًا' : '${_formatBytes(_transferSpeed.round())}/ث'),
          _statusRow('الوقت المتبقي', eta == null ? 'جارٍ حسابه من سرعة النقل' : _formatDuration(eta)),
        ],
        if (_state == 'LOADING_MODEL')
          const Text('يجري تجهيز أوزان النموذج داخل ذاكرة الجهاز. محرك JNI لا يوفّر نسبة تحميل موثوقة لهذه المرحلة، لذلك نعرض المرحلة الفعلية دون رقم تقديري مضلل.', style: TextStyle(color: NexusPalette.muted, fontSize: 10, height: 1.5)),
        if (_state == 'STARTING_SERVER')
          const Text('تم تحميل النموذج؛ يجري تشغيل خدمة API المدمجة حتى يستطيع المساعد الذكي استخدامها مباشرة.', style: TextStyle(color: NexusPalette.muted, fontSize: 10, height: 1.5)),
        if (_state == 'DOWNLOADING_MODEL') ...[
          const Text('يستمر Android في إدارة التنزيل حتى عند الانتقال إلى شاشة أخرى. بعد اكتماله وفحص GGUF يبدأ المحرك عند فتح هذه الشاشة. قد يتجاوز حجم النموذج 1 GB؛ راقب استهلاك بيانات الهاتف.', style: TextStyle(color: NexusPalette.muted, fontSize: 10, height: 1.5)),
          if (_transferPaused)
            const Padding(padding: EdgeInsets.only(top: 8), child: Text('التنزيل متوقف من مدير تنزيلات Android. تحقق من اتصال الشبكة أو قيود النظام ثم أعد المحاولة.', style: TextStyle(color: NexusPalette.warning, fontSize: 10, height: 1.5))),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: _busy ? null : _cancelDownload, icon: const Icon(Icons.close_rounded), label: const Text('إلغاء التنزيل')),
        ],
        if (_state == 'IMPORTING_MODEL')
          const Text('يتم نسخ الملف مباشرة إلى مساحة التطبيق الخاصة، ثم فحص ترويسة GGUF وحجمه قبل اعتماده.', style: TextStyle(color: NexusPalette.muted, fontSize: 10, height: 1.5)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _refreshStatus,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 5, 16, 25),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            NexusPageHeader(
              title: 'مركز محرك Aram AI',
              subtitle: 'تنزيل النموذج واستيراده وتشغيله ومتابعة كل مرحلة داخل التطبيق.',
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 18),
              trailing: IconButton(tooltip: 'تحديث الحالة', onPressed: _loading ? null : () => _refreshStatus(), icon: const Icon(Icons.refresh_rounded)),
            ),
            _sectionCard(
              title: 'حالة المحرك',
              icon: Icons.memory_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: _stateColor, shape: BoxShape.circle, boxShadow: [BoxShadow(color: _stateColor.withValues(alpha: 0.45), blurRadius: 10)])),
                  const SizedBox(width: 9),
                  Text(_stateLabel, style: TextStyle(color: _stateColor, fontSize: 16, fontWeight: FontWeight.w900)),
                  const Spacer(),
                  NexusStatusPill(_modelAvailable ? 'GGUF صالح' : 'لا يوجد نموذج صالح', color: _modelAvailable ? NexusPalette.success : NexusPalette.muted),
                ]),
                const SizedBox(height: 9),
                Text(_message, style: const TextStyle(color: NexusPalette.muted, fontSize: 11, height: 1.5)),
                const Divider(height: 23),
                _statusRow('ملف GGUF في مساحة التطبيق', _modelAvailable ? 'موجود وصالح' : 'غير موجود أو غير صالح'),
                _statusRow('حجم الملف المعتمد', _formatBytes(_modelSizeBytes)),
                _statusRow('النموذج محمّل في الذاكرة', _loaded ? 'نعم' : 'لا'),
                _statusRow('طلبات الانتظار', '$_queuedRequests'),
                _statusRow('واجهة API المحلية', _apiBaseUrl),
              ]),
            ),
            _sectionCard(
              title: 'إدارة النموذج',
              icon: Icons.folder_open_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('استخدم ملف GGUF موجودًا على الهاتف أو نزّل نسخة Spark-X2.6-1.7B مباشرة إلى مساحة TermiAI-Nexus. بعد الاستيراد يبدأ تشغيل المحرك تلقائيًا.', style: TextStyle(color: NexusPalette.muted, fontSize: 11, height: 1.5)),
                const SizedBox(height: 13),
                FilledButton.icon(
                  onPressed: _busy || _isReady || _isImporting || _isDownloading || _isStarting ? null : _importModel,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('استيراد نموذج GGUF من الهاتف'),
                ),
                const SizedBox(height: 9),
                OutlinedButton.icon(
                  onPressed: _busy || _modelAvailable || _isDownloading || _isImporting || _isStarting ? null : () => _runAction('downloadModel'),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('تنزيل Spark-X2.6-1.7B'),
                ),
              ]),
            ),
            if (_showProgress) _progressCard(),
            _sectionCard(
              title: 'التحكم بالمحرك',
              icon: Icons.settings_suggest_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilledButton.icon(
                  onPressed: _busy || !_modelAvailable || _isReady || _isImporting || _isDownloading || _isStarting ? null : () => _runAction('start'),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('تشغيل النموذج والمحرك'),
                ),
                const SizedBox(height: 9),
                OutlinedButton.icon(
                  onPressed: _busy || _isDownloading || _isImporting || (_state == 'STOPPED' && !_loaded) ? null : () => _runAction('stop'),
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('إيقاف المحرك'),
                ),
              ]),
            ),
            _sectionCard(
              title: 'الربط مع المساعد الذكي',
              icon: Icons.hub_rounded,
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('عندما يكون عنوان بوابة API فارغًا في الإعدادات، يرسل المساعد الطلبات مباشرة إلى محرك Aram AI المضمّن داخل عملية التطبيق، ولا يحتاج إلى تشغيل تطبيق Aram AI منفصل.', style: TextStyle(color: NexusPalette.muted, fontSize: 11, height: 1.55)),
                SizedBox(height: 8),
                Text('لا يصبح المساعد جاهزًا حتى تظهر حالة «جاهز ويعمل» بعد تحميل النموذج وتشغيل واجهة API.', style: TextStyle(color: NexusPalette.primaryLight, fontSize: 10, height: 1.5, fontWeight: FontWeight.w700)),
              ]),
            ),
            _sectionCard(
              title: 'معلومات الاتصال',
              icon: Icons.lan_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('عنوان API المحلي', style: TextStyle(color: NexusPalette.muted, fontSize: 10)),
                const SizedBox(height: 7),
                SelectableText(_apiBaseUrl, textDirection: TextDirection.ltr, style: const TextStyle(color: NexusPalette.primaryLight, fontWeight: FontWeight.w900, fontSize: 12)),
                const SizedBox(height: 9),
                const Text('يستمع الخادم محليًا على الهاتف فقط؛ لا يعني ذلك أن الخدمة متاحة للأجهزة الأخرى عبر الشبكة.', style: TextStyle(color: NexusPalette.subtle, fontSize: 10, height: 1.5)),
              ]),
            ),
            if (_updatedAt > 0)
              Padding(
                padding: const EdgeInsets.only(top: 3, bottom: 10),
                child: Text('آخر تحديث للحالة: ${DateTime.fromMillisecondsSinceEpoch(_updatedAt).toLocal().toString().substring(11, 19)}', textAlign: TextAlign.center, style: const TextStyle(color: NexusPalette.subtle, fontSize: 9)),
              ),
          ],
        ),
      );
}
