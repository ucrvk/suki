package top.wenwen12305.suki

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val authLogExportChannel = "top.wenwen12305.suki/auth_log_export"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            authLogExportChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method != "exportAuthLog") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            exportAuthLog(call, result)
        }
    }

    private fun exportAuthLog(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("unsupported", "Android 10 以下不支持无权限导出登录日志", null)
            return
        }

        val fileName = call.argument<String>("fileName")
        val content = call.argument<String>("content")
        if (fileName.isNullOrBlank() || content == null) {
            result.error("invalid_arguments", "缺少导出日志所需内容", null)
            return
        }

        try {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, "text/plain")
                put(
                    MediaStore.Downloads.RELATIVE_PATH,
                    "${Environment.DIRECTORY_DOWNLOADS}/Suki",
                )
            }
            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            if (uri == null) {
                result.error("create_failed", "无法创建登录日志文件", null)
                return
            }

            val stream = resolver.openOutputStream(uri)
            if (stream == null) {
                resolver.delete(uri, null, null)
                result.error("write_failed", "无法写入登录日志文件", null)
                return
            }
            stream.bufferedWriter(Charsets.UTF_8).use { writer -> writer.write(content) }
            result.success("${Environment.DIRECTORY_DOWNLOADS}/Suki/$fileName")
        } catch (error: Exception) {
            result.error("export_failed", error.message ?: "导出登录日志失败", null)
        }
    }
}
