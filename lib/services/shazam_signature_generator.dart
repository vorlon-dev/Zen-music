import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Shazam DejaVu signature generator — Dart port of Echo's
/// ShazamSignatureGenerator (the dejavu-fingerprinter algorithm).
/// Input: 16-bit little-endian mono PCM at 16 kHz.
/// Output: "data:audio/vnd.shazam.sig;base64,..." signature URI.
class ShazamSignatureGenerator {
  ShazamSignatureGenerator._();

  static const int sampleRate = 16000;
  static const int _fftSize = 2048;
  static const int _fftOutputSize = _fftSize ~/ 2 + 1; // 1025
  static const int _maxPeaks = 255;
  static const double _maxTimeSeconds = 12.0;
  static const int _ringBufSize = 256;

  static Float64List? _hanning;

  static Float64List get _h {
    var h = _hanning;
    if (h == null) {
      h = Float64List(_fftSize);
      for (var i = 0; i < _fftSize; i++) {
        // Note: denominator is 2049, not fftSize — matches the reference.
        h[i] = 0.5 * (1.0 - cos(2 * pi * (i + 1) / 2049.0));
      }
      _hanning = h;
    }
    return h;
  }

  /// Generates a signature from 16-bit LE PCM bytes.
  static String fromI16(Uint8List samples) {
    if (samples.length < 2 || samples.length % 2 != 0) {
      throw ArgumentError(
          'samples must be a non-empty byte array with even length (16-bit PCM)');
    }
    final pcm = Int16List(samples.length ~/ 2);
    final bd = ByteData.sublistView(samples);
    for (var i = 0; i < pcm.length; i++) {
      pcm[i] = bd.getInt16(i * 2, Endian.little);
    }
    return _State().process(pcm);
  }
}

class _FrequencyPeak {
  const _FrequencyPeak({
    required this.fftPassNumber,
    required this.peakMagnitude,
    required this.correctedPeakFrequencyBin,
  });
  final int fftPassNumber;
  final int peakMagnitude;
  final int correctedPeakFrequencyBin;
}

class _State {
  static const int _fftSize = ShazamSignatureGenerator._fftSize;
  static const int _fftOutputSize = ShazamSignatureGenerator._fftOutputSize;
  static const int _ringBufSize = ShazamSignatureGenerator._ringBufSize;

  final Int32List _samplesRing = Int32List(_fftSize);
  int _samplesPos = 0;

  final List<Float64List> _fftOutputs =
  List.generate(_ringBufSize, (_) => Float64List(_fftOutputSize));
  int _fftPos = 0;
  // Parity with the reference implementation (incremented, never read).
  // ignore: unused_field
  int _fftNumWritten = 0;

  final List<Float64List> _spreadFfts =
  List.generate(_ringBufSize, (_) => Float64List(_fftOutputSize));
  int _spreadPos = 0;
  int _spreadNumWritten = 0;

  int _numSamples = 0;

  final List<List<_FrequencyPeak>> _bandPeaks =
  List.generate(4, (_) => <_FrequencyPeak>[]);
  int _totalPeaks = 0;

  String process(Int16List pcm) {
    var offset = 0;
    while (offset + 128 <= pcm.length) {
      final elapsedSec = _numSamples / ShazamSignatureGenerator.sampleRate;
      if (elapsedSec >= ShazamSignatureGenerator._maxTimeSeconds &&
          _totalPeaks >= ShazamSignatureGenerator._maxPeaks) {
        break;
      }
      _numSamples += 128;
      _feedSamples(pcm, offset, 128);
      _doFft();
      _doPeakSpreadingAndRecognition();
      offset += 128;
    }
    return _encodeSignature();
  }

  void _feedSamples(Int16List pcm, int start, int count) {
    for (var k = start; k < start + count; k++) {
      _samplesRing[_samplesPos] = pcm[k];
      _samplesPos = (_samplesPos + 1) % _fftSize;
    }
  }

  void _doFft() {
    final h = ShazamSignatureGenerator._h;
    final windowed = Float64List(_fftSize);
    for (var i = 0; i < _fftSize; i++) {
      windowed[i] =
          _samplesRing[(_samplesPos + i) % _fftSize].toDouble() * h[i];
    }
    final result = _computeRfft(windowed);
    _fftOutputs[_fftPos].setAll(0, result);
    _fftPos = (_fftPos + 1) % _ringBufSize;
    _fftNumWritten++;
  }

  void _doPeakSpreadingAndRecognition() {
    _doPeakSpreading();
    if (_spreadNumWritten >= 47) {
      _doPeakRecognition();
    }
  }

