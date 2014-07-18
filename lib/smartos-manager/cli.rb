
require File.expand_path('../core', __FILE__)
require 'thor'
require 'colored'


class ColorPicker
  
  def initialize
    @colors = {}
    @available_colors = %w(green yellow red cyan magenta blue)
  end
  
  def get(str)
    @colors[str] ||= @available_colors.shift()
  end
  
end

class AppCLI < Thor
  desc "list", "List all vms"
  def list
    registry = HostRegistry.new('smartos_hosts.toml')
    ret = registry.list_vms()
    
    rev_colors = ColorPicker.new
    
    sysinfos = registry.sysinfo()
    diags = registry.diag()
    
    user_columns = registry.user_columns.keys.map{|s| humanize(s) }
    
    p_vm_list("Memory", "Name", "Type", "UUID", "State", "Admin IP", *user_columns)
    
    ret.each do |host, vms|
      mem = sysinfos[host][:memory]
      zfs_arc_reserved = sysinfos[host][:zfs_arc_reserved]
      zfs_arc_current = sysinfos[host][:zfs_arc_current]
      vm_memory = 0
      
      vms.each{|vm| vm_memory += vm.memory }
      # avail = (mem - vm_memory) - (20 * mem/100.0)
      avail = [1, (mem - vm_memory) - zfs_arc_reserved].max
      
      rev = sysinfos[host][:smartos_version]
      puts "\nHardware: #{diags[host][:system_id]}"
      puts "#{host.name} [SmartOS: #{rev.send(rev_colors.get(rev))}] (#{host.address}) (Total RAM: #{mem.human_size(1).green} [Free Slots: #{diags[host][:free_memory_banks]}], ZFS: #{format_size(zfs_arc_current)}G/#{format_size(zfs_arc_reserved)}G, Avail: #{avail.human_size(1).magenta})"
      vms.each do |vm|
        user_columns = registry.user_columns.values.map{|key| vm[key] }
        p_vm_list(vm.memory.human_size(1), vm.name, vm.type, vm.uuid, printable_state(vm.state), vm.admin_ip, *user_columns)
      end
      
      if vms.empty?
        puts "  [ no VMS                     ]"
      end
      
      # avail = (mem - vm_memory) - (20 * mem/100)
      # puts "  Available Memory: #{avail.human_size(1)}".magenta()
    end
    
  end
  
  
  no_tasks do
    
    def format_size(val, unit = 3)
      format('%.1f', val / (1024.0**unit))
    end
    
    def humanize(str)
      str.split("_").map(&:capitalize).join(' ')
    end
    
    def format_generic(str)
      str
    end
    
    def p_vm_list(size, name, type, uuid, state, admin_ip, *user_columns)
      tmp = user_columns.map{|val| "[ #{format_generic(val).to_s.ljust(15).cyan} ]" }.join('')
      puts "  [ #{size.rjust(6)}  #{name.ljust(20)} - #{uuid.ljust(37)}][ #{format_generic(admin_ip).ljust(15).cyan} ]#{tmp}[ #{state} ]"
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
  
