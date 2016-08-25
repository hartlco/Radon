Pod::Spec.new do |s|
  s.name = 'Radon'
  s.version = '0.1.0'
  s.license = 'MIT'
  s.summary = 'Simple CloudKit model syncing'
  s.homepage = 'https://github.com/hartlco/Radon'
  s.authors = { 'Martin Hartl' => 'martin@hartl.co' }
  s.source = { :git => 'https://github.com/hartlco/Radon.git', :tag => s.version }

  s.ios.deployment_target = '9.0'
  s.source_files = 'Radon/Source/*.swift'
end