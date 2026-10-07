import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'db.dart';

/// معلومات نسخة احتياطية موجودة على Google Drive
class BackupInfo {
  final String id;
  final String name;
  final DateTime? time;
  final int size;
  BackupInfo(this.id, this.name, this.time, this.size);
}

/// النسخ الاحتياطي واستعادة البيانات عبر Google Drive (مجلد التطبيق الخاص appDataFolder)
/// النسخة = ملف ZIP يحتوي data.json (كل الجداول) + مجلد images (صور العقارات والعقود)
class BackupService {
  static final GoogleSignIn _gsi =
      GoogleSignIn(scopes: [drive.DriveApi.driveAppdataScope]);

  static const _tables = [
    'properties',
    'payments',
    'attachments',
    'users',
    'settings',
  ];
  static const _keep = 10; // عدد النسخ المحفوظة على Drive

  // ---------------- حساب Google ----------------
  static GoogleSignInAccount? get account => _gsi.currentUser;

  static Future<GoogleSignInAccount?> signInSilently() async {
    try {
      return await _gsi.signInSilently();
    } catch (_) {
      return null;
    }
  }

  static Future<GoogleSignInAccount?> signIn() => _gsi.signIn();

  static Future<void> signOut() async {
    try {
      await _gsi.disconnect();
    } catch (_) {
      await _gsi.signOut();
    }
  }

  static Future<drive.DriveApi> _api() async {
    var acc = _gsi.currentUser ?? await _gsi.signInSilently();
    acc ??= await _gsi.signIn();
    if (acc == null) throw Exception('تم إلغاء تسجيل الدخول بحساب Google');
    final client = await _gsi.authenticatedClient();
    if (client == null) throw Exception('تعذر الحصول على صلاحية Google Drive');
    return drive.DriveApi(client);
  }

  // ---------------- إنشاء النسخة ----------------
  static Future<Uint8List> buildZip() async {
    final d = await DB.db;
    final data = <String, dynamic>{
      'app': 'real_estate_app',
      'db_version': DB.version,
      'created_at': DateTime.now().toIso8601String(),
    };
    final archive = Archive();
    final added = <String>{};

    for (final t in _tables) {
      final rows = await d.query(t);
      final out = <Map<String, dynamic>>[];
      for (final r in rows) {
        final m = Map<String, dynamic>.from(r);
        if (t == 'attachments') {
          m['path'] = p.basename((m['path'] ?? '').toString());
        }
        out.add(m);
      }
      data[t] = out;
    }

    // الصور (من جدول المرفقات)
    final atts = await d.query('attachments');
    for (final a in atts) {
      final path = (a['path'] ?? '').toString();
      if (path.isEmpty) continue;
      final name = p.basename(path);
      if (!added.add(name)) continue;
      final f = File(path);
      if (await f.exists()) {
        final bytes = await f.readAsBytes();
        archive.addFile(ArchiveFile('images/$name', bytes.length, bytes));
      }
    }

    final json = utf8.encode(jsonEncode(data));
    archive.addFile(ArchiveFile('data.json', json.length, json));
    final zipped = ZipEncoder().encode(archive);
    if (zipped == null) throw Exception('فشل إنشاء ملف النسخة');
    return Uint8List.fromList(zipped);
  }

  // ---------------- نسخة احتياطية كملف على الجهاز ----------------
  /// ينشئ ملف النسخة في مجلد مؤقت ويعيد مساره (للمشاركة/الحفظ)
  static Future<String> exportToFile() async {
    final bytes = await buildZip();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name =
        'backup_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.zip';
    final dir = await getTemporaryDirectory();
    final path = p.join(dir.path, name);
    await File(path).writeAsBytes(bytes, flush: true);
    await DB.setSetting('last_backup', now.toIso8601String());
    return path;
  }

  // ---------------- رفع نسخة احتياطية ----------------
  static Future<BackupInfo> backupNow() async {
    final api = await _api();
    final bytes = await buildZip();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name =
        'backup_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}.zip';

    final meta = drive.File()
      ..name = name
      ..parents = ['appDataFolder'];
    final media = drive.Media(Stream.value(bytes), bytes.length,
        contentType: 'application/zip');
    final res = await api.files.create(meta, uploadMedia: media);

    // حذف النسخ الأقدم والإبقاء على آخر _keep نسخ
    try {
      final all = await listBackups();
      if (all.length > _keep) {
        for (final old in all.sublist(_keep)) {
          await api.files.delete(old.id);
        }
      }
    } catch (_) {}

    await DB.setSetting('last_backup', now.toIso8601String());
    return BackupInfo(res.id ?? '', name, now, bytes.length);
  }

  // ---------------- قائمة النسخ ----------------
  static Future<List<BackupInfo>> listBackups() async {
    final api = await _api();
    final res = await api.files.list(
      spaces: 'appDataFolder',
      $fields: 'files(id,name,size,createdTime)',
      orderBy: 'createdTime desc',
      pageSize: 50,
    );
    return (res.files ?? [])
        .map((f) => BackupInfo(
              f.id ?? '',
              f.name ?? '',
              f.createdTime?.toLocal(),
              int.tryParse(f.size ?? '') ?? 0,
            ))
        .toList();
  }

  // ---------------- الاستيراد (الاستعادة) ----------------
  static Future<void> restore(BackupInfo info) async {
    final api = await _api();
    final media = await api.files.get(info.id,
        downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in media.stream) {
      builder.add(chunk);
    }
    await restoreBytes(builder.takeBytes());
  }

  /// استعادة من بايتات ملف ZIP (من Drive أو من ملف على الجهاز)
  static Future<void> restoreBytes(Uint8List zipBytes) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (_) {
      throw Exception('الملف غير صالح أو تالف');
    }

    final jsonFile = archive.findFile('data.json');
    if (jsonFile == null) throw Exception('ملف النسخة غير صالح');
    final data =
        jsonDecode(utf8.decode(jsonFile.content as List<int>)) as Map<String, dynamic>;
    if (data['app'] != 'real_estate_app') {
      throw Exception('هذه ليست نسخة من هذا التطبيق');
    }
    if ((data['db_version'] as int? ?? 0) > DB.version) {
      throw Exception('النسخة أحدث من إصدار التطبيق، حدّث التطبيق أولاً');
    }

    // استرجاع الصور إلى مجلد المستندات
    final dir = await getApplicationDocumentsDirectory();
    for (final f in archive.files) {
      if (!f.isFile || !f.name.startsWith('images/')) continue;
      final dest = p.join(dir.path, p.basename(f.name));
      await File(dest).writeAsBytes(f.content as List<int>);
    }

    // استبدال الجداول داخل معاملة واحدة (إما كلها أو لا شيء)
    final d = await DB.db;
    await d.transaction((txn) async {
      for (final t in _tables) {
        await txn.delete(t);
      }
      for (final t in _tables) {
        final rows = (data[t] as List? ?? []);
        for (final r in rows) {
          final m = Map<String, dynamic>.from(r as Map);
          if (t == 'attachments') {
            final name = (m['path'] ?? '').toString();
            m['path'] = name.isEmpty ? '' : p.join(dir.path, name);
          }
          await txn.insert(t, m);
        }
      }
    });
  }
}
