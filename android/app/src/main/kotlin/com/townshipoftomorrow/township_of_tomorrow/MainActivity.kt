package com.townshipoftomorrow.township_of_tomorrow

import com.townshipoftomorrow.township_of_tomorrow.BuildConfig

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import android.util.Log
import townshipcore.Townshipcore

/**
 * Thin bridge between Dart and the Go native core (gomobile .aar, see go/townshipcore).
 * All heavy pure-compute jobs live in Go: kNN over embeddings, DCT perceptual
 * hashing, and the placeholder anti-exploit verification gate.
 *
 * A second, tiny channel — `township/system` — carries system-level UI actions
 * (currently `openAppSettings`, the board-32 camera-permission recovery). Plain
 * intents only: no extra permission, no extra dependency.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "township/core"
    private val systemChannelName = "township/system"
    private val debugChannelName = "township/debug"
    private var debugEngine: FlutterEngine? = null
    private var debugImportPath: String? = null

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        // The activity is single-instance: `am start --es twp_debug_import ...`
        // on a warm instance arrives here, not through configureFlutterEngine.
        val path = intent?.getStringExtra("twp_debug_import")
        if (path != null && BuildConfig.DEBUG) {
            Log.d("TWP", "onNewIntent import=$path")
            debugImportPath = path
            debugEngine?.let { eng ->
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    MethodChannel(eng.dartExecutor.binaryMessenger, "township/debug")
                        .invokeMethod("importFile", path)
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        debugEngine = flutterEngine
        // Deterministic adb test hook: `am start ... -e twp_debug_import /path`
        // (debug builds only, and only for the shell uid). Dart pulls this
        // through consumeDebugImport once its AI stack is ready.
        val importPath = intent?.getStringExtra("twp_debug_import")
        Log.d("TWP", "hook intent=$importPath debug=${BuildConfig.DEBUG}")
        if (importPath != null && BuildConfig.DEBUG) {
            debugImportPath = importPath
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "coreVersion" -> result.success(Townshipcore.version())
                        "consumeDebugImport" -> {
                            val path = debugImportPath
                            debugImportPath = null
                            Log.d("TWP", "consumeDebugImport -> $path")
                            result.success(path)
                        }
                        "knnSearch" -> {
                            val vec = call.argument<ByteArray>("vec")!!
                            val db = call.argument<ByteArray>("db")!!
                            val labels = call.argument<String>("labels")!!
                            val k = (call.argument<Number>("k") ?: 5).toLong()
                            result.success(Townshipcore.knnSearch(vec, db, labels, k))
                        }
                        "pHash" -> {
                            val bytes = call.argument<ByteArray>("bytes")
                            if (bytes == null) {
                                result.error("BAD_ARGS", "pHash needs 'bytes'", null)
                            } else {
                                result.success(Townshipcore.pHash(bytes, ""))
                            }
                        }
                        "verifyAction" -> {
                            val action = call.argument<String>("action")!!
                            val entryHash = call.argument<String>("entryHash") ?: ""
                            val proof = call.argument<ByteArray>("proof")!!
                            result.success(Townshipcore.verifyAction(action, entryHash, proof))
                        }
                        "pHashFileDownscale" -> {
                            // Large camera captures can be several MB; downscale to 512 px wide
                            // before handing bytes over the JNI boundary.
                            val path = call.argument<String>("path")!!
                            val bmp = BitmapFactory.decodeFile(path) ?: run {
                                result.error("DECODE_FAILED", "cannot decode $path", null); return@setMethodCallHandler
                            }
                            val scaled = if (bmp.width > 512) {
                                val h = bmp.height * 512 / bmp.width
                                Bitmap.createScaledBitmap(bmp, 512, h, true)
                            } else bmp
                            val out = ByteArrayOutputStream()
                            scaled.compress(Bitmap.CompressFormat.JPEG, 90, out)
                            result.success(Townshipcore.pHash(out.toByteArray(), ""))
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("CORE_ERROR", "${call.method}: ${e.message}", null)
                }
            }

        // System-level UI actions (board-32 camera-permission recovery):
        // `openAppSettings` opens this app's own details page via the
        // ACTION_APPLICATION_DETAILS_SETTINGS intent — needs no permission
        // and no extra dependency on the Dart side.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, systemChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openAppSettings" -> {
                        try {
                            val intent = Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.fromParts("package", packageName, null)
                            )
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e("TWP", "openAppSettings failed: ${e.message}")
                            result.error("SYSTEM_ERROR", "${call.method}: ${e.message}", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
