package id.sahabatnetra.app

import android.content.Context
import java.io.File
import java.time.Instant

class Metrics(context: Context) {
    private val file = File(context.noBackupFilesDir, "metrics.csv")
    @Synchronized fun record(task: String, elapsedMs: Long, success: Boolean) {
        if (!file.exists()) file.writeText("timestamp,task,latency_ms,success\n")
        // Only fixed operation names and performance, no transcripts, faces, API keys or images.
        if (file.length() > 5_000_000) file.writeText("timestamp,task,latency_ms,success\n")
        file.appendText("${Instant.now()},$task,$elapsedMs,$success\n")
    }
    @Synchronized fun bytes(): ByteArray = if (file.exists()) file.readBytes() else "timestamp,task,latency_ms,success\n".toByteArray()
}
