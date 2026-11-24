// ZenMusic · vorlon-dev
//
// SP-78 · Offline AI remix analyzer (Android).
//
// Decodes an audio file to mono PCM via MediaCodec, then:
//   1. if an ONNX model is installed, computes a log-mel front-end whose
//      shape follows the model's own declared input tensor (auto), runs
//      the model with ONNX Runtime and maps the output to BPM using the
//      Dart-provided contract (softmax bins or direct regression);
//   2. otherwise — or when the model path fails for any reason — falls
//      back to a pure DSP tempo estimate (onset autocorrelation), so the
//      feature always returns an answer offline.
//
// Everything runs on a background thread; the channel handler posts the
// result back to the platform thread (same pattern as zen/dsp).

package com.zen.music.zenmusic.ai

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import ai.onnxruntime.TensorInfo
import java.io.File
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin

object AiRemixAnalyzer {

    private val env: OrtEnvironment by lazy { OrtEnvironment.getEnvironment() }
    private val sessions = ConcurrentHashMap<String, OrtSession>()

    private const val FFT_WIN = 1024
    private const val FFT_HOP = 512

    /**
     * @param contract map from Dart: sampleRate, melBins (0=auto), frames
     *                 (0=auto), outputKind ('softmax_bins'|'regression'),
     *                 bins, minBpm, maxBpm, maxSeconds.
     * @return map with 'bpm' (Double) and 'source' ("model"|"dsp").
     */
    fun analyze(path: String, modelPath: String?, contract: Map<String, Any?>): Map<String, Any?> {
        val sampleRate = (contract["sampleRate"] as? Number)?.toInt()?.coerceIn(8000, 48000) ?: 16000
        val maxSeconds = (contract["maxSeconds"] as? Number)?.toDouble()?.coerceIn(5.0, 120.0) ?: 45.0

        val pcm = decodeToMono(path, sampleRate, maxSeconds)
        if (pcm == null || pcm.size < FFT_WIN * 8) {
            return mapOf("bpm" to 0.0, "source" to "dsp")
        }

        if (modelPath != null && File(modelPath).exists()) {
            try {
                val bpm = runModel(modelPath, pcm, sampleRate, contract)
                if (bpm != null && bpm > 0.0) {
                    return mapOf("bpm" to bpm, "source" to "model")
                }
            } catch (_: Throwable) {
                // Model path failed (bad file / shape mismatch / runtime
                // hiccup) — silently degrade to the DSP estimate.
            }
        }

        val bpm = dspTempo(pcm, sampleRate)
        return mapOf("bpm" to bpm, "source" to "dsp")
    }

    // ------------------------------------------------------------------
    // ONNX path
    // ------------------------------------------------------------------

    private fun runModel(
        modelPath: String,
        pcm: FloatArray,
        sampleRate: Int,
        contract: Map<String, Any?>
    ): Double? {
        val session = sessions.getOrPut(modelPath) {
            env.createSession(modelPath, OrtSession.SessionOptions())
        }
        val inName = session.inputNames.firstOrNull() ?: return null
        val nodeInfo = session.inputInfo[inName]
        val shape: LongArray? = (nodeInfo?.info as? TensorInfo)?.shape

        // Auto-shape: prefer the model's own static dims; fall back to
        // the contract, then to sensible defaults (96 mels / 1291 frames).
        var melBins = (contract["melBins"] as? Number)?.toInt() ?: 0
        var frames = (contract["frames"] as? Number)?.toInt() ?: 0
        if (shape != null && shape.size >= 2) {
            val d2 = shape[shape.size - 2]
            val d3 = shape[shape.size - 1]
            if (melBins <= 0 && d2 > 0) melBins = d2.toInt()
            if (frames <= 0 && d3 > 0) frames = d3.toInt()
        }
        if (melBins <= 0) melBins = 96
        if (frames <= 0) frames = 1291
        melBins = melBins.coerceIn(8, 512)
        frames = frames.coerceIn(16, 4096)

        val spec = melSpectrogram(pcm, sampleRate, melBins, frames)
        if (spec == null) return null

        val tensor = OnnxTensor.createTensor(
            env, FloatBuffer.wrap(spec), longArrayOf(1, 1, melBins.toLong(), frames.toLong())
        )
        tensor.use {
            session.run(mapOf(inName to it)).use { result ->
                val values = flattenFloats(result.get(0).value)
                if (values.isEmpty()) return null
                val kind = (contract["outputKind"] as? String) ?: "softmax_bins"
                val bins = (contract["bins"] as? Number)?.toInt()?.coerceAtLeast(2) ?: 256
                val minBpm = (contract["minBpm"] as? Number)?.toDouble() ?: 30.0
                val maxBpm = (contract["maxBpm"] as? Number)?.toDouble() ?: 286.0
                return when (kind) {
                    "regression" -> values[0].toDouble()
                    else -> {
                        var best = 0
                        for (i in 1 until values.size) {
                            if (values[i] > values[best]) best = i
                        }
                        val span = maxBpm - minBpm
                        minBpm + span * best / max(1, bins - 1)
                    }
                }
            }
        }
    }

