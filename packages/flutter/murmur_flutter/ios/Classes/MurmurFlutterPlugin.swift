import AVFoundation
import CoreBluetooth
import Flutter
import UIKit

public final class MurmurFlutterPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "dev.october.murmur/flutter",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(MurmurFlutterPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getCapabilities":
      result([
        "microphone": true,
        "bluetoothLowEnergy": CBCentralManager.authorization != .restricted,
      ])
    case "requestPermissions":
      result(false)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
