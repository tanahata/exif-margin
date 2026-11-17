package local.photoframe

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ColorSpace
import android.graphics.ImageDecoder
import androidx.exifinterface.media.ExifInterface
import java.io.File

object PhotoNormalizer {
    fun normalize(context: Context, file: File): Map<String, Any> {
        val metadata = ExifInterface(file)
        val props = mutableMapOf<String, Any>()
        fun text(key: String, tag: String) {
            metadata.getAttribute(tag)?.trim()?.takeIf { it.isNotEmpty() }?.let { props[key] = it }
        }
        fun positive(key: String, tag: String) {
            val n = metadata.getAttributeDouble(tag, Double.NaN)
            if (n.isFinite() && n > 0) props[key] = n
        }
        text("make", ExifInterface.TAG_MAKE)
        text("model", ExifInterface.TAG_MODEL)
        text("lensMake", ExifInterface.TAG_LENS_MAKE)
        text("lensModel", ExifInterface.TAG_LENS_MODEL)
        if (!props.containsKey("lensModel")) {
            // Only metadata is scanned by the parser; bound the file read by the import limit.
            file.inputStream().use { PanasonicMakerNote.lensModel(it) }?.let { props["lensModel"] = it }
        }
        positive("focal", ExifInterface.TAG_FOCAL_LENGTH)
        positive("focal35", ExifInterface.TAG_FOCAL_LENGTH_IN_35MM_FILM)
        positive("aperture", ExifInterface.TAG_F_NUMBER)
        positive("exposure", ExifInterface.TAG_EXPOSURE_TIME)
        positive("iso", ExifInterface.TAG_PHOTOGRAPHIC_SENSITIVITY)
        if ((props["iso"] as? Double ?: 65535.0) >= 65535) {
            props.remove("iso")
            positive("iso", ExifInterface.TAG_ISO_SPEED)
        }
        // ImageDecoder applies EXIF orientation. Never rotate the decoded pixels twice.
        val bitmap = ImageDecoder.decodeBitmap(ImageDecoder.createSource(file)) { decoder, info, _ ->
            val size = info.size
            require(size.width in 1..30000 && size.height in 1..30000 &&
                size.width.toLong() * size.height <= 100_000_000L) {
                "この写真は大きすぎます。1億画素・1辺30000px以下を選んでください。"
            }
            require(info.mimeType == "image/jpeg" || info.mimeType == "image/png") { "JPEGまたはPNGを選んでください。" }
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            decoder.setTargetColorSpace(ColorSpace.get(ColorSpace.Named.SRGB))
            decoder.setOnPartialImageListener { false }
        }
        val output = File.createTempFile("normalized-", ".png", File(context.cacheDir, "imports").apply { mkdirs() })
        try {
            output.outputStream().use { check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
        } catch (e: Throwable) {
            output.delete()
            throw e
        } finally { bitmap.recycle() }
        return mapOf("path" to output.path, "metadata" to props,
            "icc" to context.assets.open("srgb.icc").use { it.readBytes() })
    }
}