    /** Unwrap nested float arrays ([1][B] or [1][1][B] …) to a flat row. */
    private fun flattenFloats(v: Any?): FloatArray {
        var cur: Any? = v
        var depth = 0
        while (cur is Array<*> && depth < 4) {
            if (cur.isEmpty()) return FloatArray(0)
            cur = cur[0]
            depth++
        }
        return when (cur) {
            is FloatArray -> cur
            is DoubleArray -> FloatArray(cur.size) { cur[it].toFloat() }
            is Float -> floatArrayOf(cur)
            is Number -> floatArrayOf(cur.toFloat())
            else -> FloatArray(0)
        }
    }

    // ------------------------------------------------------------------
    // Log-mel front-end
    // ------------------------------------------------------------------

    private val melCache = ConcurrentHashMap<String, Array<FloatArray>>()

    private fun melFilterbank(sampleRate: Int, melBins: Int): Array<FloatArray> {
        val key = "$sampleRate:$melBins:$FFT_WIN"
        melCache[key]?.let { return it }

        val nBins = FFT_WIN / 2
        fun hz2mel(hz: Double): Double = 2595.0 * kotlin.math.log10(1.0 + hz / 700.0)
        fun mel2hz(mel: Double): Double = 700.0 * (10.0.pow(mel / 2595.0) - 1.0)

        val melMin = hz2mel(20.0)
        val melMax = hz2mel(sampleRate / 2.0)
        val points = DoubleArray(melBins + 2) { i ->
            mel2hz(melMin + (melMax - melMin) * i / (melBins + 1))
        }
        val binHz = sampleRate.toDouble() / FFT_WIN

        val bank = Array(melBins) { FloatArray(nBins) }
        for (m in 0 until melBins) {
            val low = points[m]
            val center = points[m + 1]
            val high = points[m + 2]
            for (b in 0 until nBins) {
                val f = binHz * b
                if (f > low && f < high) {
                    bank[m][b] = if (f <= center) {
                        ((f - low) / (center - low)).toFloat()
                    } else {
                        ((high - f) / (high - center)).toFloat()
                    }
                }
            }
        }
        melCache[key] = bank
        return bank
    }

    /** Returns FloatArray of size melBins*frames laid out as [mel][frame]. */
    private fun melSpectrogram(
        pcm: FloatArray,
        sampleRate: Int,
        melBins: Int,
        frames: Int
    ): FloatArray? {
        if (pcm.size < FFT_WIN) return null
        val bank = melFilterbank(sampleRate, melBins)
        val nBins = FFT_WIN / 2

        val window = DoubleArray(FFT_WIN) { i ->
            0.5 * (1.0 - cos(2.0 * PI * i / (FFT_WIN - 1)))
        }
        val fftRe = DoubleArray(FFT_WIN)
        val fftIm = DoubleArray(FFT_WIN)
        val mag = DoubleArray(nBins)

        val spec = FloatArray(melBins * frames)
        val available = if (pcm.size >= FFT_WIN) (pcm.size - FFT_WIN) / FFT_HOP + 1 else 0

        for (f in 0 until frames) {
            if (f >= available) break // remaining frames stay zero-padded
            val off = f * FFT_HOP
            for (i in 0 until FFT_WIN) {
                fftRe[i] = pcm[off + i] * window[i]
                fftIm[i] = 0.0
            }
            fft(fftRe, fftIm)
            for (b in 0 until nBins) {
                mag[b] = fftRe[b] * fftRe[b] + fftIm[b] * fftIm[b]
            }
            for (m in 0 until melBins) {
                var e = 0.0
                val weights = bank[m]
                for (b in 0 until nBins) {
                    val w = weights[b]
                    if (w > 0f) e += w * mag[b]
                }
                spec[m * frames + f] = kotlin.math.ln(e + 1e-6).toFloat()
            }
        }
        return spec
    }

