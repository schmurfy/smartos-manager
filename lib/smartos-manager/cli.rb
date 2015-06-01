
require File.expand_path('../core', __FILE__)
require 'thor'
require 'colored'


class ColorPicker
  
  def initialize
    @colors = {}
    @available_colors = %w(green yellow cyan magenta blue red gray white)
  end
  
  def get(str)
    @colors[str] ||= @available_colors.shift()
  end
  
end

class AppCLI < Thor
  
  desc "list_images", "List images available"
  def list_images
    registry = HostRegistry.new('smartos_hosts.toml')
    ret = registry.list_images()
    
    rev_colors = ColorPicker.new
    p_img_list("UUID", "Name", "Version", "OS")
    
    ret.each do |host, images|
      puts "\n#{host.name} - #{host.address}"
      images.each do |img|
        # color = rev_colors.get(img.uuid)
        p_img_list( img.uuid, img.name, img.version, img.os)
      end
    end
  end
  
  desc "list", "List all vms"
  def list
    registry = HostRegistry.new('smartos_hosts.toml')
    ret = registry.list_vms()
    
    rev_colors = ColorPicker.new
    
    sysinfos = registry.sysinfo()
    diags = registry.diag()
    
    user_columns = registry.user_columns.keys.map{|s| humanize(s) }
    
    p_vm_list("Memory", "Name (gray = online)", "Type", "UUID", "State", "Admin IP", "DD(GB)", *user_columns)
    
    ret.each do |host, vms|
      mem = sysinfos[host][:memory]
      zfs_arc_reserved = sysinfos[host][:zfs_arc_reserved]
      zfs_arc_current = sysinfos[host][:zfs_arc_current]
      vm_memory = 0
      
      vms.each{|vm| vm_memory += vm.memory }
      # avail = (mem - vm_memory) - (20 * mem/100.0)
      avail = [1, (mem - vm_memory) - zfs_arc_current].max
      
      dd = sysinfos[host][:disks].map{|_, d| "#{format_size(d[:size])} GB" }.join(" - ")
      
      rev = sysinfos[host][:smartos_version]
      puts "\nHardware: #{diags[host][:system_id]} (MAC: #{sysinfos[host][:mac0].upcase.white()}, IP: #{host.address.white()} )"
      puts "HDD: #{sysinfos[host][:disks].keys.size} drives - #{dd}"
      puts "#{host.name} [SmartOS: #{rev.send(rev_colors.get(rev))}] (Free RAM: #{avail.human_size(1).green}/#{mem.human_size(1)} [Free Slots: #{diags[host][:free_memory_banks]}], ZFS: #{format_size(zfs_arc_current)}G/#{format_size(zfs_arc_reserved)}G)"
      vms.each do |vm|
        user_columns = registry.user_columns.values.map{|key| vm[key] }
        
        if vm.type == "KVM"
          vm_disk = sysinfos[host][:zfs_volumes]["zones/#{vm.uuid}-disk0"]
          vm_disk_label = "#{vm_disk[:size]}"
        else
          vm_disk = sysinfos[host][:zfs_volumes]["zones/#{vm.uuid}"]
          vm_disk_label = "#{vm_disk[:quota]}"
        end
        
        if vm.rss
          tmp = vm.rss.human_size(1)
        else
          tmp = "-"
        end
        formatted_mem = "#{tmp.ljust(5)} / #{vm.memory.human_size(1).ljust(5)}"
        
        p_vm_list(formatted_mem, vm.name, vm.type, vm.uuid, vm.state, vm.admin_ip, vm_disk_label, *user_columns)
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
    
    # (uuid name version os)
    def p_img_list(uuid, name, version, os)
      name ||= '-'
      version ||= '-'
      os ||= '-'
      puts "  [ #{uuid.ljust(37)}]  #{name.ljust(30)} #{version.ljust(6)} #{os}"
    end
    
    def p_vm_list(size, name, type, uuid, state, admin_ip, disk_label, *user_columns)
      tmp = user_columns.map{|val| "[ #{format_generic(val).to_s.ljust(15).cyan} ]" }.join('')
      
      if name.start_with?('Name')
        name = name.white()
      else
        state_color =  case state
          when 'running' then :white
          else
            :red
        end
        
        name = name.send(state_color)
      end
      
      line = build_vm_list_string(
          size,
          name,
          disk_label,
          uuid,
          format_generic(admin_ip).ljust(15).cyan,
          tmp
        )
      #line = "  [ #{size.rjust(6)}  #{name.ljust(35)} - #{disk_label.rjust(5)} - #{uuid.ljust(37)}][ #{format_generic(admin_ip).ljust(15).cyan} ]#{tmp}"
      
      puts line
    end
    
    def build_vm_list_string(size, name, disk_label, uuid, admin_ip, rest)
      "  [ #{size.rjust(14)}  #{name.ljust(35)} - #{disk_label.rjust(5)} - #{uuid.ljust(37)}][ #{admin_ip} ]#{rest}"
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
  
