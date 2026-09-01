require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |spec|
  spec.name           = 'MurmurReactNative'
  spec.version        = package['version']
  spec.summary        = package['description']
  spec.description    = package['description']
  spec.license        = package['license']
  spec.author         = 'October'
  spec.homepage       = 'https://github.com/october-dev/murmur'
  spec.platforms      = { :ios => '15.1' }
  spec.swift_version  = '5.9'
  spec.source         = { :git => 'https://github.com/october-dev/murmur.git', :tag => spec.version.to_s }
  spec.static_framework = true

  spec.dependency 'ExpoModulesCore'
  spec.source_files = 'ios/**/*.{h,m,mm,swift,hpp,cpp}'
end
