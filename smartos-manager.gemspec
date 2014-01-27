# -*- encoding: utf-8 -*-
require File.expand_path('../lib/smartos-manager/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Julien Ammous"]
  gem.email         = ["schmurfy@gmail.com"]
  gem.description   = %q{...}
  gem.summary       = %q{... .}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = %(smanager)
  gem.name          = "smartos-manager"
  gem.license       = 'MIT'
  gem.require_paths = ["lib"]
  gem.version       = SmartosManager::VERSION
  
  gem.add_dependency 'toml-rb'
  gem.add_dependency 'thor'
  gem.add_dependency 'net-ssh'
  gem.add_dependency 'net-ssh-gateway'
  gem.add_dependency 'net-ssh-multi'
  gem.add_dependency 'colored'
  gem.add_dependency 'size_units'

end
