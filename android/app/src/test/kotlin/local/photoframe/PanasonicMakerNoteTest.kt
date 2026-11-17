package local.photoframe

import org.junit.Assert.*
import org.junit.Test

class PanasonicMakerNoteTest {
    private fun fixture(little: Boolean): ByteArray {
        val t = ByteArray(128)
        fun put(offset: Int, value: Int, count: Int) {
            for (i in 0 until count) t[offset+i] = (value shr (8 * if (little) i else count-1-i)).toByte()
        }
        t[0] = (if (little) 73 else 77).toByte(); t[1] = t[0]
        put(2,42,2);put(4,8,4);put(8,1,2)
        put(10,0x8769,2);put(12,4,2);put(14,1,4);put(18,26,4)
        put(26,1,2);put(28,0x927c,2);put(30,7,2);put(32,84,4);put(36,44,4)
        byteArrayOf(80,97,110,97,115,111,110,105,99,0,0,0).copyInto(t,44)
        val text = "OLYMPUS M.25mm F1.8\u0000".toByteArray()
        put(56,1,2);put(58,0x0051,2);put(60,2,2);put(62,text.size,4);put(66,76,4)
        text.copyInto(t,76)
        val length = t.size + 8
        return byteArrayOf(255.toByte(),216.toByte(),255.toByte(),225.toByte(),(length shr 8).toByte(),length.toByte(),69,120,105,102,0,0) + t + byteArrayOf(255.toByte(),217.toByte())
    }
    @Test fun bothEndianAndStreamMatchMacFixture() {
        for (little in listOf(true,false)) {
            val data = fixture(little)
            assertEquals("OLYMPUS M.25mm F1.8", PanasonicMakerNote.lensModel(data))
            assertEquals("OLYMPUS M.25mm F1.8", data.inputStream().use { PanasonicMakerNote.lensModel(it) })
        }
    }
    @Test fun malformedAndTruncatedMetadataIsNeverReadOutsideBounds() {
        for (little in listOf(true,false)) {
            val data = fixture(little)
            for (length in 0 until data.size - 2) {
                val cut = data.copyOf(length)
                assertNull(PanasonicMakerNote.lensModel(cut))
                assertNull(cut.inputStream().use { PanasonicMakerNote.lensModel(it) })
            }
            val broken = data.copyOf()
            for (i in 0..3) broken[12 + 66 + i] = 255.toByte()
            assertNull(PanasonicMakerNote.lensModel(broken))
        }
    }
}