    // ------------------------------------------------------------------
    // Iterative radix-2 FFT (in-place, e-maxx style)
    // ------------------------------------------------------------------

    private fun fft(re: DoubleArray, im: DoubleArray) {
        val n = re.size
        // bit reversal permutation
        var j = 0
        for (i in 1 until n) {
            var bit = n shr 1
            while (j and bit != 0) {
                j = j xor bit
                bit = bit shr 1
            }
            j = j or bit
            if (i < j) {
                val tr = re[i]; re[i] = re[j]; re[j] = tr
                val ti = im[i]; im[i] = im[j]; im[j] = ti
            }
        }
        var len = 2
        while (len <= n) {
            val ang = -2.0 * PI / len
            val stepRe = cos(ang)
            val stepIm = sin(ang)
            val half = len shr 1
            var base = 0
            while (base < n) {
                var wRe = 1.0
                var wIm = 0.0
                for (k in 0 until half) {
                    val a = base + k
                    val b = a + half
                    val tRe = re[b] * wRe - im[b] * wIm
                    val tIm = re[b] * wIm + im[b] * wRe
                    re[b] = re[a] - tRe
                    im[b] = im[a] - tIm
                    re[a] += tRe
                    im[a] += tIm
                    val nRe = wRe * stepRe - wIm * stepIm
                    wIm = wRe * stepIm + wIm * stepRe
                    wRe = nRe
                }
                base += len
            }
            len = len shl 1
        }
    }

    // ------------------------------------------------------------------
    // DSP fallback — onset autocorrelation tempo, 60–190 BPM
    // ------------------------------------------------------------------

    private fun dspTempo(x: FloatArray, sampleRate: Int): Double {
        val nFrames = (x.size - FFT_WIN) / FFT_HOP
        if (nFrames < 64) return 0.0

        val energy = DoubleArray(nFrames)
        for (f in 0 until nFrames) {
            var e = 0.0
            val off = f * FFT_HOP
            for (i in 0 until FFT_WIN) {
                val v = x[off + i].toDouble()
                e += v * v
            }
            energy[f] = e
        }
        val onset = DoubleArray(nFrames)
        for (f in 1 until nFrames) {
            val d = energy[f] - energy[f - 1]
            onset[f] = if (d > 0) d else 0.0
        }
        var mean = 0.0
        for (v in onset) mean += v
        mean /= nFrames
        if (mean <= 0.0) return 0.0
        for (i in onset.indices) onset[i] = onset[i] / mean

        val fps = sampleRate.toDouble() / FFT_HOP
        var bestBpm = 0.0
        var bestScore = -1.0
        var bpm = 60.0
        while (bpm <= 190.0) {
            val lag = (fps * 60.0 / bpm).roundToInt()
            if (lag >= 2 && (nFrames - lag) > 8) {
                var s = 0.0
                for (f in 0 until nFrames - lag) s += onset[f] * onset[f + lag]
                s /= (nFrames - lag)
                val lag2 = lag / 2
                if (lag2 >= 2 && (nFrames - lag2) > 8) {
                    var s2 = 0.0
                    for (f in 0 until nFrames - lag2) s2 += onset[f] * onset[f + lag2]
                    s2 /= (nFrames - lag2)
                    s += 0.5 * s2
                }
                if (s > bestScore) {
                    bestScore = s
                    bestBpm = bpm
                }
            }
            bpm += 0.5
        }
        return bestBpm
    }

