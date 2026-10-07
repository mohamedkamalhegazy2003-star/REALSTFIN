import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:share_plus/share_plus.dart';

import 'backup.dart';
import 'db.dart';
import 'home.dart';
import 'notifications.dart';
import 'utils.dart';

/// المستخدم الحالي (في الذاكرة فقط)
Map<String, dynamic>? currentUser;

bool get isMainUser => currentUser?['role'] == 'main';

// ---------------------------------------------------------
// شاشة تسجيل الدخول
// ---------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final LocalAuthentication _auth = LocalAuthentication();
  bool _busy = false;
  bool _hide = true;
  bool _bioAvail = false;
  bool _bioOn = false;
  String? _error;
  List<Map<String, dynamic>> _hints = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final users = await DB.users();
      final last = await DB.getSetting('last_user');
      _user.text = last ?? (users.isNotEmpty ? users.first['username'].toString() : '');
      _hints = users.where((u) => u['must_change'] == 1).toList();
      _bioOn = (await DB.getSetting('biometric_enabled')) == '1';
      try {
        _bioAvail = await _auth.isDeviceSupported();
      } catch (_) {
        _bioAvail = false;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {});
    if (_bioOn && _bioAvail) _biometric();
  }

  String _defaultPass(String username) =>
      username == 'admin' ? '1234' : (username == 'backup' ? '5678' : '');

  Future<void> _login() async {
    final name = _user.text.trim();
    if (name.isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'أدخل اسم المستخدم وكلمة المرور');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final u = await DB.userByName(name);
    if (u != null &&
        hashPw(u['salt'].toString(), _pass.text) == u['pass_hash']) {
      await _enter(u);
    } else {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'اسم المستخدم أو كلمة المرور غير صحيحة';
        });
      }
    }
  }

  Future<void> _biometric() async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'سجّل الدخول ببصمتك',
        options: const AuthenticationOptions(
            biometricOnly: false, stickyAuth: true),
      );
      if (!ok) return;
      final name = await DB.getSetting('biometric_user');
      final u = name == null ? null : await DB.userByName(name);
      if (u == null) {
        if (mounted) setState(() => _error = 'لم يتم ربط حساب بالبصمة');
        return;
      }
      await _enter(u);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر استخدام البصمة على هذا الجهاز');
    }
  }

  Future<void> _enter(Map<String, dynamic> u) async {
    currentUser = Map<String, dynamic>.from(u);
    await DB.setSetting('last_user', u['username'].toString());
    await loadAppSettings();
    await Notifier.bootstrap();
    if ((await DB.getSetting('login_notice')) != '0') {
      await Notifier.showLogin(u['display_name'].toString());
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: cs.primary,
                    child: const Icon(Icons.apartment, size: 44, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  const Text('إدارة العقارات',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('سجّل الدخول للمتابعة',
                      style: TextStyle(color: Colors.black54)),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _user,
                    decoration: const InputDecoration(
                        labelText: 'اسم المستخدم',
                        prefixIcon: Icon(Icons.person_outline)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: _hide,
                    onSubmitted: (_) => _login(),
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_hide ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _hide = !_hide),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _busy ? null : _login,
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('دخول',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  if (_bioOn && _bioAvail) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _biometric,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('الدخول بالبصمة'),
                    ),
                  ],
                  if (_hints.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withAlpha(40),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('بيانات الدخول الافتراضية (غيّرها من الإعدادات):',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          for (final h in _hints)
                            Text(
                                '${h['display_name']}: ${h['username']} / ${_defaultPass(h['username'].toString())}'),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// شاشة إعدادات التطبيق
// ---------------------------------------------------------
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final LocalAuthentication _auth = LocalAuthentication();
  final _company = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  bool _bio = false;
  bool _bioSupported = false;
  bool _notif = false;
  bool _permission = false;
  int _soon = 3;
  bool _loading = true;
  bool _loginNotice = true;
  bool _gBusy = false;
  String? _gEmail;
  String? _lastBackup;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final users = await DB.users();
    final bioUser = await DB.getSetting('biometric_user');
    final bioOn = (await DB.getSetting('biometric_enabled')) == '1' &&
        bioUser == currentUser?['username'];
    var supported = false;
    try {
      supported = await _auth.isDeviceSupported();
    } catch (_) {}
    final notif = (await DB.getSetting('notifications_enabled')) == '1';
    var perm = false;
    try {
      perm = await Notifier.permissionGranted();
    } catch (_) {}
    _company.text = await DB.getSetting('company_name') ?? '';
    final loginNotice = (await DB.getSetting('login_notice')) != '0';
    final lastBackup = await DB.getSetting('last_backup');
    final gAcc = BackupService.account ?? await BackupService.signInSilently();
    if (!mounted) return;
    setState(() {
      _loginNotice = loginNotice;
      _lastBackup = lastBackup;
      _gEmail = gAcc?.email;
      _users = users;
      _bio = bioOn;
      _bioSupported = supported;
      _notif = notif;
      _permission = perm;
      _soon = soonDays;
      _loading = false;
    });
  }

  Future<void> _toggleBio(bool v) async {
    if (!v) {
      await DB.setSetting('biometric_enabled', '0');
      setState(() => _bio = false);
      return;
    }
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'تأكيد البصمة لتفعيل الدخول بها',
        options: const AuthenticationOptions(
            biometricOnly: false, stickyAuth: true),
      );
      if (!ok) return;
      await DB.setSetting('biometric_enabled', '1');
      await DB.setSetting('biometric_user', currentUser!['username'].toString());
      setState(() => _bio = true);
    } catch (_) {
      if (mounted) toast(context, 'تعذر استخدام البصمة على هذا الجهاز');
    }
  }

  Future<void> _toggleNotif(bool v) async {
    if (v) {
      final ok = await Notifier.requestPermission();
      if (!ok) {
        if (mounted) {
          toast(context, 'صلاحية الإشعارات مرفوضة. فعّلها من إعدادات الهاتف.');
        }
        await _load();
        return;
      }
      await DB.setSetting('notifications_enabled', '1');
      await Notifier.schedule();
    } else {
      await DB.setSetting('notifications_enabled', '0');
      await Notifier.cancel();
    }
    await _load();
  }

  // ---------------- Google Drive: نسخ احتياطي واستيراد ----------------
  String _fmtDateTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)}  ${two(d.hour)}:${two(d.minute)}';
  }

  String _fmtSize(int b) => b >= 1048576
      ? '${(b / 1048576).toStringAsFixed(1)} MB'
      : '${(b / 1024).toStringAsFixed(0)} KB';

  String _gErr(Object e) {
    final s = e.toString();
    if (s.contains('ApiException: 10') || s.contains('sign_in_failed')) {
      return 'فشل تسجيل الدخول بـ Google. تأكد من إعداد OAuth (SHA-1) في Google Cloud.';
    }
    if (s.contains('SocketException') || s.contains('ClientException')) {
      return 'لا يوجد اتصال بالإنترنت';
    }
    return 'حدث خطأ: $s';
  }

  Future<void> _gConnect() async {
    setState(() => _gBusy = true);
    try {
      final acc = await BackupService.signIn();
      if (acc != null) _gEmail = acc.email;
    } catch (e) {
      if (mounted) toast(context, _gErr(e));
    }
    if (mounted) setState(() => _gBusy = false);
  }

  Future<void> _gDisconnect() async {
    await BackupService.signOut();
    if (mounted) setState(() => _gEmail = null);
  }

  Future<void> _backupNow() async {
    setState(() => _gBusy = true);
    try {
      final b = await BackupService.backupNow();
      _gEmail = BackupService.account?.email ?? _gEmail;
      _lastBackup = DateTime.now().toIso8601String();
      if (mounted) toast(context, 'تم رفع النسخة الاحتياطية (${_fmtSize(b.size)})');
    } catch (e) {
      if (mounted) toast(context, _gErr(e));
    }
    if (mounted) setState(() => _gBusy = false);
  }

  Future<void> _importBackup() async {
    setState(() => _gBusy = true);
    List<BackupInfo> list;
    try {
      list = await BackupService.listBackups();
      _gEmail = BackupService.account?.email ?? _gEmail;
    } catch (e) {
      if (mounted) {
        setState(() => _gBusy = false);
        toast(context, _gErr(e));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _gBusy = false);
    if (list.isEmpty) {
      toast(context, 'لا توجد نسخ احتياطية على هذا الحساب');
      return;
    }
    final chosen = await showDialog<BackupInfo>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اختر النسخة المراد استيرادها'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final b in list)
                ListTile(
                  leading: const Icon(Icons.cloud_download_outlined),
                  title: Text(b.time == null ? b.name : _fmtDateTime(b.time!)),
                  subtitle: Text(_fmtSize(b.size)),
                  onTap: () => Navigator.pop(ctx, b),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        ],
      ),
    );
    if (chosen == null || !mounted) return;

    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الاستيراد'),
        content: const Text(
            'سيتم استبدال كل البيانات الحالية (العقارات، الإيصالات، الصور، الحسابات) بمحتوى هذه النسخة. لا يمكن التراجع.\n\nهل تريد المتابعة؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('استيراد')),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    setState(() => _gBusy = true);
    try {
      await BackupService.restore(chosen);
      await loadAppSettings();
      if (!mounted) return;
      toast(context, 'تم استيراد النسخة بنجاح، سجّل الدخول من جديد');
      currentUser = null;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (r) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _gBusy = false);
        toast(context, _gErr(e));
      }
    }
  }

  // ---------------- نسخ احتياطي كملف / استيراد من ملف ----------------
  Future<void> _exportFile() async {
    setState(() => _gBusy = true);
    try {
      final path = await BackupService.exportToFile();
      _lastBackup = DateTime.now().toIso8601String();
      if (mounted) setState(() => _gBusy = false);
      await Share.shareXFiles([XFile(path)],
          subject: 'نسخة احتياطية - إدارة العقارات');
    } catch (e) {
      if (mounted) toast(context, _gErr(e));
    }
    if (mounted) setState(() => _gBusy = false);
  }

  Future<void> _importFile() async {
    FilePickerResult? res;
    try {
      res = await FilePicker.platform
          .pickFiles(type: FileType.any, withData: true);
    } catch (_) {
      if (mounted) toast(context, 'تعذر فتح اختيار الملفات');
      return;
    }
    if (res == null || res.files.isEmpty || !mounted) return;
    final file = res.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      toast(context, 'تعذر قراءة الملف');
      return;
    }
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الاستيراد'),
        content: Text(
            'سيتم استبدال كل البيانات الحالية (العقارات، الإيصالات، الصور، الحسابات) بمحتوى الملف:\n${file.name}\n\nلا يمكن التراجع. هل تريد المتابعة؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('استيراد')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _gBusy = true);
    try {
      await BackupService.restoreBytes(bytes);
      await loadAppSettings();
      if (!mounted) return;
      toast(context, 'تم استيراد النسخة بنجاح، سجّل الدخول من جديد');
      currentUser = null;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (r) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _gBusy = false);
        toast(context, _gErr(e));
      }
    }
  }

  Future<void> _saveApp() async {
    await DB.setSetting('company_name', _company.text.trim());
    await DB.setSetting('soon_days', '$_soon');
    await loadAppSettings();
    if (mounted) toast(context, 'تم حفظ الإعدادات');
  }

  Future<void> _editUser(Map<String, dynamic> u) async {
    final own = u['id'] == currentUser?['id'];
    final name = TextEditingController(text: u['display_name'].toString());
    final uname = TextEditingController(text: u['username'].toString());
    final cur = TextEditingController();
    final np = TextEditingController();
    final np2 = TextEditingController();
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('تعديل ${u['display_name']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'الاسم')),
                const SizedBox(height: 10),
                TextField(
                    controller: uname,
                    decoration: const InputDecoration(labelText: 'اسم المستخدم')),
                const SizedBox(height: 10),
                if (own)
                  TextField(
                      controller: cur,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'كلمة المرور الحالية (لتغييرها)')),
                if (own) const SizedBox(height: 10),
                TextField(
                    controller: np,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'كلمة مرور جديدة (اختياري)')),
                const SizedBox(height: 10),
                TextField(
                    controller: np2,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'تأكيد كلمة المرور الجديدة')),
                if (err != null) ...[
                  const SizedBox(height: 10),
                  Text(err!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                if (uname.text.trim().isEmpty || name.text.trim().isEmpty) {
                  setS(() => err = 'الاسم واسم المستخدم مطلوبان');
                  return;
                }
                if (np.text.isNotEmpty) {
                  if (np.text.length < 4) {
                    setS(() => err = 'كلمة المرور 4 أحرف على الأقل');
                    return;
                  }
                  if (np.text != np2.text) {
                    setS(() => err = 'تأكيد كلمة المرور غير مطابق');
                    return;
                  }
                  if (own &&
                      hashPw(u['salt'].toString(), cur.text) != u['pass_hash']) {
                    setS(() => err = 'كلمة المرور الحالية غير صحيحة');
                    return;
                  }
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final upd = <String, dynamic>{
      'display_name': name.text.trim(),
      'username': uname.text.trim(),
    };
    if (np.text.isNotEmpty) {
      final salt = newSalt();
      upd['salt'] = salt;
      upd['pass_hash'] = hashPw(salt, np.text);
      upd['must_change'] = 0;
    }
    try {
      await DB.updateUser(u['id'] as int, upd);
      if (own) {
        currentUser = {...currentUser!, ...upd};
        if ((await DB.getSetting('biometric_user')) == u['username']) {
          await DB.setSetting('biometric_user', upd['username'].toString());
        }
      }
      if (mounted) toast(context, 'تم حفظ بيانات الحساب');
    } catch (_) {
      if (mounted) toast(context, 'اسم المستخدم مستخدم بالفعل');
    }
    await _load();
  }

  Future<void> _logout() async {
    currentUser = null;
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (r) => false,
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(t,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات التطبيق',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                _section('الحسابات'),
                for (final u in _users)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(u['role'] == 'main'
                              ? Icons.admin_panel_settings
                              : Icons.person),
                        ),
                        title: Text('${u['display_name']}'),
                        subtitle: Text(
                            '${u['username']}${u['id'] == currentUser?['id'] ? ' (أنت)' : ''}'),
                        trailing: (isMainUser || u['id'] == currentUser?['id'])
                            ? IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _editUser(u),
                              )
                            : null,
                      ),
                    ),
                  ),
                _section('الأمان'),
                AppCard(
                  child: SwitchListTile(
                    secondary: const Icon(Icons.fingerprint),
                    title: const Text('الدخول بالبصمة'),
                    subtitle: Text(_bioSupported
                        ? 'للحساب الحالي: ${currentUser?['username']}'
                        : 'غير مدعومة على هذا الجهاز'),
                    value: _bio,
                    onChanged: _bioSupported ? _toggleBio : null,
                  ),
                ),
                _section('الإشعارات'),
                AppCard(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.notifications_active_outlined),
                        title: const Text('إشعارات المتأخرات والاستحقاق'),
                        subtitle: const Text('فحص وإشعار كل 4 ساعات'),
                        value: _notif,
                        onChanged: _toggleNotif,
                      ),
                      ListTile(
                        leading: Icon(
                            _permission ? Icons.check_circle : Icons.error_outline,
                            color: _permission ? Colors.green : Colors.orange),
                        title: Text(_permission
                            ? 'صلاحية الإشعارات ممنوحة'
                            : 'صلاحية الإشعارات غير ممنوحة'),
                        trailing: _permission
                            ? null
                            : TextButton(
                                onPressed: () async {
                                  await Notifier.requestPermission();
                                  await _load();
                                },
                                child: const Text('طلب الصلاحية'),
                              ),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.login),
                        title: const Text('إشعار تسجيل الدخول'),
                        subtitle: const Text('إشعار عند كل دخول ناجح للتطبيق'),
                        value: _loginNotice,
                        onChanged: (v) async {
                          await DB.setSetting('login_notice', v ? '1' : '0');
                          setState(() => _loginNotice = v);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.send_outlined),
                        title: const Text('إرسال إشعار تجريبي'),
                        onTap: () async {
                          await Notifier.show('تنبيه تجريبي', 'الإشعارات تعمل بنجاح ✅');
                        },
                      ),
                    ],
                  ),
                ),
                _section('النسخ الاحتياطي (Google Drive)'),
                AppCard(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                            _gEmail != null ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                            color: _gEmail != null ? Colors.green : Colors.grey),
                        title: Text(_gEmail ?? 'غير متصل بحساب Google'),
                        subtitle: Text(_lastBackup == null
                            ? 'لم يتم أخذ نسخة بعد'
                            : 'آخر نسخة: ${_fmtDateTime(DateTime.tryParse(_lastBackup!) ?? DateTime.now())}'),
                        trailing: _gEmail == null
                            ? TextButton(
                                onPressed: _gBusy ? null : _gConnect,
                                child: const Text('ربط الحساب'))
                            : TextButton(
                                onPressed: _gBusy ? null : _gDisconnect,
                                child: const Text('فصل')),
                      ),
                      if (_gBusy) const LinearProgressIndicator(),
                      ListTile(
                        leading: const Icon(Icons.cloud_upload_outlined),
                        title: const Text('نسخ احتياطي الآن'),
                        subtitle: const Text('رفع كل البيانات والصور إلى Google Drive'),
                        enabled: !_gBusy,
                        onTap: _gBusy ? null : _backupNow,
                      ),
                      ListTile(
                        leading: const Icon(Icons.cloud_download_outlined),
                        title: const Text('استيراد نسخة احتياطية'),
                        subtitle: Text(isMainUser
                            ? 'استعادة البيانات من Google Drive'
                            : 'متاح للحساب الرئيسي فقط'),
                        enabled: !_gBusy && isMainUser,
                        onTap: (_gBusy || !isMainUser) ? null : _importBackup,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.save_alt),
                        title: const Text('نسخ احتياطي كملف'),
                        subtitle: const Text('حفظ أو مشاركة ملف النسخة (واتساب، الملفات...)'),
                        enabled: !_gBusy,
                        onTap: _gBusy ? null : _exportFile,
                      ),
                      ListTile(
                        leading: const Icon(Icons.folder_open_outlined),
                        title: const Text('استيراد من ملف'),
                        subtitle: Text(isMainUser
                            ? 'اختيار ملف نسخة احتياطية من الجهاز'
                            : 'متاح للحساب الرئيسي فقط'),
                        enabled: !_gBusy && isMainUser,
                        onTap: (_gBusy || !isMainUser) ? null : _importFile,
                      ),
                    ],
                  ),
                ),
                _section('بيانات التطبيق'),
                AppCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextField(
                          controller: _company,
                          decoration: const InputDecoration(
                              labelText: 'اسم المكتب/المالك (يظهر في الإيصالات)',
                              prefixIcon: Icon(Icons.business_outlined)),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          value: _soon,
                          items: const [1, 2, 3, 5, 7, 10]
                              .map((d) => DropdownMenuItem(
                                  value: d, child: Text('قبل الاستحقاق بـ $d يوم')))
                              .toList(),
                          onChanged: (v) => setState(() => _soon = v ?? 3),
                          decoration: const InputDecoration(
                              labelText: 'موعد تنبيه قرب الاستحقاق',
                              prefixIcon: Icon(Icons.schedule)),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                              onPressed: _saveApp, child: const Text('حفظ')),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout),
                  label: const Text('تسجيل الخروج'),
                ),
              ],
            ),
    );
  }
}
