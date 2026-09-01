package dev.october.murmur.reactnative

import android.content.pm.PackageManager
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class MurmurReactNativeModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("MurmurReactNative")

    Function("getCapabilities") {
      val context = appContext.reactContext
      val packageManager = context?.packageManager
      mapOf(
        "microphone" to (packageManager?.hasSystemFeature(
          PackageManager.FEATURE_MICROPHONE
        ) == true),
        "bluetoothLowEnergy" to (packageManager?.hasSystemFeature(
          PackageManager.FEATURE_BLUETOOTH_LE
        ) == true)
      )
    }

    AsyncFunction("requestPermissions") {
      false
    }
  }
}
