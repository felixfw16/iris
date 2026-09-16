package id.sahabatnetra.app

import android.graphics.Bitmap
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import ai.onnxruntime.TensorInfo
import java.nio.FloatBuffer
import kotlin.math.roundToInt

/** YOLO26n-depth: RGB /255 letterbox 640, output 1x1x640x640 in metres. */
class DepthVision(private val models: ModelFiles) : AutoCloseable {
    private val runtime = OrtEnvironment.getEnvironment()
    private var session: OrtSession? = null
    fun measure(bitmap: Bitmap, objects: List<SeenObject>): List<SeenObject> {
        if (session == null) {
            val options = OrtSession.SessionOptions().apply { setIntraOpNumThreads(2); setInterOpNumThreads(1) }
            session = options.use { runtime.createSession(models.file("depth").absolutePath, it) }
        }
        val active = checkNotNull(session)
        val inputName = active.inputNames.first()
        val info = active.inputInfo.getValue(inputName).info as TensorInfo
        check(info.shape.contentEquals(longArrayOf(1, 3, 640, 640))) { "Format model kedalaman tidak sesuai." }
        val w = 640; val h = 640
        val scale = minOf(w.toFloat() / bitmap.width, h.toFloat() / bitmap.height)
        val scaledW = (bitmap.width * scale).roundToInt().coerceIn(1, w)
        val scaledH = (bitmap.height * scale).roundToInt().coerceIn(1, h)
        val offsetX = (w - scaledW) / 2; val offsetY = (h - scaledH) / 2
        val scaled = Bitmap.createScaledBitmap(bitmap, scaledW, scaledH, true)
        val pixels = IntArray(scaledW * scaledH); scaled.getPixels(pixels, 0, scaledW, 0, 0, scaledW, scaledH)
        if (scaled !== bitmap) scaled.recycle()
        val data = FloatArray(3 * w * h) { 114f / 255f }
        // Same RGB 114 letterbox and /255 normalization as the official predictor.
        for (i in pixels.indices) for (c in 0..2) {
            val target = (i / scaledW + offsetY) * w + i % scaledW + offsetX
            data[c * w * h + target] = ((pixels[i] shr (16 - c * 8)) and 255) / 255f
        }
        OnnxTensor.createTensor(runtime, FloatBuffer.wrap(data), longArrayOf(1, 3, h.toLong(), w.toLong())).use { input ->
            active.run(mapOf(inputName to input)).use { result ->
                val output = result[0] as OnnxTensor
                val depth = FloatArray(w * h)
                check(output.info.shape.contentEquals(longArrayOf(1, 1, h.toLong(), w.toLong()))) { "Ukuran keluaran depth tidak sesuai." }
                output.floatBuffer.get(depth)
                for (obj in objects) {
                    val b = obj.box
                    val left = ((b.left + b.width() * .3f) * scale + offsetX).toInt().coerceIn(0, w - 1)
                    val right = ((b.right - b.width() * .3f) * scale + offsetX).toInt().coerceIn(left, w - 1)
                    val top = ((b.top + b.height() * .3f) * scale + offsetY).toInt().coerceIn(0, h - 1)
                    val bottom = ((b.bottom - b.height() * .3f) * scale + offsetY).toInt().coerceIn(top, h - 1)
                    val values = ArrayList<Float>()
                    for (y in top..bottom step 2) for (x in left..right step 2) values.add(depth[y * w + x])
                    obj.meters = VisionMath.reliableDepth(values)
                }
            }
        }
        return objects
    }
    override fun close() { session?.close(); session = null }
}
