const {
  AndroidConfig,
  createRunOncePlugin,
  withInfoPlist,
} = require('expo/config-plugins');
const packageJson = require('./package.json');

const permissions = [
  'android.permission.BLUETOOTH_CONNECT',
  'android.permission.BLUETOOTH_SCAN',
  'android.permission.RECORD_AUDIO',
];

function withMurmur(config, options = {}) {
  config = withInfoPlist(config, (mod) => {
    mod.modResults.NSMicrophoneUsageDescription =
      options.microphonePermission ||
      mod.modResults.NSMicrophoneUsageDescription ||
      'Allow this app to use voice as an input through Murmur.';
    mod.modResults.NSBluetoothAlwaysUsageDescription =
      options.bluetoothPermission ||
      mod.modResults.NSBluetoothAlwaysUsageDescription ||
      'Allow this app to connect to voice wearables through Murmur.';
    return mod;
  });

  return AndroidConfig.Permissions.withPermissions(config, permissions);
}

module.exports = createRunOncePlugin(
  withMurmur,
  packageJson.name,
  packageJson.version
);
