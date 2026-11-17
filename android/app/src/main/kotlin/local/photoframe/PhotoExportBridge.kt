package local.photoframe

import android.content.ClipData
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import androidx.core.content.FileProvider
import java.io.File

class PhotoExportBridge(private val context: Context) {
    private val shareDir get() = File(context.cacheDir, "share").apply { mkdirs() }

    fun share(file: File, name: String): Intent {
        cleanShares()
        val directory = File(shareDir, java.util.UUID.randomUUID().toString()).apply { mkdirs() }
        val copy = File(directory, safeName(name))
        try { file.copyTo(copy) } catch (e: Throwable) { directory.deleteRecursively(); throw e }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.share", copy)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "image/jpeg"
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newRawUri("EXIF Margin", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        return Intent.createChooser(send, "完成画像を共有").apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            clipData = send.clipData
        }
    }

    @Synchronized fun save(file: File, requestedName: String): Map<String, String> {
        val resolver = context.contentResolver
        val collection = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val existing = mutableSetOf<String>()
        resolver.query(collection, arrayOf(MediaStore.Images.Media.DISPLAY_NAME),
            "${MediaStore.Images.Media.RELATIVE_PATH} = ?", arrayOf("Pictures/EXIFMargin/"), null)?.use { cursor ->
            while (cursor.moveToNext()) existing.add(cursor.getString(0))
        }
        val base = safeName(requestedName).removeSuffix(".jpg")
        var name = "$base.jpg"
        var n = 1
        while (name in existing) name = "${base}_${n++}.jpg"
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/EXIFMargin/")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values) ?: error("写真の保存先を作成できません。")
        try {
            resolver.openOutputStream(uri, "w")?.use { out -> file.inputStream().use { it.copyTo(out) } }
                ?: error("写真を書き込めません。")
            check(resolver.update(uri, ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }, null, null) == 1)
        } catch (e: Throwable) { resolver.delete(uri, null, null); throw e }
        return mapOf("uri" to uri.toString(), "name" to name)
    }

    fun view(uri: String) = Intent(Intent.ACTION_VIEW).apply {
        setDataAndType(Uri.parse(uri), "image/jpeg")
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }

    fun cleanShares() {
        val cutoff = System.currentTimeMillis() - 24 * 60 * 60 * 1000
        shareDir.listFiles()?.filter { it.lastModified() < cutoff }?.forEach { it.deleteRecursively() }
    }

    companion object {
        fun safeName(value: String): String = value.replace(Regex("[\\\\/\\p{Cntrl}]"), "_")
            .take(160).ifBlank { "photo_frame_HQ.jpg" }.let { if (it.endsWith(".jpg")) it else "$it.jpg" }
    }
}
