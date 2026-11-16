import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/tafsir_downloads.dart';

/// v12 tafsir downloads: the 5 big tafsirs are download-on-demand
/// (NOT bundled). Tap تحميل once, background download, offline
/// after. The bundled الميسر needs no download.
///
/// MockClient stands in for the network; no real HTTP is made.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late TafsirService service;

  const sampleTafsirJson = '{"1:1": "تفسير السعدي للفاتحة 1", "1:2": "تفسير السعدي للفاتحة 2"}';

  Future<TafsirService> makeService({required http.Client client}) async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('tafsir-dl-test');
    final s = TafsirService(
      client: client,
      storageDir: tempDir,
      prefs: await SharedPreferences.getInstance(),
    );
    await s.init();
    return s;
  }

  tearDown(() async {
    service.dispose();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('selector has 6 tafsirs; الميسر bundled, the rest downloadable',
      () async {
    service = await makeService(
      client: MockClient((_) async => http.Response('', 404)),
    );
    expect(kTafsirs, hasLength(6));
    expect(
      kTafsirs.map((t) => t.id),
      ['muyassar', 'jalalayn', 'saadi', 'siraj', 'tabari', 'ibn_kathir'],
    );
    expect(kTafsirs.first.isBundled, isTrue);
    expect(kTafsirs.skip(1).every((t) => !t.isBundled), isTrue);
    expect(kTafsirs.skip(1).every((t) => t.downloadUrl != null), isTrue);
    // All five download URLs point at the repo's raw files.
    for (final t in kTafsirs.skip(1)) {
      expect(
        t.downloadUrl,
        startsWith(
            'https://raw.githubusercontent.com/zeiaad98-maker/noor-quran-app/main/assets/quran_data/tafsir_'),
      );
    }
    // الميسر is available from the start; the rest are not.
    expect(service.statusOf('muyassar'), TafsirStatus.downloaded);
    expect(service.statusOf('jalalayn'), TafsirStatus.notDownloaded);
    expect(service.selectedId, 'muyassar');
  });

  test('v12 availability: الميسر bundled; السعدي + السراج downloadable; '
      'الجلالين + الطبري + ابن كثير deferred to v13', () async {
    service = await makeService(
      client: MockClient((_) async => http.Response('', 404)),
    );
    TafsirInfo byId(String id) =>
        kTafsirs.firstWhere((t) => t.id == id);
    expect(byId('muyassar').isBundled, isTrue);
    expect(byId('saadi').available, isTrue);
    expect(byId('siraj').available, isTrue);
    expect(byId('saadi').downloadUrl, contains('tafsir_saadi.json'));
    expect(byId('siraj').downloadUrl, contains('tafsir_siraj.json'));
    // Extraction not finished in time: no download is offered.
    for (final id in ['jalalayn', 'tabari', 'ibn_kathir']) {
      expect(byId(id).available, isFalse);
    }
  });

  test('download: 200 + valid JSON -> downloaded, text readable',
      () async {
    final requested = <String>[];
    service = await makeService(
      client: MockClient((request) async {
        requested.add(request.url.toString());
        return http.Response.bytes(utf8.encode(sampleTafsirJson), 200);
      }),
    );
    final saadi =
        kTafsirs.firstWhere((t) => t.id == 'saadi');

    await service.download(saadi);
    expect(service.statusOf('saadi'), TafsirStatus.downloaded);
    expect(service.progressOf('saadi'), 1.0);
    expect(requested, [saadi.downloadUrl]);
    expect(
      await File('${tempDir.path}/tafsir_saadi.json').readAsString(),
      sampleTafsirJson,
    );

    // Select it and read an ayah.
    expect(await service.select('saadi'), isTrue);
    expect(service.selectedId, 'saadi');
    expect(
      await service.selectedTafsirForAyah(1, 2),
      'تفسير السعدي للفاتحة 2',
    );
    expect(await service.selectedTafsirForAyah(1, 3), isNull);
  });

  test('404 -> failed with error; retry succeeds', () async {
    var fail = true;
    service = await makeService(
      client: MockClient((_) async {
        if (fail) return http.Response('not found', 404);
        return http.Response.bytes(utf8.encode(sampleTafsirJson), 200);
      }),
    );
    final saadi =
        kTafsirs.firstWhere((t) => t.id == 'saadi');

    await service.download(saadi);
    expect(service.statusOf('saadi'), TafsirStatus.failed);
    expect(service.errorOf('saadi'), contains('404'));
    expect(await service.select('saadi'), isFalse);

    fail = false;
    await service.download(saadi);
    expect(service.statusOf('saadi'), TafsirStatus.downloaded);
  });

  test('resume: partial file continues with a Range request', () async {
    final ranges = <String?>[];
    service = await makeService(
      client: MockClient((request) async {
        ranges.add(request.headers['Range']);
        final bytes = utf8.encode(sampleTafsirJson);
        final range = request.headers['Range'];
        if (range == null) {
          return http.Response.bytes(bytes, 200);
        }
        // bytes=10- : return the rest with 206 + Content-Range.
        final start = int.parse(range.split('=')[1].split('-')[0]);
        return http.Response.bytes(
          bytes.sublist(start),
          206,
          headers: {
            'content-range': 'bytes $start-${bytes.length - 1}/${bytes.length}',
          },
        );
      }),
    );
    final saadi =
        kTafsirs.firstWhere((t) => t.id == 'saadi');
    // A previous attempt left the first 10 bytes on disk.
    final file = File('${tempDir.path}/tafsir_saadi.json');
    await file.writeAsBytes(utf8.encode(sampleTafsirJson).sublist(0, 10));

    await service.download(saadi);
    expect(ranges, ['bytes=10-']);
    expect(service.statusOf('saadi'), TafsirStatus.downloaded);
    expect(await file.readAsString(), sampleTafsirJson);
  });

  test('invalid JSON is rejected and the bad file is removed',
      () async {
    var badJson = true;
    final ranges = <String?>[];
    service = await makeService(
      client: MockClient((request) async {
        ranges.add(request.headers['Range']);
        if (badJson) {
          return http.Response.bytes(utf8.encode('this is not json'), 200);
        }
        return http.Response.bytes(utf8.encode(sampleTafsirJson), 200);
      }),
    );
    final saadi = kTafsirs.firstWhere((t) => t.id == 'saadi');
    await service.download(saadi);
    expect(service.statusOf('saadi'), TafsirStatus.failed);
    expect(
      await File('${tempDir.path}/tafsir_saadi.json').exists(),
      isFalse,
    );
    // A retry after the server is fixed starts clean (no Range on
    // a deleted file) and succeeds.
    badJson = false;
    await service.download(saadi);
    expect(ranges.last, isNull);
    expect(service.statusOf('saadi'), TafsirStatus.downloaded);
  });

  test('unavailable tafsir (failed extraction): no download, no select',
      () async {
    // A tafsir whose extraction failed is marked available: false.
    // The service must never attempt its download, and select()
    // must refuse it — the UI shows "غير متوفر بعد" instead.
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('tafsir-dl-test');
    var requests = 0;
    service = TafsirService(
      client: MockClient((_) async {
        requests++;
        return http.Response.bytes(utf8.encode(sampleTafsirJson), 200);
      }),
      storageDir: tempDir,
      prefs: await SharedPreferences.getInstance(),
      tafsirs: [
        const TafsirInfo(
          id: 'muyassar',
          name: 'التفسير الميسر',
          assetPath: 'assets/quran_data/tafsir_muyassar.json',
        ),
        const TafsirInfo(
          id: 'tabari',
          name: 'تفسير الطبري',
          downloadUrl: 'https://example.invalid/tafsir_tabari.json',
          dalailBookId: 43,
          available: false,
        ),
      ],
    );
    await service.init();
    expect(service.selectedId, 'muyassar');
    final failed = TafsirInfo(
      id: 'tabari',
      name: 'تفسير الطبري',
      downloadUrl: 'https://example.invalid/tafsir_tabari.json',
      dalailBookId: 43,
      available: false,
    );
    await service.download(failed);
    expect(requests, 0);
    expect(service.statusOf('tabari'), TafsirStatus.notDownloaded);
    expect(await service.select('tabari'), isFalse);
    expect(service.selectedId, 'muyassar');
  });
}
