import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'word_meanings.dart';

/// The six tafsirs offered in the tafsir card (v12).
///
/// * التفسير الميسر is BUNDLED in the APK (small, 2.57 MB) and is
///   the default.
/// * The other five are DOWNLOAD-ON-DEMAND: they are NOT bundled
///   (together ~15–35 MB raw), so the app size does not grow. Each is
///   a per-ayah JSON in the same `{"3:7": "..."}` shape as the bundled
///   الميسر, hosted in the app's own public repo — the URLs below are
///   the download source. Tap تحميل once in the tafsir selector: the
///   file downloads in the background (resumable), works offline
///   after, and shows only مثبّت afterwards — no file management.
///
/// Dalail book IDs (verified 2026-11-16): الجلالين 12876، السعدي 42،
/// السراج المنير 1466، الطبري 43، ابن كثير 1503.
/// One tafsir in the selector (v12).
///
/// `available` is false when the tafsir could NOT be extracted
/// cleanly per ayah — its row then shows "غير متوفر بعد" with no
/// تحميل button, instead of offering a broken download. Flip it to
/// false only for a tafsir the extraction reported as failed.
class TafsirInfo {
  final String id;
  final String name;
  final String? assetPath; // bundled (الميسر only)
  final String? downloadUrl; // raw.githubusercontent (the other five)
  final int? dalailBookId;
  final bool available;

  const TafsirInfo({
    required this.id,
    required this.name,
    this.assetPath,
    this.downloadUrl,
    this.dalailBookId,
    this.available = true,
  });

  bool get isBundled => assetPath != null;
}

const String _tafsirRepoBase =
    'https://raw.githubusercontent.com/zeiaad98-maker/noor-quran-app'
    '/main/assets/quran_data';

const List<TafsirInfo> kTafsirs = [
  TafsirInfo(
    id: 'muyassar',
    name: 'التفسير الميسر',
    assetPath: 'assets/quran_data/tafsir_muyassar.json',
  ),
  TafsirInfo(
    id: 'jalalayn',
    name: 'تفسير الجلالين',
    downloadUrl: '$_tafsirRepoBase/tafsir_jalalayn.json',
    dalailBookId: 12876,
    // v12: extraction not finished in time — comes in v13.
    available: false,
  ),
  TafsirInfo(
    id: 'saadi',
    name: 'تفسير السعدي',
    downloadUrl: '$_tafsirRepoBase/tafsir_saadi.json',
    dalailBookId: 42,
  ),
  TafsirInfo(
    id: 'siraj',
    name: 'السراج المنير',
    downloadUrl: '$_tafsirRepoBase/tafsir_siraj.json',
    dalailBookId: 1466,
  ),
  TafsirInfo(
    id: 'tabari',
    name: 'تفسير الطبري',
    downloadUrl: '$_tafsirRepoBase/tafsir_tabari.json',
    dalailBookId: 43,
    // v12: extraction not finished in time (14,577 pages, the
    // biggest) — comes in v13.
    available: false,
  ),
  TafsirInfo(
    id: 'ibn_kathir',
    name: 'تفسير ابن كثير',
    downloadUrl: '$_tafsirRepoBase/tafsir_ibn_kathir.json',
    dalailBookId: 1503,
    // v12: extraction not finished in time — comes in v13.
    available: false,
  ),
];

enum TafsirStatus { notDownloaded, downloading, downloaded, failed }

/// Download + selection state for the six tafsirs.
///
/// Files live under `<app documents>/tafsirs/tafsir_<id>.json`.
/// Downloads resume with HTTP Range when the server supports it
/// (raw.githubusercontent does); a failed download keeps the partial
/// file so the next attempt continues where it stopped. The completed
/// file is JSON-verified before it counts as downloaded.
class TafsirService extends ChangeNotifier {
  static const String selectedKey = 'tafsir_selected_id';
  static const String downloadedKey = 'tafsir_downloaded_ids';

  final http.Client _client;
  final Directory? _storageDirOverride;
  final SharedPreferences? _prefsOverride;
  final List<TafsirInfo> _tafsirs;

  String _selectedId = 'muyassar';
  final Map<String, TafsirStatus> _status = {};
  final Map<String, double?> _progress = {};
  final Map<String, String?> _error = {};
  final Map<String, Map<String, String>> _cache = {};

  TafsirService({
    http.Client? client,
    Directory? storageDir,
    SharedPreferences? prefs,
    List<TafsirInfo>? tafsirs,
  })  : _client = client ?? http.Client(),
        _storageDirOverride = storageDir,
        _prefsOverride = prefs,
        _tafsirs = tafsirs ?? kTafsirs;

  String get selectedId => _selectedId;

  TafsirInfo get selected =>
      _tafsirs.firstWhere((t) => t.id == _selectedId);

  TafsirStatus statusOf(String id) =>
      _status[id] ??
      (_tafsirs.firstWhere((t) => t.id == id).isBundled
          ? TafsirStatus.downloaded
          : TafsirStatus.notDownloaded);

  /// 0..1 while downloading, null when the total size is unknown.
  double? progressOf(String id) => _progress[id];

  String? errorOf(String id) => _error[id];

  bool get isAvailable => statusOf(_selectedId) == TafsirStatus.downloaded;

