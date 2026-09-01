Pod::Spec.new do |spec|
  spec.name             = 'murmur_flutter'
  spec.version          = '0.1.0'
  spec.summary          = 'Flutter bindings for Murmur.'
  spec.homepage         = 'https://github.com/october-dev/murmur'
  spec.license          = { :type => 'Apache-2.0', :file => '../../../../LICENSE' }
  spec.author           = { 'October' => 'opensource@october.dev' }
  spec.source           = { :path => '.' }
  spec.source_files     = 'Classes/**/*'
  spec.dependency 'Flutter'
  spec.platform = :ios, '13.0'
  spec.swift_version = '5.0'
end
