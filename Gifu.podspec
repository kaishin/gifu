Pod::Spec.new do |s|
  s.name = "Gifu"
  s.version = ENV['LIB_VERSION'] || "0.0.1"
  s.summary = "High-performance animated GIF support for iOS "
  s.homepage = "https://github.com/kaishin/Gifu"
  s.social_media_url = "http://twitter.com/kaishin"
  s.license = { :type => "MIT", :file => "LICENSE" }
  s.author = { "Reda Lemeden" => "git@redalemeden.com" }
  s.source = { :git => "https://github.com/kaishin/Gifu.git", :tag => "v#{s.version}", :submodules => true }
  s.platform = :ios, "14.0"
  s.platform = :tvos, "14.0"
  s.swift_versions = ["5.0", "5.1", "5.2", "5.3", "5.4", "6.0", "6.1", "6.2"]
  s.ios.source_files = "Sources/**/*.{h,swift}"
  s.tvos.source_files = "Sources/**/*.{h,swift}"
  s.ios.deployment_target = "14.0"
  s.tvos.deployment_target = "14.0"
end
