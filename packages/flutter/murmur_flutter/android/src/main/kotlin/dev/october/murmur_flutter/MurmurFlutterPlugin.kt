package dev.october.murmur_flutter

import android.content.Context
import android.content.pm.PackageManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class MurmurFlutterPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "dev.october.murmur/flutter")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getCapabilities" -> result.success(
                mapOf(
                    "microphone" to context.packageManager.hasSystemFeature(
                        PackageManager.FEATURE_MICROPHONE
                    ),
                    "bluetoothLowEnergy" to context.packageManager.hasSystemFeature(
                        PackageManager.FEATURE_BLUETOOTH_LE
                    )
                )
            )
            "requestPermissions" -> result.success(false)
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
