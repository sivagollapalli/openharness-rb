# frozen_string_literal: true

require_relative "lib/openharness/rb/version"

Gem::Specification.new do |spec|
  spec.name = "openharness-rb"
  spec.version = Openharness::Rb::VERSION
  spec.authors = ["Siva Gollapalli"]
  spec.email = ["sgollapalli@csod.com"]

  spec.summary = "Ruby port of OpenHarness - lightweight agent infrastructure"
  spec.description = "openharness-rb provides lightweight infrastructure to turn an LLM into a functional agent, supporting tool-use, skills, memory, permissions, hooks, and multi-agent coordination."
  spec.homepage = "https://github.com/HKUDS/OpenHarness"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/HKUDS/OpenHarness"
  spec.metadata["changelog_uri"] = "https://github.com/HKUDS/OpenHarness/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "dry-types", "~> 1.7"
  spec.add_dependency "dry-struct", "~> 1.6"
  spec.add_dependency "dry-validation", "~> 1.10"
  spec.add_dependency "ruby_llm", "~> 1.0"
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "async", "~> 2.0"
  spec.add_dependency "listen", "~> 3.8"
  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "serpapi", "~> 1.0", ">= 1.0.3"
  spec.add_dependency "ruby_llm-mcp", "~> 0.4"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
