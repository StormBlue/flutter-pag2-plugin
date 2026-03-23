#
# CocoaPods integration for apps that do not use Flutter's Swift Package Manager path.
# Keep `libpag` versions aligned with `ios/flutter_pag2_plugin/Package.swift`.
#
# Validate: (from repo root) `cd ios && pod lib lint flutter_pag2_plugin.podspec --configuration=Debug --skip-tests`
#

Pod::Spec.new do |s|
  s.name             = 'flutter_pag2_plugin'
  s.version          = '1.0.0-alpha.5'
  s.summary          = 'Flutter plugin for Tencent PAG animations on iOS and Android.'
  s.description      = <<-DESC
A Flutter plugin for rendering Tencent PAG animations on Android (API 24+) and iOS (13.0+), supporting network, asset, and binary data sources.
                       DESC
  s.homepage         = 'https://github.com/cold-storm/flutter_pag2_plugin'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'cold-storm' => 'https://github.com/cold-storm' }
  s.source           = { :path => '.' }
  s.source_files     = 'flutter_pag2_plugin/Sources/flutter_pag2_plugin/**/*.swift'
  s.dependency       'Flutter'
  s.dependency       'libpag', '~> 4.5.41'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.9'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
