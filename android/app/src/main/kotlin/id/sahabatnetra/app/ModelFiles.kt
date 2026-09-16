package id.sahabatnetra.app

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

class ModelFiles(private val context: Context) {
    companion object {
        val names = linkedMapOf("objects" to "objects_oiv7.onnx", "objectLabels" to "objects_labels.json", "face" to "mobilefacenet.tflite",
            "depth" to "depth_yolo26n.onnx", "speech" to "ggml-tiny.bin",
            "qwen" to "qwen35_0_8b_iris.litertlm")
    }
    private val available by lazy { context.assets.list("models")?.toSet() ?: emptySet() }
    private val verified = mutableSetOf<String>()
    fun status(): Map<String, Boolean> = names.mapValues { available.contains(it.value) && available.contains("manifest.json") }
    @Synchronized fun file(id: String): File {
        val name = names[id] ?: error("Model tidak dikenal.")
        check(available.contains(name)) { "Model $id belum dipasang. Pasang APK lengkap dengan paket model." }
        val folder = File(context.noBackupFilesDir, "models").apply { mkdirs() }
        val file = File(folder, name)
        if (verified.contains(name) && file.exists()) return file
        val manifest = JSONObject(context.assets.open("models/manifest.json").bufferedReader().use { it.readText() })
        val expected = manifest.getJSONObject(id).getString("sha256")
        if (!file.exists() || digest(file) != expected) {
            val partial = File(folder, "$name.part")
            context.assets.open("models/$name").use { input -> partial.outputStream().use { input.copyTo(it) } }
            check(digest(partial) == expected) { "Pemeriksaan integritas model $id gagal." }
            check(partial.renameTo(file)) { "Tidak dapat memasang model $id." }
        }
        verified.add(name)
        return file
    }
    private fun digest(file: File): String {
        val hash = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { stream -> val buffer = ByteArray(65536); while (true) { val count = stream.read(buffer); if (count < 0) break; hash.update(buffer, 0, count) } }
        return hash.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
    }
}
