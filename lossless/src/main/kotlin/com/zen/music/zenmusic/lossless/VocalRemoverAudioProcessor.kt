// ZenMusic · Sing mode: removes the centre-panned vocal on-device.
@file:OptIn(androidx.media3.common.util.UnstableApi::class)

package com.zen.music.zenmusic.lossless

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import kotlin.math.PI
import kotlin.math.exp

/** Shared by every player instance. 0 = off, 1 = voice fully removed. */
object VocalRemovalState {
    @Volatile
    var amount: Float = 0f
}

/**
 * Centre-channel cancellation with the bass kept. Vocals sit in the middle of the stereo image,
 * so subtracting the (high-passed) mid signal from both channels removes them while bass and
 * kick, which are also centred, stay because the mid is high-passed at ~150 Hz first.
 * Mono and unsupported formats are left alone (processor stays inactive for them).
 */
@androidx.annotation.OptIn(UnstableApi::class)
class VocalRemoverAudioProcessor : BaseAudioProcessor() {

    private var encoding = C.ENCODING_INVALID
    private var alpha = 0f
    private var lp = 0f
    private var current = 0f
    private var step = 0.001f

    override fun onConfigure(
        inputAudioFormat: AudioProcessor.AudioFormat,
    ): AudioProcessor.AudioFormat {
        val ok = inputAudioFormat.channelCount == 2 &&
            (inputAudioFormat.encoding == C.ENCODING_PCM_16BIT ||
                inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT)
        if (!ok) return AudioProcessor.AudioFormat.NOT_SET
        encoding = inputAudioFormat.encoding
        val sr = inputAudioFormat.sampleRate.toFloat()
        alpha = 1f - exp(-2.0 * PI * 150.0 / sr).toFloat()
        step = 1f / (sr * 0.05f) // 50 ms ramp = no clicks when toggled
        return inputAudioFormat
    }

    override fun onFlush() {
        lp = 0f
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val size = inputBuffer.remaining()
        if (size == 0) return
        val out = replaceOutputBuffer(size)
        val target = VocalRemovalState.amount.coerceIn(0f, 1f)

        if (target < 0.001f && current < 0.001f) {
            out.put(inputBuffer) // off: straight copy
        } else if (encoding == C.ENCODING_PCM_16BIT) {
            while (inputBuffer.remaining() >= 4) {
                current += (target - current).coerceIn(-step, step)
                val l = inputBuffer.short.toFloat()
                val r = inputBuffer.short.toFloat()
                val m = (l + r) * 0.5f
                lp += alpha * (m - lp)
                val hp = m - lp
                out.putShort((l - current * hp).coerceIn(-32768f, 32767f).toInt().toShort())
                out.putShort((r - current * hp).coerceIn(-32768f, 32767f).toInt().toShort())
            }
        } else {
            while (inputBuffer.remaining() >= 8) {
                current += (target - current).coerceIn(-step, step)
                val l = inputBuffer.float
                val r = inputBuffer.float
                val m = (l + r) * 0.5f
                lp += alpha * (m - lp)
                val hp = m - lp
                out.putFloat((l - current * hp).coerceIn(-1f, 1f))
                out.putFloat((r - current * hp).coerceIn(-1f, 1f))
            }
        }
        out.flip()
    }
}
