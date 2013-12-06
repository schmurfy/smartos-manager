
require File.expand_path('../core', __FILE__)
require 'thor'

class AppCLI < Thor
  desc "list", "List all vms"
  def list
    registry = HostRegistry.new('hosts.yml')
  end
end
  
