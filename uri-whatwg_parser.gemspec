# frozen_string_literal: true

require_relative "lib/uri/whatwg_parser/version"

Gem::Specification.new do |spec|
  spec.name = "uri-whatwg_parser"
  spec.version = URI::WhatwgParser::VERSION
  spec.authors = ["Yuji Yaginuma"]
  spec.email = ["yuuji.yaginuma@gmail.com"]

  spec.summary = "Ruby implementation of the WHATWG URL Living Standard"
  spec.homepage = "https://github.com/y-yagi/uri-whatwg_parser"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile benchmark])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "uri", ">= 1.1.0"
  spec.add_dependency "uri-idna"
  spec.add_development_dependency "debug"
end
