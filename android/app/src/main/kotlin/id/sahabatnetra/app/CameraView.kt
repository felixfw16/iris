package id.sahabatnetra.app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Matrix
import android.view.View
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.StandardMessageCodec
import java.util.concurrent.Executors

class CameraFactory(private val host: MainActivity) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView = CameraView(context, host)
}

class CameraView(context: Context, private val host: MainActivity) : PlatformView {
    private val preview = PreviewView(context).apply { implementationMode = PreviewView.ImplementationMode.COMPATIBLE; scaleType = PreviewView.ScaleType.FILL_CENTER }
    private val cameraExecutor = Executors.newSingleThreadExecutor()
    private var provider: ProcessCameraProvider? = null
    private var analysis: ImageAnalysis? = null
    private var previewUseCase: Preview? = null
    private var disposed = false
    private var lastFrameAt = 0L
    init { host.attachCamera(this); bind() }
    fun bind() {
        if (disposed || analysis != null || ContextCompat.checkSelfPermission(host, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) return
        val future = ProcessCameraProvider.getInstance(host)
        future.addListener({
            if (disposed) return@addListener
            try {
                val camera = future.get(); provider = camera
                camera.unbindAll()
                val p = Preview.Builder().build().also { it.setSurfaceProvider(preview.surfaceProvider) }; previewUseCase = p
                @Suppress("DEPRECATION")
                val a = ImageAnalysis.Builder().setTargetResolution(android.util.Size(960, 720))
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888).build()
                analysis = a
                a.setAnalyzer(cameraExecutor) { proxy ->
                    try {
                        val now = System.currentTimeMillis()
                        if (now - lastFrameAt < 180) return@setAnalyzer
                        lastFrameAt = now
                        val plane = proxy.planes[0]
                        val paddedWidth = plane.rowStride / plane.pixelStride
                        val padded = Bitmap.createBitmap(paddedWidth, proxy.height, Bitmap.Config.ARGB_8888)
                        plane.buffer.rewind(); padded.copyPixelsFromBuffer(plane.buffer)
                        val cropped = Bitmap.createBitmap(padded, 0, 0, proxy.width, proxy.height)
                        if (cropped !== padded) padded.recycle()
                        val rotation = Matrix().apply { postRotate(proxy.imageInfo.rotationDegrees.toFloat()) }
                        val upright = Bitmap.createBitmap(cropped, 0, 0, cropped.width, cropped.height, rotation, true)
                        if (upright !== cropped) cropped.recycle()
                        host.receiveFrame(upright, now)
                    } catch (_: Exception) { host.emit(mapOf("type" to "error", "message" to "Frame kamera tidak dapat dibaca.")) }
                    finally { proxy.close() }
                }
                camera.bindToLifecycle(host, CameraSelector.DEFAULT_BACK_CAMERA, p, a)
            } catch (_: Exception) { host.emit(mapOf("type" to "error", "message" to "Kamera tidak tersedia. Tutup aplikasi lain yang menggunakan kamera.")) }
        }, ContextCompat.getMainExecutor(host))
    }
    override fun getView(): View = preview
    fun rebind() { analysis?.clearAnalyzer(); analysis = null; bind() }
    override fun dispose() {
        disposed = true; analysis?.clearAnalyzer()
        val owned = listOfNotNull(previewUseCase, analysis)
        if (owned.isNotEmpty()) provider?.unbind(*owned.toTypedArray())
        cameraExecutor.shutdown()
        host.detachCamera(this)
    }
}