  Future<void> init() async {
    final prefs = _prefsOverride ?? await SharedPreferences.getInstance();
    final saved = prefs.getString(selectedKey);
    if (saved != null && _tafsirs.any((t) => t.id == saved)) {
      _selectedId = saved;
    }
    final downloaded = prefs.getStringList(downloadedKey) ?? const [];
    for (final info in _tafsirs) {
      if (info.isBundled) {
        _status[info.id] = TafsirStatus.downloaded;
        continue;
      }
      if (downloaded.contains(info.id)) {
        // Trust the flag only if the file is really there.
        final file = await _fileFor(info.id);
        _status[info.id] = await file.exists()
            ? TafsirStatus.downloaded
            : TafsirStatus.notDownloaded;
      }
    }
    notifyListeners();
  }

  Future<Directory> _dir() async {
    if (_storageDirOverride != null) return _storageDirOverride;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/tafsirs');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _fileFor(String id) async {
    final dir = await _dir();
    return File('${dir.path}/tafsir_$id.json');
  }

  /// Select a tafsir that is already available (bundled or
  /// downloaded). Returns false when it is not available yet.
  Future<bool> select(String id) async {
    if (statusOf(id) != TafsirStatus.downloaded) return false;
    _selectedId = id;
    final prefs = _prefsOverride ?? await SharedPreferences.getInstance();
    await prefs.setString(selectedKey, id);
    notifyListeners();
    return true;
  }

  /// Tafsir text for one ayah from the SELECTED tafsir, or null when
  /// the selected tafsir is not available / has no entry for it.
  Future<String?> selectedTafsirForAyah(int surah, int verse) async {
    final info = selected;
    if (info.isBundled) {
      return QuranWordData.tafsirForAyah(surah, verse);
    }
    if (statusOf(info.id) != TafsirStatus.downloaded) return null;
    final data = await _loadDownloaded(info.id);
    if (data == null) return null;
    return data['$surah:$verse'];
  }

  Future<Map<String, String>?> _loadDownloaded(String id) async {
    if (_cache.containsKey(id)) return _cache[id];
    try {
      final file = await _fileFor(id);
      if (!await file.exists()) return null;
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final data = raw.map((k, v) => MapEntry(k, v as String));
      _cache[id] = data;
      return data;
    } catch (_) {
      return null;
    }
  }

  /// Download one tafsir (tap تحميل once). Resumable, shows progress.
  /// On success the tafsir becomes available offline and is marked
  /// مثبّت. On failure the status is `failed` with an error message
  /// and the partial file is kept for the next attempt.
  Future<void> download(TafsirInfo info) async {
    if (info.isBundled || info.downloadUrl == null) return;
    if (!info.available) return; // extraction failed: no download to offer
    if (statusOf(info.id) == TafsirStatus.downloading) return;
    _status[info.id] = TafsirStatus.downloading;
    _progress[info.id] = 0;
    _error[info.id] = null;
    notifyListeners();

    final file = await _fileFor(info.id);
    var existing = await file.exists() ? await file.length() : 0;
    try {
      final request = http.Request('GET', Uri.parse(info.downloadUrl!));
      if (existing > 0) {
        request.headers['Range'] = 'bytes=$existing-';
      }
      final response = await _client.send(request).timeout(
            const Duration(seconds: 60),
          );
      if (response.statusCode == 416) {
        // The server rejects our range (file changed): restart clean.
        existing = 0;
        await file.writeAsString('');
      } else if (response.statusCode != 200 &&
          response.statusCode != 206) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final resumed = response.statusCode == 206;
      if (!resumed) existing = 0;
      final total = _totalLength(response, existing);
      final sink = file.openWrite(
        mode: resumed ? FileMode.append : FileMode.write,
      );
      var received = existing;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0) {
          _progress[info.id] = received / total;
          notifyListeners();
        }
      }
      await sink.close();

      // Verify before trusting it: valid JSON with ayah keys.
      // A bad file is deleted so the next attempt starts clean
      // (otherwise a retry would append good bytes to garbage).
      final data = await _loadDownloaded(info.id);
      if (data == null || data.isEmpty) {
        if (await file.exists()) await file.delete();
        _cache.remove(info.id);
        throw const FormatException('ملف التفسير غير صالح');
      }
      _status[info.id] = TafsirStatus.downloaded;
      _progress[info.id] = 1;
      final prefs = _prefsOverride ?? await SharedPreferences.getInstance();
      final downloaded = prefs.getStringList(downloadedKey) ?? <String>[];
      if (!downloaded.contains(info.id)) {
        downloaded.add(info.id);
        await prefs.setStringList(downloadedKey, downloaded);
      }
    } catch (e) {
      _status[info.id] = TafsirStatus.failed;
      _error[info.id] = e.toString();
    }
    notifyListeners();
  }

  /// Total file size from the response headers, or null when unknown.
  /// `existing` is the bytes already on disk (only meaningful on 206).
  static int? _totalLength(http.StreamedResponse response, int existing) {
    final contentLength =
        int.tryParse(response.headers['content-length'] ?? '');
    if (response.statusCode == 206) {
      // content-range: bytes 100-999/5000
      final range = response.headers['content-range'] ?? '';
      final total = int.tryParse(range.split('/').last);
      if (total != null) return total;
      if (contentLength != null) return existing + contentLength;
      return null;
    }
    return contentLength;
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}
