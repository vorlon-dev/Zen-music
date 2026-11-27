// ZenMusic · Spatial audio ("6D" / "16D"): on-device orbiting-sound effect for headphones.
@file:OptIn(androidx.media3.common.util.UnstableApi::class)

package com.zen.music.zenmusic.lossless

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

/**
 * Shared by every player instance.
 * 0 = off, 6 = 6D, 8 = 8D, 16 = 16D, 18 = 18D, 100 = Surround (far-away concert-hall feel).
 */
object SpatialAudioState {
    @Volatile
    var mode: Int = 0

    /** 0..1 reverb-only "room" used by Slowed + Reverb when no spatial mode is chosen. */
    @Volatile
    var room: Float = 0f
}

/**
 * Moves the sound in a slow circle around the listener.
 *
 *  - pan (equal-power) follows the orbit,
 *  - the far ear hears the sound a fraction of a millisecond later and slightly darker
 *    (interaural time / level difference),
 *  - 8D is the classic wide auto-pan, 18D the most intense orbit,
 *  - Surround does not orbit: it keeps the full stereo width and pushes the sound away
 *    (darker, quieter direct sound, pre-delayed big room) so it feels like a distant stage,
 *  - 16D / 18D add a front/back illusion (the sound gets duller and quieter behind you),
 *    orbits faster and adds a bigger room,
 *  - the original stereo width is kept at a low level so it never collapses to mono,
 *  - a small stereo room (two combs + all-pass per ear) gives the sense of space.
 *
 * Stereo 16-bit / float only; anything else is left untouched. Switching modes crossfades
 * every parameter, so there are no clicks. Best on headphones.
 */
@androidx.annotation.OptIn(UnstableApi::class)
class SpatialAudioProcessor : BaseAudioProcessor() {

    private class Comb(val buf: FloatArray) {
        var i = 0
        fun run(x: Float, fb: Float): Float {
            val y = buf[i]
            buf[i] = x + y * fb
            if (++i == buf.size) i = 0
            return y
        }
    }

    private class AllPass(val buf: FloatArray) {
        var i = 0
        fun run(x: Float): Float {
            val b = buf[i]
            buf[i] = x + b * 0.5f
            if (++i == buf.size) i = 0
            return b - x
        }
    }

    private var encoding = C.ENCODING_INVALID
    private var sr = 44100f

    // inter-aural delay line (per ear)
    private var dl = FloatArray(0)
    private var dr = FloatArray(0)
    private var w = 0
    private var maxItd = 0f

    private var combL1 = Comb(FloatArray(1)); private var combL2 = Comb(FloatArray(1))
    private var combR1 = Comb(FloatArray(1)); private var combR2 = Comb(FloatArray(1))
    private var apL = AllPass(FloatArray(1)); private var apR = AllPass(FloatArray(1))

    private var phase = 0f
    private var lpl = 0f
    private var lpr = 0f

    // smoothed parameters
    private var amount = 0f
    private var omega = 0f
    private var depth = 0f
    private var wet = 0f
    private var width = 0f
    private var far = 0f
    private var plain = 0f // 1 = keep the original stereo untouched (room-only)
    private var preDelay = 0f // seconds

    private var pre = FloatArray(0)
    private var pw = 0
    private var lpd = 0f // darkening of the direct sound (Surround)

    private var outL = 0f
    private var outR = 0f

    override fun onConfigure(
        inputAudioFormat: AudioProcessor.AudioFormat,
    ): AudioProcessor.AudioFormat {
        val ok = inputAudioFormat.channelCount == 2 &&
            (inputAudioFormat.encoding == C.ENCODING_PCM_16BIT ||
                inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT)
        if (!ok) return AudioProcessor.AudioFormat.NOT_SET
        encoding = inputAudioFormat.encoding
        sr = inputAudioFormat.sampleRate.toFloat()
        val k = sr / 44100f
        maxItd = sr * 0.0006f // 0.6 ms
        dl = FloatArray((maxItd).toInt() + 4)
        dr = FloatArray((maxItd).toInt() + 4)
        combL1 = Comb(FloatArray((1557 * k).toInt()))
        combL2 = Comb(FloatArray((1617 * k).toInt()))
        combR1 = Comb(FloatArray((1491 * k).toInt()))
        combR2 = Comb(FloatArray((1422 * k).toInt()))
        apL = AllPass(FloatArray((225 * k).toInt()))
        apR = AllPass(FloatArray((248 * k).toInt()))
        pre = FloatArray((sr * 0.04f).toInt() + 4)
        pw = 0; lpd = 0f
        w = 0
        return inputAudioFormat
    }

    override fun onFlush() {
        dl.fill(0f); dr.fill(0f); pre.fill(0f); lpd = 0f
        listOf(combL1, combL2, combR1, combR2).forEach { it.buf.fill(0f) }
        apL.buf.fill(0f); apR.buf.fill(0f)
        lpl = 0f; lpr = 0f
    }

    private fun readDelayed(buf: FloatArray, widx: Int, delay: Float): Float {
        val n = buf.size
        val d = delay.coerceIn(0f, (n - 2).toFloat())
        val di = d.toInt()
        val frac = d - di
        var i0 = widx - di; if (i0 < 0) i0 += n
        var i1 = i0 - 1; if (i1 < 0) i1 += n
        return buf[i0] * (1f - frac) + buf[i1] * frac
    }

