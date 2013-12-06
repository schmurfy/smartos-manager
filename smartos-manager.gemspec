# -*- encoding: utf-8 -*-
require File.expand_path('../lib/smartos-manager/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Julien Ammous"]
  gem.email         = ["schmurfy@gmail.com"]
  gem.description   = %q{TODO: Write a gem description}
  gem.summary       = %q{TODO: Write a gem summary}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.name          = "smartos-manager"
  gem.license       = 'MIT'
  gem.require_paths = ["lib"]
  gem.version       = SmartosManager::VERSION
  
  gem.add_dependency 'thor'
  gem.add_dependency 'net-ssh'
  gem.add_dependency 'net-ssh-gateway'

end
