
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EngineCenterScreen extends StatefulWidget {
  const EngineCenterScreen({super.key});

  @override
  State<EngineCenterScreen> createState() => _EngineCenterScreenState();
}

class _EngineCenterScreenState extends State<EngineCenterScreen> {
  static const MethodChannel _channel =
      MethodChannel('termai/aram-engine');

  Timer? _pollTimer;

  bool _loading = false;
  bool _busy = false;

  String _state = 'UNKNOWN';
  String _message = 'لم يتم جلب حالة المحرك بعد';
  String _apiBaseUrl = 'http://127.0.0.1:8766/v1';

  bool _loaded = false;
  int _queuedRequests = 0;
  int _updatedAt = 0;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshStatus(silent: true),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  bool get _isReady => _loaded && _state == 'READY';

  bool get _isImporting =>
      _state == 'IMPORTING_MODEL' ||
      _state == 'LOADING_MODEL' ||
      _state == 'STARTING' ||
      _state == 'STARTING_SERVER';

  Color get _stateColor {
    if (_isReady) return Colors.green;
    if (_isImporting ||
        _state == 'DOWNLOADING_MODEL' ||
        _state == 'STOPPING') {
      return Colors.orange;
    }
    if (_state == 'ERROR') return Colors.red;
    return Colors.blueGrey;
  }

  String get _stateLabel {
    switch (_state) {
      case 'READY':
        return 'جاهز';
      case 'STOPPED':
        return 'متوقف';
      case 'STARTING':
        return 'قيد التشغيل';
      case 'DOWNLOADING_MODEL':
        return 'تنزيل النموذج';
      case 'IMPORTING_MODEL':
        return 'استيراد النموذج';
      case 'LOADING_MODEL':
        return 'تحميل النموذج';
      case 'STARTING_SERVER':
        return 'تشغيل خادم API';
      case 'STOPPING':
        return 'جارٍ الإيقاف';
      case 'ERROR':
        return 'خطأ';
      default:
        return 'غير معروف';
    }
  }

  Future<void> _refreshStatus({bool silent = false}) async {
    if (_loading) return;

    if (!silent && mounted) {
      setState(() => _loading = true);
    }

    try {
      final status =
          await _channel.invokeMapMethod<String, dynamic>('status');

      if (!mounted || status == null) return;

      setState(() {
        _state = status['state']?.toString() ?? 'UNKNOWN';
        _message = status['message']?.toString() ?? '';
        _loaded = status['loaded'] == true;
        _queuedRequests =
            (status['queuedRequests'] as num?)?.toInt() ?? 0;
        _apiBaseUrl =
            status['apiBaseUrl']?.toString() ?? _apiBaseUrl;
        _updatedAt =
            (status['updatedAt'] as num?)?.toInt() ?? 0;
      });
    } catch (error) {
      if (mounted && !silent) {
        _showMessage('تعذر قراءة حالة المحرك: $error');
      }
    } finally {
      if (mounted && !silent) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _runAction(
    String method, {
    String? successMessage,
  }) async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      await _channel.invokeMethod<bool>(method);

      if (successMessage != null && mounted) {
        _showMessage(successMessage);
      }

      await _refreshStatus(silent: true);
    } on PlatformException catch (error) {
      if (mounted) {
        _showMessage(error.message ?? 'تعذر تنفيذ العملية');
      }
    } catch (error) {
      if (mounted) {
        _showMessage('حدث خطأ: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importModel() async {
    if (_busy || _isImporting) return;

    setState(() => _busy = true);

    try {
      await _channel.invokeMethod<bool>('importModel');
      if (mounted) {
        _showMessage('تم إرسال طلب اختيار ملف النموذج');
      }
      await _refreshStatus(silent: true);
    } on PlatformException catch (error) {
      if (mounted) {
        _showMessage(error.message ?? 'تعذر فتح منتقي الملفات');
      }
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
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _statusRow(String title, String value, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (trailing != null) trailing,
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: RefreshIndicator(
        onRefresh: _refreshStatus,
        child: ListView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _sectionCard(
              title: 'حالة محرك Aram AI',
              icon: Icons.memory_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: _stateColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Text(
                        _stateLabel,
                        style: TextStyle(
                          color: _stateColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'تحديث الحالة',
                        onPressed: _loading
                            ? null
                            : () => _refreshStatus(),
                        icon: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _message,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const Divider(height: 26),
                  _statusRow(
                    'النموذج في الذاكرة',
                    _loaded ? 'نعم' : 'لا',
                  ),
                  _statusRow(
                    'طلبات الانتظار',
                    '$_queuedRequests',
                  ),
                  _statusRow(
                    'واجهة API',
                    _apiBaseUrl,
                  ),
                ],
              ),
            ),

            _sectionCard(
              title: 'إدارة النموذج',
              icon: Icons.folder_open_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'استورد نموذج GGUF  موجودًا  على  هاتفك  بدل  تنزيل  نسخة
أخرى. '
                     'اختر  الملف  من  مدير  الملفات  وانتظر  انتهاء  التحقق
والتحميل.',
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _busy || _isImporting
                        ? null
                        : _importModel,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('استيراد نموذج GGUF'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy || _isReady
                        ? null
                        : () => _runAction(
                              'downloadModel',
                              successMessage: 'تم إرسال طلب تشغيل المحرك',
                            ),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('تشغيل المحرك / تنزيل النموذج'),
                  ),
                ],
              ),
            ),

            _sectionCard(
              title: 'التحكم بالمحرك',
              icon: Icons.settings_suggest_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _busy || _isReady || _isImporting
                        ? null
                        : () => _runAction(
                              'start',
                              successMessage: 'تم إرسال طلب تشغيل المحرك',
                            ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('تشغيل المحرك'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ||
                            (_state == 'STOPPED' && !_loaded)
                        ? null
                        : () => _runAction(
                              'stop',
                              successMessage: 'تم إرسال طلب إيقاف المحرك',
                            ),
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('إيقاف المحرك'),
                  ),
                ],
              ),
            ),

            _sectionCard(
              title: 'معلومات الاتصال',
              icon: Icons.lan_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('عنوان API المحلي'),
                  const SizedBox(height: 8),
                  SelectableText(
                    _apiBaseUrl,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'هذا العنوان محلي على الهاتف، ولا يعني أن الخدمة متاحة\n'
                    'للأجهزة الأخرى عبر الشبكة.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),

            if (_busy || _isImporting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    LinearProgressIndicator(),
                    SizedBox(height: 8),
                    Text('يجري تنفيذ العملية ومراقبة حالة المحرك...'),
                  ],
                ),
              ),

            if (_updatedAt > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 18),
                child: Text(
                  'آخر تحديث للحالة: $_updatedAt',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