    /** One stereo frame in (-1..1) -> outL/outR. */
    private fun frame(l: Float, r: Float, mode: Int) {
        val target = if (mode == 0) 0f else 1f
        amount += (target - amount).coerceIn(-1f / (sr * 0.3f), 1f / (sr * 0.3f))

        // per-mode targets: period (s, 0 = no orbit), depth, wet, width, far, pre-delay (s)
        val tPeriod: Double; val tDepth: Float; val tWet: Float
        val tWidth: Float; val tFar: Float; val tPre: Float
        when (mode) {
            6 -> { tPeriod = 10.0; tDepth = 0f; tWet = 0.14f; tWidth = 0.35f; tFar = 0f; tPre = 0f }
            8 -> { tPeriod = 8.0; tDepth = 0f; tWet = 0.10f; tWidth = 0.30f; tFar = 0f; tPre = 0f }
            16 -> { tPeriod = 5.0; tDepth = 1f; tWet = 0.28f; tWidth = 0.35f; tFar = 0f; tPre = 0f }
            18 -> { tPeriod = 3.5; tDepth = 1f; tWet = 0.38f; tWidth = 0.50f; tFar = 0f; tPre = 0f }
            200 -> { tPeriod = 0.0; tDepth = 0f; tWet = 0.40f * SpatialAudioState.room.coerceIn(0f, 1f); tWidth = 1.0f; tFar = 0f; tPre = 0.015f }
            100 -> { tPeriod = 0.0; tDepth = 0f; tWet = 0.45f; tWidth = 1.0f; tFar = 1f; tPre = 0.025f }
            else -> { tPeriod = 10.0; tDepth = 0f; tWet = 0f; tWidth = 0.35f; tFar = 0f; tPre = 0f }
        }
        val tPlain = if (mode == 200) 1f else 0f
        val tOmega = if (tPeriod > 0.0) (2.0 * PI / (tPeriod * sr)).toFloat() else 0f
        val sm = 1f / (sr * 0.5f)
        if (mode != 0) { // keep the old shape while fading out
            val k = sm * 4f
            omega += (tOmega - omega) * k
            depth += (tDepth - depth) * k
            wet += (tWet - wet) * k
            width += (tWidth - width) * k
            far += (tFar - far) * k
            plain += (tPlain - plain) * k
            preDelay += (tPre - preDelay) * k
        }
        phase += omega
        if (phase > (2.0 * PI).toFloat()) phase -= (2.0 * PI).toFloat()

        val pan = sin(phase) * (1f - far) // Surround: no orbit, centred
        val front = if (far > 0.5f) 1f else cos(phase)
        val back = (1f - front) * 0.5f // 0 in front .. 1 behind

        val mid = (l + r) * 0.5f
        val side = (l - r) * 0.5f

        val ang = (pan + 1f) * (PI.toFloat() / 4f)
        val g = 1.35f * (1f - 0.25f * back * depth) * (1f - 0.35f * far)
        val xl = mid * cos(ang) * g
        val xr = mid * sin(ang) * g

        dl[w] = xl; dr[w] = xr
        val yl = readDelayed(dl, w, max(pan, 0f) * maxItd)
        val yr = readDelayed(dr, w, max(-pan, 0f) * maxItd)
        w = if (w + 1 == dl.size) 0 else w + 1

        val dull = 1f - 0.5f * back * depth
        val aL = (1f - 0.7f * max(pan, 0f)) * dull
        val aR = (1f - 0.7f * max(-pan, 0f)) * dull
        lpl += aL * (yl - lpl)
        lpr += aR * (yr - lpr)

        // reverb send, pre-delayed in Surround so the room trails the direct sound
        pre[pw] = mid
        val send = readDelayed(pre, pw, preDelay * sr)
        pw = if (pw + 1 == pre.size) 0 else pw + 1
        val fb = 0.82f + 0.06f * far
        val rl = apL.run((combL1.run(send, fb) + combL2.run(send, fb)) * 0.5f)
        val rr = apR.run((combR1.run(send, fb) + combR2.run(send, fb)) * 0.5f)

        // Surround: darken the direct sound like distance does (air absorbs highs)
        val dark = 1f - 0.55f * far
        lpd += dark * ((lpl + lpr) * 0.5f - lpd)
        val dl2 = lpl + (lpd - lpl) * far
        val dr2 = lpr + (lpd - lpr) * far
        val baseL = dl2 + side * width
        val baseR = dr2 - side * width
        val pl = ((baseL + (l - baseL) * plain) + wet * rl) * 0.9f
        val pr = ((baseR + (r - baseR) * plain) + wet * rr) * 0.9f

        outL = l + (pl - l) * amount
        outR = r + (pr - r) * amount
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val size = inputBuffer.remaining()
        if (size == 0) return
        val out = replaceOutputBuffer(size)
        val chosen = SpatialAudioState.mode
        val mode = if (chosen != 0) chosen else if (SpatialAudioState.room > 0.001f) 200 else 0

        if (mode == 0 && amount < 0.001f) {
            amount = 0f
            out.put(inputBuffer) // off: straight copy
        } else if (encoding == C.ENCODING_PCM_16BIT) {
            while (inputBuffer.remaining() >= 4) {
                val l = inputBuffer.short / 32768f
                val r = inputBuffer.short / 32768f
                frame(l, r, mode)
                out.putShort((outL * 32767f).coerceIn(-32768f, 32767f).toInt().toShort())
                out.putShort((outR * 32767f).coerceIn(-32768f, 32767f).toInt().toShort())
            }
        } else {
            while (inputBuffer.remaining() >= 8) {
                val l = inputBuffer.float
                val r = inputBuffer.float
                frame(l, r, mode)
                out.putFloat(outL.coerceIn(-1f, 1f))
                out.putFloat(outR.coerceIn(-1f, 1f))
            }
        }
        out.flip()
    }
}
