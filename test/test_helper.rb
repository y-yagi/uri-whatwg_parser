# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "simplecov"
SimpleCov.start

require "uri/whatwg_parser"
require "debug"
require "test/unit"
require "core_assertions"

Test::Unit::TestCase.include Test::Unit::CoreAssertions