  void _doPeakSpreading() {
    final lastFftIdx = (_fftPos - 1 + _ringBufSize) % _ringBufSize;
    final spread = Float64List.fromList(_fftOutputs[lastFftIdx]);

    for (var pos = 0; pos < _fftOutputSize - 2; pos++) {
      final a = spread[pos], b = spread[pos + 1], c = spread[pos + 2];
      final m = a > b ? a : b;
      spread[pos] = m > c ? m : c;
    }

    for (var pos = 0; pos < _fftOutputSize; pos++) {
      var maxVal = spread[pos];
      for (final offset in const [-1, -3, -6]) {
        final idx =
            ((_spreadPos + offset) % _ringBufSize + _ringBufSize) % _ringBufSize;
        final oldVal = _spreadFfts[idx][pos];
        if (oldVal > maxVal) maxVal = oldVal;
        _spreadFfts[idx][pos] = maxVal;
      }
    }

    _spreadFfts[_spreadPos].setAll(0, spread);
    _spreadPos = (_spreadPos + 1) % _ringBufSize;
    _spreadNumWritten++;
  }

  void _doPeakRecognition() {
    final fftMinus46 =
    _fftOutputs[(_fftPos - 46 + _ringBufSize * 2) % _ringBufSize];
    final spreadMinus49 =
    _spreadFfts[(_spreadPos - 49 + _ringBufSize * 2) % _ringBufSize];

    const otherOffsets = [
      -53, -45, 165, 172, 179, 186, 193, 200, 214, 221, 228, 235, 242, 249,
    ];

    for (var binPos = 10; binPos < _fftOutputSize - 8; binPos++) {
      final fftVal = fftMinus46[binPos];
      if (fftVal < 1.0 / 64.0 || fftVal < spreadMinus49[binPos]) continue;

      var maxNeighborSpread49 = 0.0;
      for (final neighborOffset in const [-10, -7, -4, -3, 1, 2, 5, 8]) {
        final v = spreadMinus49[binPos + neighborOffset];
        if (v > maxNeighborSpread49) maxNeighborSpread49 = v;
      }
      if (fftVal <= maxNeighborSpread49) continue;

      var maxNeighborOther = maxNeighborSpread49;
      for (final otherOffset in otherOffsets) {
        final spreadIdx =
            ((_spreadPos + otherOffset) % _ringBufSize + _ringBufSize) %
                _ringBufSize;
        final v = _spreadFfts[spreadIdx][binPos - 1];
        if (v > maxNeighborOther) maxNeighborOther = v;
      }
      if (fftVal <= maxNeighborOther) continue;

      final fftNumber = _spreadNumWritten - 46;

      final peakMag = log(max(1.0 / 64.0, fftVal)) * 1477.3 + 6144;
      final peakMagBefore =
          log(max(1.0 / 64.0, fftMinus46[binPos - 1])) * 1477.3 + 6144;
      final peakMagAfter =
          log(max(1.0 / 64.0, fftMinus46[binPos + 1])) * 1477.3 + 6144;

      final peakVariation1 = peakMag * 2 - peakMagBefore - peakMagAfter;
      final peakVariation2 = (peakMagAfter - peakMagBefore) * 32 / peakVariation1;

      final correctedBin = binPos * 64.0 + peakVariation2;
      final frequencyHz = correctedBin * (16000.0 / 2.0 / 1024.0 / 64.0);

      int band;
      if (frequencyHz < 250.0) {
        continue;
      } else if (frequencyHz < 520.0) {
        band = 0; // 250-520
      } else if (frequencyHz < 1450.0) {
        band = 1; // 520-1450
      } else if (frequencyHz < 3500.0) {
        band = 2; // 1450-3500
      } else if (frequencyHz <= 5500.0) {
        band = 3; // 3500-5500
      } else {
        continue;
      }

      _bandPeaks[band].add(_FrequencyPeak(
        fftPassNumber: fftNumber,
        peakMagnitude: peakMag.toInt(),
        correctedPeakFrequencyBin: correctedBin.toInt(),
      ));
      _totalPeaks++;
    }
  }

