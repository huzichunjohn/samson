# frozen_string_literal: true
require 'bundler/setup'
raise "ENV clearing failed" if File.expand_path(ENV.fetch("BUNDLE_GEMFILE")) != File.expand_path("Gemfile")
require_relative 'dotenv'
rails_env = ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
if ['development', 'test'].include?(rails_env)
  require 'bootsnap'
  Bootsnap.setup(
    cache_dir:            'tmp/bootsnap', # Path to your cache
    development_mode:     rails_env == "development",
    load_path_cache:      true, # Should we optimize the LOAD_PATH with a cache?
    autoload_paths_cache: true, # Should we optimize ActiveSupport autoloads with cache?
    disable_trace:        false, # Sets `RubyVM::InstructionSequence.compile_option = { trace_instruction: false }`
    compile_cache_iseq:   true, # Should compile Ruby code into ISeq cache?
    compile_cache_yaml:   true # Should compile YAML into a cache?
  )
end
