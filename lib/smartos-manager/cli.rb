
require File.expand_path('../core', __FILE__)
require 'thor'
require 'colored'

class AppCLI < Thor
  desc "list", "List all vms"
  def list
    registry = HostRegistry.new('smartos_hosts.toml')
    ret = registry.list_vms()
    
    sysinfos = registry.sysinfo()
    
    p_vm_list("Memory", "Name", "Type", "UUID", "State", "Admin IP")
    
    ret.each do |host, vms|
      mem = sysinfos[host][:memory]
      vm_memory = 0
      
      vms.each{|vm| vm_memory += vm.memory }
      avail = (mem - vm_memory) - (20 * mem/100.0)
      
      puts "\n#{host.name} (#{host.address})  (#{vms.size} vms)  (Total RAM: #{mem.human_size(1).green}, Avail: #{avail.human_size(1).magenta})"
      vms.each do |vm|
        p_vm_list(vm.memory.human_size(1), vm.name, vm.type, vm.uid, printable_state(vm.state), vm.admin_ip)
      end
      
      if vms.empty?
        puts "  [ no VMS                     ]"
      end
      
      # avail = (mem - vm_memory) - (20 * mem/100)
      # puts "  Available Memory: #{avail.human_size(1)}".magenta()
    end
    
  end
  
  
  no_tasks do
    
    def p_vm_list(size, name, type, uuid, state, admin_ip)
      puts "  [ #{size.rjust(6)} #{name.rjust(15)} - #{uuid.ljust(37)}][ #{admin_ip.ljust(15).cyan} ][ #{state} ]"
    end
    
    def printable_state(state)
      if state =='running'
        state.green()
      else
        state.red()
      end
    end
    
  end
end
  
