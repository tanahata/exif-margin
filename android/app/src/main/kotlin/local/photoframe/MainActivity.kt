package local.photoframe

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
    private var channel: MethodChannel? = null
    private val executor = Executors.newSingleThreadExecutor()
    private val incoming = java.util.ArrayDeque<Map<String, Any>>()
    private var selection: MethodChannel.Result? = null
    private var selectionKind: String? = null
    private val exports by lazy { PhotoExportBridge(this) }
    private val imports get() = File(cacheDir, "imports").apply { mkdirs() }
    private val picker = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        completeSelection(uri, false)
    }
    private val zipPicker = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        completeSelection(uri, true)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        exports.cleanShares()
        // Do not re-import the same cold-start intent after an Activity recreation.
        if (savedInstanceState == null) receive(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receive(intent)
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "local.photoframe/android").also { bridge ->
            bridge.setMethodCallHandler { call, result ->
                when (call.method) {
                    "paths" -> result.success(mapOf("files" to filesDir.path, "cache" to cacheDir.path))
                    "nextIncoming" -> result.success(if (incoming.isEmpty()) null else incoming.removeFirst())
                    "pickPhoto", "pickZip" -> {
                        if (selection != null) result.error("busy", "選択画面は既に開いています。", null)
                        else {
                            selection = result
                            selectionKind = call.method
                            try {
                                if (call.method == "pickPhoto") picker.launch(arrayOf("image/jpeg", "image/png"))
                                else zipPicker.launch(arrayOf("application/zip", "application/x-zip-compressed", "application/octet-stream"))
                            } catch (e: Exception) {
                                selection = null
                                selectionKind = null
                                result.error("picker", "ファイル選択画面を開けません。", null)
                            }
                        }
                    }
                    "normalizeFile" -> background(result, task = {
                        PhotoNormalizer.normalize(this, privateFile(call.argument<String>("path")))
                    })
                    "copyExif" -> background(result, task = {
                        PhotoExif.copy(privateFile(call.argument<String>("original")), privateFile(call.argument<String>("jpeg")))
                        null
                    })
                    "save" -> background(result, task = {
                        exports.save(privateFile(call.argument<String>("path")), call.argument<String>("name") ?: "photo_frame_HQ.jpg")
                    })
                    "share" -> background(result, {
                        exports.share(privateFile(call.argument<String>("path")), call.argument<String>("name") ?: "photo_frame_HQ.jpg")
                    }) { value -> startActivity(value as Intent); null }
                    "open" -> try {
                        val uri = call.argument<String>("uri") ?: error("保存画像がありません。")
                        require(Uri.parse(uri).authority == MediaStoreAuthority) { "保存画像が正しくありません。" }
                        startActivity(exports.view(uri))
                        result.success(null)
                    } catch (e: Exception) { result.error("open", "画像を開けるアプリがありません。", null) }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun background(result: MethodChannel.Result, task: () -> Any?, finish: (Any?) -> Any? = { it }) {
        executor.execute {
            try {
                val value = task()
                runOnUiThread {
                    try { result.success(finish(value)) }
                    catch (e: Exception) { result.error("operation", e.message ?: "操作を完了できません。", null) }
                }
            } catch (e: Exception) {
                runOnUiThread { result.error("operation", e.message ?: "画像を処理できません。", null) }
            } catch (e: OutOfMemoryError) {
                runOnUiThread { result.error("memory", "メモリが足りません。他のアプリを閉じて再度お試しください。", null) }
            }
        }
    }

    private fun privateFile(path: String?): File {
        val file = File(requireNotNull(path)).canonicalFile
        require(file.isFile && file.path.startsWith(cacheDir.canonicalPath + File.separator)) { "一時画像を確認できません。" }
        return file
    }

    private fun completeSelection(uri: Uri?, zip: Boolean) {
        val result = selection
        selection = null
        selectionKind = null
        if (uri == null) { result?.success(null); return }
        executor.execute {
            try {
                val item = copyInput(uri, zip)
                runOnUiThread {
                    // A recreated Activity may receive a result without the old MethodChannel callback.
                    if (result != null) result.success(item)
                    else enqueue(item + ("kind" to if (zip) "zip" else "photo"))
                }
            } catch (e: Exception) {
                runOnUiThread {
                    if (result != null) result.error("import", e.message, null)
                    else enqueue(mapOf("error" to (e.message ?: "ファイルを読み込めません。")))
                }
            }
        }
    }

    private fun receive(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        @Suppress("DEPRECATION")
        val stream = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        val clip = intent.clipData
        if ((clip?.itemCount ?: 0) > 1) {
            enqueue(mapOf("error" to "写真は1枚ずつ共有してください。")); return
        }
        val uri = stream ?: clip?.takeIf { it.itemCount == 1 }?.getItemAt(0)?.uri
        if (uri == null || uri.scheme != "content" || intent.type !in listOf("image/jpeg", "image/png", "image/*")) {
            enqueue(mapOf("error" to "JPEGまたはPNGを1枚共有してください。")); return
        }
        executor.execute {
            val item = try { copyInput(uri, false) }
            catch (e: Exception) { mapOf("error" to (e.message ?: "共有写真を読み込めません。")) }
            runOnUiThread { enqueue(item) }
        }
    }

    private fun enqueue(item: Map<String, Any>) {
        incoming.addLast(item)
        channel?.invokeMethod("incoming", null)
    }

    private fun copyInput(uri: Uri, zip: Boolean): Map<String, Any> {
        require(uri.scheme == "content") { "選択したファイルを読み込めません。" }
        var name = if (zip) "settings.zip" else "photo.jpg"
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst() && !c.isNull(0)) name = c.getString(0)
        }
        name = name.replace(Regex("[\\\\/\\p{Cntrl}]"), "_").take(160)
        val destination = File.createTempFile(if (zip) "config-" else "source-", if (zip) ".zip" else ".input", imports)
        try {
            val max = if (zip) 32L * 1024 * 1024 else 512L * 1024 * 1024
            contentResolver.openInputStream(uri)?.use { input ->
                destination.outputStream().use { output ->
                    val buffer = ByteArray(65536)
                    var total = 0L
                    while (true) {
                        val n = input.read(buffer)
                        if (n == -1) break
                        total += n
                        require(total <= max) { "ファイルが大きすぎます。" }
                        output.write(buffer, 0, n)
                    }
                    require(total > 0) { "ファイルが空です。" }
                }
            } ?: error("読み取り権限を確認できません。もう一度選択してください。")
            if (!zip) {
                val header = ByteArray(8)
                destination.inputStream().use { it.read(header) }
                val jpeg = (header[0].toInt() and 255) == 255 && (header[1].toInt() and 255) == 216
                val png = header.contentEquals(byteArrayOf(137.toByte(),80,78,71,13,10,26,10))
                require(jpeg || png) { "JPEGまたはPNGを選んでください。" }
            }
            return mapOf("path" to destination.path, "name" to name)
        } catch (e: Throwable) { destination.delete(); throw e }
    }

    companion object { private const val MediaStoreAuthority = "media" }
}
