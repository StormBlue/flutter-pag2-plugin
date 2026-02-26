#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_pag2.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_pag2_plugin'
  s.version          = '2.0.0-alpha.1'
  s.summary          = 'PAG rendering plugin for Flutter.'
  s.description      = <<-DESC
Flutter plugin for rendering Tencent PAG animations on Android and iOS.
                       DESC
  s.homepage         = 'https://github.com/cold-storm/flutter_pag2_plugin'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'libpag'
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.static_framework = true
  s.dependency 'Flutter'
  s.dependency 'libpag', '~> 4.5.27'
  s.platform = :ios, '13.0'
  s.library = 'c++'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
