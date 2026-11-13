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
  bool _busy = false;
  String _state = 'UNKNOWN';
  String _message = 'لم يتم جلب حالة المحرك بعد';
  String _apiBaseUrl = 'http://127.0.0.1:8766/v1';
  bool _loaded = false;
  bool _modelAvailable = false;
  int _queuedRequests = 0;
  int _updatedAt = 0;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshStatus(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  bool get _isReady => _loaded && _state == 'READY';
  bool get _isImporting => _state == 'IMPORTING_MODEL' || _state == 'LOADING_MODEL' || _state == 'STARTING' || _state == 'STARTING_SERVER' || _state == 'DOWNLOADING_MODEL';

  Color get _stateColor {
    if (_isReady) return NexusPalette.success;
    if (_isImporting || _state == 'DOWNLOADING_MODEL' || _state == 'STOPPING') return NexusPalette.warning;
    if (_state == 'ERROR') return NexusPalette.danger;
    return NexusPalette.muted;
  }

  String get _stateLabel => switch (_state) {
        'READY' => 'جاهز',
        'STOPPED' => 'متوقف',
        'STARTING' => 'قيد التشغيل',
        'DOWNLOADING_MODEL' => 'تنزيل النموذج',
        'IMPORTING_MODEL' => 'استيراد النموذج',
        'LOADING_MODEL' => 'تحميل النموذج',
        'STARTING_SERVER' => 'تشغيل خادم API',
        'STOPPING' => 'جارٍ الإيقاف',
        'ERROR' => 'خطأ',
        _ => 'غير معروف',
      };

  Future<void> _refreshStatus({bool silent = false}) async {
    if (_loading) return;
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final status = await _channel.invokeMapMethod<String, dynamic>('status');
      if (!mounted || status == null) return;
      setState(() {
        _state = status['state']?.toString() ?? 'UNKNOWN';
        _message = status['message']?.toString() ?? '';
        _loaded = status['loaded'] == true;
        _modelAvailable = status['modelAvailable'] == true;
        _queuedRequests = (status['queuedRequests'] as num?)?.toInt() ?? 0;
        _apiBaseUrl = status['apiBaseUrl']?.toString() ?? _apiBaseUrl;
        _updatedAt = (status['updatedAt'] as num?)?.toInt() ?? 0;
      });
    } catch (error) {
      if (mounted && !silent) _showMessage('تعذر قراءة حالة المحرك: $error');
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _runAction(String method) async {
    if (_busy) return;
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
    if (_busy || _isImporting) return;
    setState(() => _busy = true);
    try {
      final imported = await _channel.invokeMethod<bool>('importModel');
      if (imported == true && mounted) {
        _showMessage('تم استيراد نموذج GGUF والتحقق منه بنجاح');
      } else if (mounted) {
        _showMessage('تم إلغاء اختيار ملف النموذج');
      }
      await _refreshStatus(silent: true);
    } on PlatformException catch (error) {
      if (mounted) _showMessage(error.message ?? 'تعذر فتح منتقي الملفات');
    } catch (error) {
      if (mounted) _showMessage('فشل طلب الاستيراد: $error');
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

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _refreshStatus,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 5, 16, 25),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            NexusPageHeader(
              title: 'مركز محرك Aram AI',
              subtitle: 'إدارة النموذج المحلي وحالة الخدمة وواجهة API المدمجة.',
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
                  Text(_stateLabel, style: TextStyle(color: _stateColor, fontSize: 17, fontWeight: FontWeight.w900)),
                  const Spacer(),
                  NexusStatusPill(_modelAvailable ? 'ملف النموذج موجود' : 'ملف النموذج غير موجود', color: _modelAvailable ? NexusPalette.success : NexusPalette.muted),
                ]),
                const SizedBox(height: 9),
                Text(_message, style: const TextStyle(color: NexusPalette.muted, fontSize: 11, height: 1.5)),
                const Divider(height: 23),
                _statusRow('ملف GGUF في مساحة التطبيق', _modelAvailable ? 'موجود وصالح' : 'غير موجود أو غير صالح'),
                _statusRow('النموذج في الذاكرة', _loaded ? 'نعم' : 'لا'),
                _statusRow('طلبات الانتظار', '$_queuedRequests'),
                _statusRow('واجهة API المحلية', _apiBaseUrl),
              ]),
            ),
            _sectionCard(
              title: 'إدارة النموذج',
              icon: Icons.folder_open_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('يمكنك استيراد ملف GGUF موجود على الهاتف، أو تنزيل النموذج من المصدر المحدد في المحرك.', style: TextStyle(color: NexusPalette.muted, fontSize: 11, height: 1.5)),
                const SizedBox(height: 13),
                FilledButton.icon(onPressed: _busy || _isReady || _isImporting || _state == 'DOWNLOADING_MODEL' ? null : _importModel, icon: const Icon(Icons.file_upload_outlined), label: const Text('استيراد نموذج GGUF من الهاتف')),
                const SizedBox(height: 9),
                OutlinedButton.icon(onPressed: _busy || _isReady || _modelAvailable ? null : () => _runAction('downloadModel'), icon: const Icon(Icons.download_rounded), label: const Text('تنزيل النموذج من المصدر')),
              ]),
            ),
            _sectionCard(
              title: 'التحكم بالمحرك',
              icon: Icons.settings_suggest_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilledButton.icon(onPressed: _busy || _isReady || _isImporting ? null : () => _runAction('start'), icon: const Icon(Icons.play_arrow_rounded), label: const Text('تشغيل المحرك')),
                const SizedBox(height: 9),
                OutlinedButton.icon(onPressed: _busy || (_state == 'STOPPED' && !_loaded) ? null : () => _runAction('stop', successMessage: 'تم إرسال طلب إيقاف المحرك'), icon: const Icon(Icons.stop_rounded), label: const Text('إيقاف المحرك')),
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
                const Text('هذا العنوان يعمل محليًا على الهاتف، ولا يعني أن الخدمة متاحة للأجهزة الأخرى عبر الشبكة.', style: TextStyle(color: NexusPalette.subtle, fontSize: 10, height: 1.5)),
              ]),
            ),
            if (_busy || _isImporting)
              const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Column(children: [LinearProgressIndicator(), SizedBox(height: 8), Text('يجري تنفيذ العملية ومراقبة حالة المحرك…', style: TextStyle(color: NexusPalette.muted, fontSize: 10))])),
            if (_updatedAt > 0)
              Padding(padding: const EdgeInsets.only(top: 3, bottom: 10), child: Text('آخر تحديث للحالة: $_updatedAt', textAlign: TextAlign.center, style: const TextStyle(color: NexusPalette.subtle, fontSize: 9))),
          ],
        ),
      );
}
