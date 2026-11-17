package local.photoframe

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.exifinterface.media.ExifInterface
import java.io.File
import java.io.BufferedInputStream
import java.io.DataInputStream

/** Copy only standard shooting fields into a fresh EXIF container, never opaque metadata. */
object PhotoExif {
    private val tags = listOf(
        "Make", "Model", "DateTime", "DateTimeOriginal", "DateTimeDigitized",
        "SubSecTime", "SubSecTimeOriginal", "SubSecTimeDigitized",
        "OffsetTime", "OffsetTimeOriginal", "OffsetTimeDigitized",
        "ExposureTime", "FNumber", "ExposureProgram", "SpectralSensitivity",
        "PhotographicSensitivity", "SensitivityType", "StandardOutputSensitivity",
        "RecommendedExposureIndex", "ISOSpeed", "ShutterSpeedValue", "ApertureValue",
        "BrightnessValue", "ExposureBiasValue", "MaxApertureValue", "SubjectDistance",
        "MeteringMode", "LightSource", "Flash", "FocalLength", "FlashEnergy",
        "FocalPlaneXResolution", "FocalPlaneYResolution", "FocalPlaneResolutionUnit",
        "ExposureIndex", "SensingMethod", "CustomRendered", "ExposureMode", "WhiteBalance",
        "DigitalZoomRatio", "FocalLengthIn35mmFilm", "SceneCaptureType", "GainControl",
        "Contrast", "Saturation", "Sharpness", "SubjectDistanceRange",
        "LensSpecification", "LensMake", "LensModel"
    )
    fun copy(original: File, jpeg: File) {
        require(original.canonicalPath != jpeg.canonicalPath)
        val source = ExifInterface(original)
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(jpeg.path, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0)
        val container = File.createTempFile("exif-", ".jpg", jpeg.parentFile)
        val staged = File.createTempFile("exif-ready-", ".jpg", jpeg.parentFile)
        try {
            val pixel = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
            try { container.outputStream().use { check(pixel.compress(Bitmap.CompressFormat.JPEG, 90, it)) } }
            finally { pixel.recycle() }
            val target = ExifInterface(container)
            val values = tags.mapNotNull { tag -> source.getAttribute(tag)?.let { tag to it } }.toMap().toMutableMap()
            if (values["LensModel"].isNullOrBlank()) {
                original.inputStream().use { PanasonicMakerNote.lensModel(it) }?.let { values["LensModel"] = it }
            }
            values.forEach { (tag, value) -> target.setAttribute(tag, value) }
            target.setAttribute("Orientation", "1")
            target.setAttribute("ImageWidth", bounds.outWidth.toString())
            target.setAttribute("ImageLength", bounds.outHeight.toString())
            target.setAttribute("PixelXDimension", bounds.outWidth.toString())
            target.setAttribute("PixelYDimension", bounds.outHeight.toString())
            target.setAttribute("ColorSpace", "1")
            target.saveAttributes()
            // Extract the fresh APP1 and insert it without decoding/recompressing the photo.
            var app1: ByteArray? = null
            DataInputStream(BufferedInputStream(container.inputStream())).use { input ->
                check(input.readUnsignedShort() == 0xffd8)
                while (true) {
                    val marker = input.readUnsignedShort()
                    if (marker == 0xffda || marker == 0xffd9) break
                    val size = input.readUnsignedShort()
                    require(size >= 2)
                    val payload = ByteArray(size - 2).also { input.readFully(it) }
                    if (marker == 0xffe1) { app1 = byteArrayOf(0xff.toByte(), 0xe1.toByte(), (size shr 8).toByte(), size.toByte()) + payload; break }
                }
            }
            val segment = requireNotNull(app1)
            staged.outputStream().buffered().use { output ->
                DataInputStream(BufferedInputStream(jpeg.inputStream())).use { input ->
                    check(input.readUnsignedShort() == 0xffd8)
                    output.write(byteArrayOf(0xff.toByte(), 0xd8.toByte()))
                    output.write(segment)
                    while (true) {
                        val marker = input.readUnsignedShort()
                        if (marker == 0xffda || marker == 0xffd9) {
                            output.write(marker shr 8); output.write(marker)
                            input.copyTo(output)
                            break
                        }
                        val size = input.readUnsignedShort()
                        require(size >= 2)
                        val payload = ByteArray(size - 2).also { input.readFully(it) }
                        // No XMP, old EXIF, thumbnails or comments can leak via APP1/COM.
                        if (marker != 0xffe1 && marker != 0xfffe) {
                            output.write(marker shr 8); output.write(marker)
                            output.write(size shr 8); output.write(size); output.write(payload)
                        }
                    }
                }
            }
            val check = ExifInterface(staged)
            require(check.getAttribute("GPSLatitude") == null && check.getAttribute("GPSLongitude") == null &&
                check.getAttribute("MakerNote") == null && check.getAttribute("UserComment") == null && !check.hasThumbnail())
            require(check.getAttributeInt("Orientation", 0) == 1 && check.getAttributeInt("ColorSpace", 0) == 1)
            require(check.getAttributeInt("PixelXDimension", 0) == bounds.outWidth && check.getAttributeInt("PixelYDimension", 0) == bounds.outHeight)
            values.forEach { (tag, value) ->
                val actual = check.getAttribute(tag)
                // ExifInterface can rewrite rational exposure values with a different
                // decimal representation. Compare the value, not its formatting.
                val matches = if (tag == "ExposureTime" && actual != null) {
                    val before = source.getAttributeDouble(tag, Double.NaN)
                    val after = check.getAttributeDouble(tag, Double.NaN)
                    before.isFinite() && after.isFinite() &&
                        kotlin.math.abs(before - after) <= maxOf(1e-9, kotlin.math.abs(before) * 1e-5)
                } else actual == value
                require(matches) { "撮影情報を書き込めません：$tag" }
            }
            check(staged.renameTo(jpeg)) { "撮影情報付きJPEGを確定できません。" }
        } finally { container.delete(); staged.delete() }
    }
}
