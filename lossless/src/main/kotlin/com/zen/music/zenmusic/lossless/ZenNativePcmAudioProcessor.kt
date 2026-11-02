// ZenMusic · vorlon-dev

@file:OptIn(androidx.media3.common.util.UnstableApi::class)

package com.zen.music.zenmusic.lossless

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import java.nio.ByteOrder

@androidx.annotation.OptIn(UnstableApi::class)
class ZenNativePcmAudioProcessor(private val engine: NativeAudioEngine) : BaseAudioProcessor() {

    /** Encoding handed to the engine; null = passthrough (no engine in path). */
    private var nativeEncoding: NativePcmEncoding? = null

    private var copyBuffer: ByteBuffer = AudioProcessor.EMPTY_BUFFER
    private var engineOutputBuffer: ByteBuffer = AudioProcessor.EMPTY_BUFFER

    /** True while PCM is actually flowing through the native engine. */
    val isEngineActive: Boolean
        get() = engine.isAvailable && nativeEncoding != null

    override fun onConfigure(
        inputAudioFormat: AudioProcessor.AudioFormat,
    ): AudioProcessor.AudioFormat {
        nativeEncoding = null
        copyBuffer = AudioProcessor.EMPTY_BUFFER
        engineOutputBuffer = AudioProcessor.EMPTY_BUFFER
        if (!engine.isAvailable) return inputAudioFormat
        // Scope: 16-bit sources only, engine output emitted as PCM16 (see
        // class doc). Everything else passes through bit-exact.
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) return inputAudioFormat
        if (inputAudioFormat.channelCount !in 1..2) return inputAudioFormat
        if (inputAudioFormat.sampleRate <= 0) return inputAudioFormat
        val configured = runCatching {
            // Output rate = input rate: no resampling in the path.
            engine.configureMediaProcessor(
                inputSampleRate = inputAudioFormat.sampleRate,
                outputSampleRate = inputAudioFormat.sampleRate,
                channelCount = inputAudioFormat.channelCount,
            )
        }.getOrDefault(false)
        if (!configured) return inputAudioFormat
        nativeEncoding = NativePcmEncoding.PCM_I16
        android.util.Log.i(
            "ZenLossless",
            "engine media path configured: ${inputAudioFormat.sampleRate}Hz/" +
                    "${inputAudioFormat.channelCount}ch PCM16",
        )
        return AudioProcessor.AudioFormat(
            inputAudioFormat.sampleRate,
            inputAudioFormat.channelCount,
            C.ENCODING_PCM_16BIT,
        )
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        if (nativeEncoding == null) {
            // Passthrough: bit-identical copy.
            val remaining = inputBuffer.remaining()
            if (remaining == 0) return
            val out = replaceOutputBuffer(remaining)
            out.put(inputBuffer)
            out.flip()
            return
        }
        val bytesPerFrame = inputAudioFormat.bytesPerFrame
        if (bytesPerFrame <= 0) {
            inputBuffer.position(inputBuffer.limit())
            return
        }
        val frameCount = inputBuffer.remaining() / bytesPerFrame
        if (frameCount == 0) {
            inputBuffer.position(inputBuffer.limit())
            return
        }
        val channels = inputAudioFormat.channelCount
        val originalPosition = inputBuffer.position()
        val inputByteCount = frameCount * bytesPerFrame
        val inputLimit = originalPosition + inputByteCount

        val floatByteCount = frameCount * channels * 4
        if (engineOutputBuffer.capacity() < floatByteCount) {
            engineOutputBuffer = ByteBuffer.allocateDirect(floatByteCount)
                .order(ByteOrder.LITTLE_ENDIAN)
        }
        engineOutputBuffer.clear()

        val nativeInput: ByteBuffer
        val inputOffset: Int
        if (inputBuffer.isDirect) {
            nativeInput = inputBuffer
            inputOffset = originalPosition
        } else {
            if (copyBuffer.capacity() < inputByteCount) {
                copyBuffer = ByteBuffer.allocateDirect(inputByteCount)
                    .order(ByteOrder.LITTLE_ENDIAN)
            }
            copyBuffer.clear()
            val copySource = inputBuffer.duplicate()
            copySource.position(originalPosition)
            copySource.limit(inputLimit)
            copyBuffer.put(copySource)
            copyBuffer.flip()
            nativeInput = copyBuffer
            inputOffset = 0
        }

        val processedFrames = runCatching {
            engine.processMediaPcm(
                input = nativeInput,
                inputByteOffset = inputOffset,
                output = engineOutputBuffer,
                outputByteOffset = 0,
                frameCount = frameCount,
                encoding = NativePcmEncoding.PCM_I16,
                channelCount = channels,
            )
        }.getOrDefault(-1)
        inputBuffer.position(inputLimit)
        if (processedFrames < 0) {
            // Fail-open: emit the raw input untouched rather than failing
            // the renderer. The native path must never break playback.
            val passthrough = replaceOutputBuffer(inputByteCount)
            val copySource = inputBuffer.duplicate()
            copySource.position(originalPosition)
            copySource.limit(inputLimit)
            passthrough.put(copySource)
            passthrough.flip()
            return
        }
        engineOutputBuffer.order(ByteOrder.LITTLE_ENDIAN)
        val out = replaceOutputBuffer(processedFrames * channels * 2)
        for (i in 0 until processedFrames * channels) {
            out.putShort(floatToPcm16Sample(engineOutputBuffer.getFloat(i * 4)))
        }
        out.flip()
    }

    override fun onQueueEndOfStream() {
        if (outputAudioFormat == AudioProcessor.AudioFormat.NOT_SET) return
        if (nativeEncoding == null) return
        val channels = outputAudioFormat.channelCount
        val outputByteCount = RESAMPLER_FLUSH_CAPACITY_FRAMES * channels * 4
        if (engineOutputBuffer.capacity() < outputByteCount) {
            engineOutputBuffer = ByteBuffer.allocateDirect(outputByteCount)
                .order(ByteOrder.LITTLE_ENDIAN)
        }
        engineOutputBuffer.clear()
        val outputFrames = runCatching {
            engine.flushMediaProcessor(engineOutputBuffer, channels)
        }.getOrDefault(0)
        if (outputFrames <= 0) return
        val out = replaceOutputBuffer(outputFrames * channels * 2)
        for (i in 0 until outputFrames * channels) {
            out.putShort(floatToPcm16Sample(engineOutputBuffer.getFloat(i * 4)))
        }
        out.flip()
    }

    override fun onFlush() {
        // Seek/track-swap: drop resampler + filter state so pre-seek audio
        // never smears into the new position.
        runCatching { engine.resetMediaProcessor() }
    }

    override fun onReset() {
        nativeEncoding = null
        copyBuffer = AudioProcessor.EMPTY_BUFFER
        engineOutputBuffer = AudioProcessor.EMPTY_BUFFER
        runCatching { engine.resetMediaProcessor() }
    }

    /**
     * float [-1, 1] -> int16 with round-half-away and clamping. For 16-bit
     * sources the engine output is the exact float image of the original
     * int16 samples, so this conversion returns them unchanged (bit-exact).
     */
    private fun floatToPcm16Sample(value: Float): Short {
        if (!value.isFinite()) return 0
        val scaled = value * 32768f
        val rounded = if (scaled >= 0f) scaled + 0.5f else scaled - 0.5f
        return rounded.coerceIn(-32768f, 32767f).toInt().toShort()
    }

    private companion object {
        // Capacity for draining the (dormant in R2) resampler tail at EOS.
        const val RESAMPLER_FLUSH_CAPACITY_FRAMES = 65_536
    }
}