    // ------------------------------------------------------------------
    // MediaCodec decode → mono FloatArray @ target sample rate
    // ------------------------------------------------------------------

    private fun decodeToMono(path: String, targetSr: Int, maxSeconds: Double): FloatArray? {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(path)
            var trackIndex = -1
            var format: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                val mime = f.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    trackIndex = i
                    format = f
                    break
                }
            }
            if (trackIndex < 0 || format == null) return null
            val mime = format.getString(MediaFormat.KEY_MIME)!!
            val srcSr = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                .coerceIn(1, 8)
            extractor.selectTrack(trackIndex)

            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(format, null, null, 0)
            codec.start()

            val src = ArrayList<Float>(1024 * 256)
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            val maxSrcSamples = (maxSeconds * srcSr * channels).toLong()

            while (!outputDone && src.size < maxSrcSamples) {
                if (!inputDone) {
                    val idx = codec.dequeueInputBuffer(10_000)
                    if (idx >= 0) {
                        val buf = codec.getInputBuffer(idx)
                        if (buf == null) {
                            codec.queueInputBuffer(idx, 0, 0, 0, 0)
                        } else {
                            buf.clear()
                            val size = extractor.readSampleData(buf, 0)
                            if (size < 0) {
                                codec.queueInputBuffer(
                                    idx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                )
                                inputDone = true
                            } else {
                                codec.queueInputBuffer(
                                    idx, 0, size, extractor.sampleTime, 0
                                )
                                extractor.advance()
                            }
                        }
                    }
                }
                val outIdx = codec.dequeueOutputBuffer(info, 10_000)
                when {
                    outIdx >= 0 -> {
                        val outBuf = codec.getOutputBuffer(outIdx)
                        if (outBuf != null && info.size > 0) {
                            outBuf.order(ByteOrder.nativeOrder())
                            val outFormat = codec.outputFormat
                            val isFloat = try {
                                outFormat.getInteger(
                                    MediaFormat.KEY_PCM_ENCODING
                                ) == AudioFormat.ENCODING_PCM_FLOAT
                            } catch (_: Exception) {
                                false // key absent → assume 16-bit PCM
                            }
                            if (isFloat) {
                                val fb = outBuf.asFloatBuffer()
                                val n = fb.remaining() / channels
                                for (i in 0 until n) {
                                    var acc = 0f
                                    for (c in 0 until channels) acc += fb.get(i * channels + c)
                                    src.add(acc / channels)
                                }
                            } else {
                                val sb = outBuf.asShortBuffer()
                                val n = sb.remaining() / channels
                                for (i in 0 until n) {
                                    var acc = 0f
                                    for (c in 0 until channels) {
                                        acc += sb.get(i * channels + c) / 32768f
                                    }
                                    src.add(acc / channels)
                                }
                            }
                        }
                        codec.releaseOutputBuffer(outIdx, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            outputDone = true
                        }
                    }
                    outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        // new output format picked up on the next buffer
                    }
                    else -> {
                        // INFO_TRY_AGAIN_LATER — keep pumping
                    }
                }
            }

            val mono = src.toFloatArray()
            return resample(mono, srcSr, targetSr)
        } catch (_: Throwable) {
            return null
        } finally {
            try {
                codec?.stop()
            } catch (_: Throwable) {}
            try {
                codec?.release()
            } catch (_: Throwable) {}
            try {
                extractor.release()
            } catch (_: Throwable) {}
        }
    }

    /** Linear-interpolation resampler — good enough for tempo analysis. */
    private fun resample(x: FloatArray, fromSr: Int, toSr: Int): FloatArray {
        if (fromSr == toSr || x.isEmpty()) return x
        val outLen = (x.size.toLong() * toSr / fromSr).toInt()
        if (outLen <= 0) return FloatArray(0)
        val out = FloatArray(outLen)
        val ratio = fromSr.toDouble() / toSr
        var pos = 0.0
        for (i in 0 until outLen) {
            val i0 = pos.toInt()
            val i1 = min(i0 + 1, x.size - 1)
            val frac = pos - i0
            out[i] = (x[i0] * (1.0 - frac) + x[i1] * frac).toFloat()
            pos += ratio
        }
        return out
    }
}
