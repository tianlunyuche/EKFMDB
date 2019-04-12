#
# Be sure to run `pod lib lint EKDBSpec.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'EKDBSpec'
  s.version          = '0.0.5'
  s.summary          = 'FMDB的二次封装，提供面向对象的简洁接口'

  s.description      = <<-DESC
TODO: Add long description of the pod here.
                       DESC

  s.homepage         = 'https://github.com/tianlunyuche/EKDBSpec'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = 'MIT'
  s.author           = { 'tianlunyuche' => 'zhaozhuangxin@moyi365.com' }
  s.source           = { :git => 'mird@172.17.20.28:/home/mird/gitdata/ios/toollib/EKFMDB.git',
                         :tag => s.version.to_s,
                         :submodules => true
                        }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'
  s.ios.deployment_target = '8.0'
  s.requires_arc  = true

  s.source_files = 'EKFMDB/**/*'
  s.public_header_files = 'EKFMDB/**/*.h'
  # s.resource_bundles = {
  #   'EKDBSpec' => ['EKDBSpec/Assets/*.png']
  # }

  s.frameworks = 'UIKit', 'Foundation'
  s.dependency 'FMDB'
  
end
