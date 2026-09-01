import CoreBluetooth
import ExpoModulesCore

public final class MurmurReactNativeModule: Module {
  public func definition() -> ModuleDefinition {
    Name("MurmurReactNative")

    Function("getCapabilities") {
      [
        "microphone": true,
        "bluetoothLowEnergy": CBCentralManager.authorization != .restricted,
      ]
    }

    AsyncFunction("requestPermissions") { () -> Bool in
      false
    }
  }
}
