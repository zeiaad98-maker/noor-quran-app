/// A fake but VALID MP3 payload for tests.
///
/// v13.16 validates cached audio files (size >= 1 KB + MP3 magic:
/// an "ID3" tag or an MPEG frame sync), so test fixtures must look
/// like real recordings — the old tiny payloads ([1, 2, 3, 4],
/// [7], ...) are now correctly rejected as poisoned cache and
/// re-downloaded. Use this wherever a test serves or seeds a
/// per-ayah / wbw file and expects the cache to keep it.
///
/// [fill] distinguishes payloads from different hosts when a test
/// asserts which host served the file (the ID3 header is the same;
/// the body bytes are [fill]).
List<int> fakeMp3Bytes({int size = 2048, int fill = 0}) {
  const head = <int>[
    0x49, 0x44, 0x33, // "ID3"
    0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x21,
  ];
  assert(size >= head.length);
  return [...head, ...List<int>.filled(size - head.length, fill)];
}
