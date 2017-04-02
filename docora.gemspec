# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'docora/version'

Gem::Specification.new do |spec|
  spec.name          = "docora"
  spec.version       = Docora::VERSION
  spec.authors       = ["Dakota Lightning"]
  spec.email         = ["im@koda.io"]

  spec.summary       = %q{Run your rails app in docker using docker compose}
  spec.description   = %q{The intention is use this to dockerify your rails project for use anywhere in development.}
  spec.homepage      = "http://github.com/dakotalightning/docora"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = '>= 2.0.0'

  spec.add_runtime_dependency 'thor', '~> 0.19'
  spec.add_runtime_dependency 'rainbow', '~> 2.0'
  spec.add_runtime_dependency 'highline', '~> 1.7'
  spec.add_development_dependency 'rake', '~> 10.5'
  spec.add_development_dependency 'rspec', '~> 5.8'
end
