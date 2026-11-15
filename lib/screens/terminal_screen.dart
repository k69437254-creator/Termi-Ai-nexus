import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/approval_policy.dart';
import '../core/linux_runtime_service.dart';
import '../core/nexus_theme.dart';
import '../core/pty_service.dart';
import '../core/secure_vault.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final PtyService _pty = PtyService();
  final LinuxRuntimeService _linux = LinuxRuntimeService();
  final SecureVault _vault = SecureVault.instance;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final StringBuffer _output = StringBuffer();
  StreamSubscription<Map<String, dynamic>>? _subscription;
  StreamSubscription<Map<String, dynamic>>? _installProgressSubscription;
  bool _installPromptOpen = false;
  String _installStage = '';
  String _installStageMessage = '';
  int? _downloadedBytes;
  int? _totalBytes;
  double? _downloadProgress;
  bool _running = false;
  bool _busy = false;
  bool _linuxInstalled = false;
  bool _installingLinux = false;
  String _status = 'الجلسة غير مشغّلة';

  @override
  void initState() {
    super.initState();
    unawaited(_refreshLinux());
    _subscription = _pty.events.listen(
      _onEvent,
      onError: (Object error) {
        if (mounted) setState(() => _status = 'خطأ في أحداث PTY: $error');
      },
    );
  }

  void _onEvent(Map<String, dynamic> event) {
    final data = event['data']?.toString() ?? '';
    if (data.isEmpty || !mounted) return;
    setState(() {
      _output.write(data);
      if (data.contains('[PTY session closed]')) {
        _running = false;
        _status = 'أُغلقت جلسة PTY';
      }
      if (_output.length > 80000) {
        final trimmed = _output.toString().substring(_output.length - 60000);
        _output.clear();
        _output.write(trimmed);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _refreshLinux() async {
    try {
      final installed = await _linux.isInstalled();
      if (!mounted) return;
      setState(() {
        _linuxInstalled = installed;
        _status = installed
            ? 'Ubuntu 24.04.5 LTS • ARM64 • PRoot جاهز'
            : 'Ubuntu غير مثبت — جهّز بيئة Linux داخل التطبيق';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'تعذر فحص Linux: $error');
    }
  }

  Future<void> _installLinux() async {
    if (_installPromptOpen || _installingLinux || _busy || _linuxInstalled) {
      return;
    }

    _installPromptOpen = true;
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تهيئة Ubuntu Linux'),
          content: const Text(
            'سيُنزل التطبيق نظام Ubuntu 24.04.5 ARM64 من خوادم Canonical الرسمية، ثم يتحقق من SHA-256 ويثبت Git وGitHub CLI وأدوات التطوير داخل مساحة التطبيق الخاصة.\n\n'
            'تحتاج العملية اتصالاً بالإنترنت ومساحة تخزين فارغة لا تقل عن 1.2 GB. لا تحتاج إلى root أو تثبيت Termux خارجي.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('متابعة التهيئة'),
            ),
          ],
        ),
      );

      if (accepted != true || !mounted) return;

      setState(() {
        _installingLinux = true;
        _installStage = 'prepare';
        _installStageMessage = 'جارٍ بدء تهيئة Ubuntu…';
        _downloadedBytes = null;
        _totalBytes = null;
        _downloadProgress = null;
        _status = _installStageMessage;
      });

      await _installProgressSubscription?.cancel();
      _installProgressSubscription = _linux.installEvents.listen(
        (event) {
          if (!mounted) return;
          final stage = event['stage']?.toString() ?? '';
          final message = event['message']?.toString() ?? '';
          final downloaded = event['downloadedBytes'];
          final total = event['totalBytes'];
          final percent = event['percent'];

          setState(() {
            _installStage = stage;
            if (message.isNotEmpty) {
              _installStageMessage = message;
              _status = message;
            }
            if (downloaded is num) _downloadedBytes = downloaded.toInt();
            if (total is num) _totalBytes = total.toInt();
            _downloadProgress = stage == 'download' && percent is num
                ? (percent.toDouble() / 100.0).clamp(0.0, 1.0).toDouble()
                : null;
          });
        },
        onError: (Object error) {
          if (mounted) {
            setState(() {
              _installStageMessage = 'تعذر استقبال تقدم التهيئة: $error';
            });
          }
        },
      );

      final result = await _linux.install();
      if (!mounted) return;

      setState(() {
        _linuxInstalled = result['installed'] == true;
        _installStage = _linuxInstalled ? 'complete' : 'error';
        _installStageMessage = _linuxInstalled
            ? 'اكتملت تهيئة Ubuntu بنجاح.'
            : 'لم يكتمل تثبيت Ubuntu.';
        _status = _linuxInstalled
            ? 'Ubuntu 24.04.5 LTS جاهز — Git وGitHub CLI مثبتان'
            : 'لم يكتمل تثبيت Ubuntu.';
        if (_linuxInstalled) {
          _output.write('\n[PASS] Ubuntu 24.04.5 LTS installed and verified.\n');
          _output.write('[PASS] git and gh are available inside the Linux guest.\n');
        }
      });
    } catch (error, stackTrace) {
      if (mounted) {
        final busyError =
            error is PlatformException && error.code == 'LINUX_INSTALL_BUSY';
        setState(() {
          _status = busyError
              ? 'هناك عملية تهيئة Ubuntu قيد التشغيل بالفعل؛ انتظر انتهائها.'
              : 'فشل تهيئة Ubuntu؛ راجع سجل الطرفية للتفاصيل';
          _installStage = 'error';
          _installStageMessage = _status;
          _output
            ..write('\n[LINUX INSTALL FAILED]\n')
            ..write('$error\n')
            ..write('$stackTrace\n');
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }
    } finally {
      _installPromptOpen = false;
      await _installProgressSubscription?.cancel();
      _installProgressSubscription = null;
      if (mounted) setState(() => _installingLinux = false);
    }
  }

  String _formatInstallBytes(int bytes) {
    const mb = 1024 * 1024;
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  Future<void> _start() async {
    if (!_linuxInstalled) {
      setState(() => _status = 'يجب تهيئة Ubuntu قبل تشغيل الطرفية.');
      return;
    }
    setState(() { _busy = true; _status = 'جارٍ فتح جلسة Ubuntu PTY…'; });
    try {
      final githubToken = await _vault.read('github.token');
      final documents = await getApplicationDocumentsDirectory();
      final workspacePath = p.join(documents.path, 'TermiAI-Nexus', 'workspaces');
      await Directory(workspacePath).create(recursive: true);
      await _pty.start(rows: 30, columns: 100, workspacePath: workspacePath, githubToken: githubToken);
      if (mounted) setState(() { _running = true; _status = 'Ubuntu 24.04.5 LTS • Bash • Git • GitHub CLI'; });
    } catch (error) {
      if (mounted) setState(() => _status = 'تعذر تشغيل PTY: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final command = _input.text;
    if (command.trim().isEmpty || !_running) return;
    final decision = ApprovalPolicy.inspectCommand(command);
    if (decision.requiresApproval) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('موافقة مطلوبة'),
          content: Text('${decision.reason}\n\n$command', textDirection: TextDirection.ltr),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('أوافق على تشغيل الأمر')),
          ],
        ),
      );
      if (approved != true) return;
    }
    _input.clear();
    try {
      await _pty.write('$command\n');
    } catch (error) {
      if (mounted) setState(() => _status = 'فشل إرسال الأمر: $error');
    }
  }

  Future<void> _close() async {
    try { await _pty.close(); } catch (_) {}
    if (mounted) setState(() { _running = false; _status = 'أُغلقت الجلسة'; });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _installProgressSubscription?.cancel();
    _input.dispose();
    _scroll.dispose();
    _pty.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF00F0FF);
    const panel = Color(0xE609101D);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF050811),
            Color(0xFF0B1220),
            Color(0xFF050811),
          ],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 5),
            child: Row(
              children: [
                const Icon(Icons.blur_on_rounded,
                    color: cyan, size: 17),
                const SizedBox(width: 7),
                const Text(
                  'AETHERIUM',
                  style: TextStyle(
                    color: cyan,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0x2210B981),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0x5510B981)),
                  ),
                  child: Text(
                    _running ? 'PTY ONLINE' : 'SYSTEM STANDBY',
                    style: const TextStyle(
                      color: Color(0xFF10B981),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                _status,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF8296A8),
                  fontSize: 9,
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(
                    color: const Color(0x553B5268),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x3300F0FF),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 11),
                      child: Row(
                        children: [
                          const Icon(Icons.terminal,
                              color: cyan, size: 16),
                          const SizedBox(width: 8),
                          const Text(
                            'TERMINAL',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _linuxInstalled ? 'UBUNTU ARM64' : 'NOT INSTALLED',
                            style: TextStyle(
                              color: _linuxInstalled
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFF59E0B),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(
                      height: 1,
                      color: Color(0x333B5268),
                    ),
                    Expanded(
                      child: SelectionArea(
                        child: SingleChildScrollView(
                          controller: _scroll,
                          padding: const EdgeInsets.all(14),
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Text(
                              _output.isEmpty
                                  ? 'AETHERIUM // LINUX ENVIRONMENT\n'
                                    '━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
                                    'Ubuntu ARM64 Terminal\n\n'
                                    'البيئة جاهزة لبدء جلسة العمل.\n'
                                    'ابدأ بتهيئة Ubuntu، ثم شغّل الطرفية.\n'
                                    'يُستخدم رمز GitHub المحفوظ في التخزين الآمن لهذه الجلسة فقط.\n'
                                    'ولا يُكتب الرمز داخل ملفات Linux.\n\n'
                                  : _output.toString(),
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                fontFamily: 'JetBrainsMono',
                                color: Color(0xFFB9D5DF),
                                fontSize: 11.5,
                                height: 1.6,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_installingLinux || _busy)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LinearProgressIndicator(
                            value: _installingLinux && _installStage == 'download'
                                ? _downloadProgress
                                : null,
                            minHeight: 2,
                            color: const Color(0xFF00F0FF),
                            backgroundColor: const Color(0x2238BDF8),
                          ),
                          if (_installingLinux) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 7, 12, 4),
                              child: Text(
                                _installStageMessage.isEmpty
                                    ? 'جارٍ تهيئة Ubuntu…'
                                    : _installStageMessage,
                                style: const TextStyle(
                                  color: Color(0xFF9BC9D8),
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            if (_installStage == 'download' &&
                                _downloadedBytes != null &&
                                _totalBytes != null &&
                                _totalBytes! > 0)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${_formatInstallBytes(_downloadedBytes!)} / ${_formatInstallBytes(_totalBytes!)}',
                                        style: const TextStyle(
                                          color: Color(0xFF8296A8),
                                          fontSize: 9,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${((_downloadProgress ?? 0) * 100).toStringAsFixed(1)}%  •  متبقٍ ${_formatInstallBytes((_totalBytes! - _downloadedBytes!).clamp(0, _totalBytes!).toInt())}',
                                      style: const TextStyle(
                                        color: Color(0xFF00F0FF),
                                        fontSize: 9,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ],
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 5),
                      child: Row(
                        children: [
                          if (!_linuxInstalled)
                            FilledButton.icon(
                              onPressed: _busy || _installingLinux
                                  ? null
                                  : _installLinux,
                              icon: const Icon(Icons.download_rounded),
                              label: Text(_installingLinux
                                  ? 'جارٍ التثبيت…'
                                  : 'تهيئة Ubuntu'),
                            )
                          else if (!_running)
                            FilledButton.icon(
                              onPressed: _busy ? null : _start,
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('تشغيل'),
                            )
                          else
                            OutlinedButton.icon(
                              onPressed: _close,
                              icon: const Icon(Icons.stop_rounded),
                              label: const Text('إيقاف'),
                            ),
                          const Spacer(),
                          Text(
                            _running ? 'SESSION ACTIVE' : 'SESSION IDLE',
                            style: const TextStyle(
                              color: Color(0xFF8296A8),
                              fontSize: 8,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 5, 12, 13),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _input,
                              enabled: _running,
                              textDirection: TextDirection.ltr,
                              onSubmitted: (_) => _send(),
                              decoration: const InputDecoration(
                                hintText: 'اكتب أمر shell…',
                                prefixIcon: Icon(
                                  Icons.chevron_right_rounded,
                                  color: Color(0xFF00F0FF),
                                ),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: _running ? _send : null,
                            icon: const Icon(Icons.send_rounded),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
