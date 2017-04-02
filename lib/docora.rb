require 'thor'
require 'rainbow'
require 'yaml'
require 'highline'

require "docora/version"

# Starting 2.0.0, Rainbow no longer patches string with the color method by default.
require 'rainbow/version'
require 'rainbow/ext/string' unless Rainbow::VERSION < '2.0.0'

module Docora
  autoload :Cli,        'docora/cli'
  autoload :Logger,     'docora/logger'
  autoload :Utility,    'docora/utility'
end