  String _encodeSignature() {
    final contents = BytesBuilder();

    for (var bandId = 0; bandId <= 3; bandId++) {
      final peaks = _bandPeaks[bandId];
      if (peaks.isEmpty) continue;

      final peakBuf = BytesBuilder();
      var prevFftPassNumber = 0;

      for (final peak in peaks) {
        final diff = peak.fftPassNumber - prevFftPassNumber;
        if (diff >= 255) {
          peakBuf.addByte(0xFF);
          _writeLe32(peakBuf, peak.fftPassNumber);
          prevFftPassNumber = peak.fftPassNumber;
        }
        peakBuf.addByte(peak.fftPassNumber - prevFftPassNumber);
        _writeLe16(peakBuf, peak.peakMagnitude);
        _writeLe16(peakBuf, peak.correctedPeakFrequencyBin);
        prevFftPassNumber = peak.fftPassNumber;
      }

      final peakBytes = peakBuf.takeBytes();

      _writeLe32(contents, 0x60030040 + bandId);
      _writeLe32(contents, peakBytes.length);
      contents.add(peakBytes);

      final padBytes = (4 - peakBytes.length % 4) % 4;
      for (var i = 0; i < padBytes; i++) {
        contents.addByte(0);
      }
    }

    final contentsBytes = contents.takeBytes();
    final sizeMinusHeader = contentsBytes.length + 8;
    final samplesAndOffset =
    (_numSamples + ShazamSignatureGenerator.sampleRate * 0.24).toInt();

    // 48-byte header.
    final header = BytesBuilder();
    _writeLe32(header, 0xcafe2580);
    _writeLe32(header, 0); // CRC placeholder, patched below
    _writeLe32(header, sizeMinusHeader);
    _writeLe32(header, 0x94119c00);
    _writeLe32(header, 0);
    _writeLe32(header, 0);
    _writeLe32(header, 0);
    _writeLe32(header, 3 << 27);
    _writeLe32(header, 0);
    _writeLe32(header, 0);
    _writeLe32(header, samplesAndOffset);
    _writeLe32(header, (15 << 19) + 0x40000);
    final headerBytes = header.takeBytes();

    final full = BytesBuilder();
    full.add(headerBytes);
    _writeLe32(full, 0x40000000);
    _writeLe32(full, contentsBytes.length + 8);
    full.add(contentsBytes);

    final fullBytes = full.takeBytes();

    // CRC32 over everything except the first 8 bytes.
    final crc = _Crc32();
    crc.update(fullBytes, 8, fullBytes.length);
    final crcValue = crc.value & 0xFFFFFFFF;

    fullBytes[4] = crcValue & 0xFF;
    fullBytes[5] = (crcValue >>> 8) & 0xFF;
    fullBytes[6] = (crcValue >>> 16) & 0xFF;
    fullBytes[7] = (crcValue >>> 24) & 0xFF;

    final b64 = base64Encode(fullBytes);
    return 'data:audio/vnd.shazam.sig;base64,$b64';
  }

  Float64List _computeRfft(Float64List windowed) {
    const n = _fftSize;
    final re = Float64List(n);
    final im = Float64List(n);
    re.setAll(0, windowed);

    // Bit-reversal permutation.
    var j = 0;
    for (var i = 1; i < n; i++) {
      var bit = n >>> 1;
      while (j & bit != 0) {
        j ^= bit;
        bit = bit >>> 1;
      }
      j ^= bit;
      if (i < j) {
        var tmp = re[i];
        re[i] = re[j];
        re[j] = tmp;
        tmp = im[i];
        im[i] = im[j];
        im[j] = tmp;
      }
    }

    var len = 2;
    while (len <= n) {
      final halfLen = len >> 1;
      final ang = -pi / halfLen;
      final wBaseRe = cos(ang);
      final wBaseIm = sin(ang);
      var i = 0;
      while (i < n) {
        var wRe = 1.0;
        var wIm = 0.0;
        for (var k = 0; k < halfLen; k++) {
          final u = i + k;
          final v = u + halfLen;
          final evenRe = re[u], evenIm = im[u];
          final oddRe = re[v] * wRe - im[v] * wIm;
          final oddIm = re[v] * wIm + im[v] * wRe;
          re[u] = evenRe + oddRe;
          im[u] = evenIm + oddIm;
          re[v] = evenRe - oddRe;
          im[v] = evenIm - oddIm;
          final newWRe = wRe * wBaseRe - wIm * wBaseIm;
          wIm = wRe * wBaseIm + wIm * wBaseRe;
          wRe = newWRe;
        }
        i += len;
      }
      len = len << 1;
    }

    const scaleFactor = 1.0 / (1 << 17);
    const minVal = 1e-10;
    final out = Float64List(_fftOutputSize);
    for (var idx = 0; idx < _fftOutputSize; idx++) {
      final r = re[idx], img = im[idx];
      final mag = (r * r + img * img) * scaleFactor;
      out[idx] = mag < minVal ? minVal : mag;
    }
    return out;
  }
}

void _writeLe32(BytesBuilder out, int value) {
  final v = value & 0xFFFFFFFF;
  out.addByte(v & 0xFF);
  out.addByte((v >>> 8) & 0xFF);
  out.addByte((v >>> 16) & 0xFF);
  out.addByte((v >>> 24) & 0xFF);
}

void _writeLe16(BytesBuilder out, int value) {
  final v = value & 0xFFFF;
  out.addByte(v & 0xFF);
  out.addByte((v >>> 8) & 0xFF);
}

/// Standard CRC-32 (IEEE, reflected, poly 0xEDB88320) — matches
/// java.util.zip.CRC32.
class _Crc32 {
  static final List<int> _table = _generateTable();
  int _value = 0xFFFFFFFF;

  static List<int> _generateTable() {
    final table = List<int>.filled(256, 0);
    for (var i = 0; i < 256; i++) {
      var c = i;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      }
      table[i] = c & 0xFFFFFFFF;
    }
    return table;
  }

  /// [start] inclusive, [end] exclusive.
  void update(List<int> bytes, int start, int end) {
    for (var i = start; i < end; i++) {
      _value = _table[(_value ^ bytes[i]) & 0xFF] ^ (_value >>> 8);
    }
  }

  int get value => (_value ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}