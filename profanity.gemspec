# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'profanity/version'

Gem::Specification.new do |spec|
  spec.name          = "profanity"
  spec.version       = Profanity::VERSION
  spec.authors       = ["Tillmen"]
  spec.email         = ["tillmen@lichproject.org"]
  spec.summary       = %q{A terminal frontend for Simutronics games}
  spec.homepage      = "http://lichproject.org/"
  spec.license       = "GPL-2"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
end
