package local.photoframe

/** Reads only bounded JPEG APP1/TIFF metadata, matching the macOS fallback. */
object PanasonicMakerNote {
    fun lensModel(input: java.io.InputStream): String? {
        val data = java.io.DataInputStream(input)
        try {
            if (data.readUnsignedShort() != 0xffd8) return null
            while (true) {
                if (data.readUnsignedByte() != 255) return null
                var marker = data.readUnsignedByte()
                while (marker == 255) marker = data.readUnsignedByte()
                if (marker == 218 || marker == 217) return null
                if (marker == 1 || marker in 208..215) continue
                val size = data.readUnsignedShort()
                if (size < 2) return null
                if (marker == 225) {
                    val payload = ByteArray(size - 2)
                    data.readFully(payload)
                    val segment = byteArrayOf(255.toByte(),216.toByte(),255.toByte(),225.toByte(),
                        (size shr 8).toByte(),size.toByte()) + payload + byteArrayOf(255.toByte(),217.toByte())
                    lensModel(segment)?.let { return it }
                } else {
                    var remaining = size - 2
                    while (remaining > 0) {
                        val skipped = data.skipBytes(remaining)
                        if (skipped == 0) return null
                        remaining -= skipped
                    }
                }
            }
        } catch (_: java.io.EOFException) { return null }
    }

    fun lensModel(bytes: ByteArray): String? {
        fun u(i: Int) = bytes[i].toInt() and 255
        if (bytes.size < 4 || u(0) != 255 || u(1) != 216) return null
        var cursor = 2
        while (cursor + 4 <= bytes.size) {
            if (u(cursor) != 255) return null
            while (cursor < bytes.size && u(cursor) == 255) cursor++
            if (cursor >= bytes.size) return null
            val marker = u(cursor++)
            if (marker == 218 || marker == 217) return null
            if (marker == 1 || marker in 208..215) continue
            if (cursor + 2 > bytes.size) return null
            val length = u(cursor) * 256 + u(cursor + 1)
            if (length < 2 || length > bytes.size - cursor) return null
            val start = cursor + 2
            val end = cursor + length
            cursor = end
            if (marker != 225 || end - start < 14 ||
                !bytes.copyOfRange(start, start + 6).contentEquals(byteArrayOf(69,120,105,102,0,0))) continue
            val base = start + 6
            val size = end - base
            val little = when {
                u(base) == 73 && u(base + 1) == 73 -> true
                u(base) == 77 && u(base + 1) == 77 -> false
                else -> continue
            }
            fun number(offset: Int, count: Int): Int? {
                if (offset < 0 || count > size || offset > size - count) return null
                var value = 0L
                for (i in 0 until count) value = value or
                    (u(base + offset + i).toLong() shl (8 * if (little) i else count - 1 - i))
                return if (value <= Int.MAX_VALUE) value.toInt() else null
            }
            fun entry(ifd: Int, tag: Int): Int? {
                val count = number(ifd, 2) ?: return null
                if (count > 4096 || ifd > size - 2 || count > (size - ifd - 2) / 12) return null
                for (i in 0 until count) {
                    val p = ifd + 2 + i * 12
                    if (number(p, 2) == tag) return p
                }
                return null
            }
            if (number(2, 2) != 42) continue
            val first = number(4, 4) ?: continue
            val exifEntry = entry(first, 0x8769) ?: continue
            if (number(exifEntry + 2, 2) != 4 || number(exifEntry + 4, 4) != 1) continue
            val exif = number(exifEntry + 8, 4) ?: continue
            val noteEntry = entry(exif, 0x927c) ?: continue
            if (number(noteEntry + 2, 2) != 7) continue
            val noteCount = number(noteEntry + 4, 4) ?: continue
            val note = number(noteEntry + 8, 4) ?: continue
            if (noteCount < 14 || note > size - noteCount ||
                !bytes.copyOfRange(base + note, base + note + 12)
                    .contentEquals(byteArrayOf(80,97,110,97,115,111,110,105,99,0,0,0))) continue
            val lens = entry(note + 12, 0x0051) ?: continue
            if (lens > note + noteCount - 12 || number(lens + 2, 2) != 2) continue
            val count = number(lens + 4, 4) ?: continue
            if (count !in 2..256) continue
            val value = number(lens + 8, 4) ?: continue
            val offset = if (count <= 4) lens + 8 else value
            if (offset < note || offset > note + noteCount - count) continue
            val content = bytes.copyOfRange(base + offset, base + offset + count).takeWhile { it != 0.toByte() }
            if (content.isEmpty() || content.any { (it.toInt() and 255) !in 32..126 }) continue
            return content.toByteArray().toString(Charsets.US_ASCII).trim().ifEmpty { null }
        }
        return null
    }
}
