Pod::Spec.new do |s|
  s.name         = "MUAssetsLibrary"
  s.version      = "0.9.2"
  s.license      = "MIT"
  s.summary      = "Support Photos and ALAssetsLibrary photo library framework."
  s.homepage     = "https://github.com/muer2000/MUAssetsLibrary"
  s.author       = { "muer" => "muer2000@gmail.com" }
  s.platform     = :ios, "5.0"
  s.ios.deployment_target = "5.0"
  s.source       = { :git => "https://github.com/muer2000/MUAssetsLibrary.git", :tag => s.version }
  s.source_files  = "MUAssetsLibrary/**/*"
  s.requires_arc = true
end
