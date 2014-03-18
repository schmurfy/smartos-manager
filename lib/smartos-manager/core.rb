
require 'net/ssh'
require 'net/ssh/multi'
require 'net/ssh/gateway'
require 'toml'
require 'size_units'


class SSHHost
  attr_reader :name
  attr_reader :address, :user
  attr_reader :gateway
  
  def self.from_hash(name, h, global_h)
    new(
        name:         name,
        address:      h['address'],
        gateway:      h['gateway'] || global_h['gateway'],
        user:         h['user'] || global_h['user'],
        gateway_user: h['gateway_user'] || global_h['gateway_user']
      )
  end
  
  def initialize(name: nil, address: nil, gateway: nil, user: nil, gateway_user: nil)
    raise "address required" unless address
    
    @name= name
    
    @address = address
    @user = user
    
    @gateway = gateway
    @gateway_user = gateway_user
  end
  
  def user
    @user || 'root'
  end
  
  def gateway_user
    @gateway_user || user
  end
  
end


class VirtualMachine
  attr_reader :uuid, :type, :memory, :state, :name, :admin_ip
    
  def initialize(data = {})
    @uuid = data.delete('uuid')
    @type = data.delete('type')
    @memory = data.delete('ram').to_i.megabytes
    @state = data.delete('state')
    @name = data.delete('alias')
    @admin_ip = data.delete('nics.0.ip')
    
    @user_data = data
  end
  
  def [](key)
    @user_data[key]
  end
end

class HostRegistry
  attr_reader :user_columns
  
  def initialize(path)
    @registry = {}
    @gateways = {}
    @hosts = {}
    
    @connection = Net::SSH::Multi.start()
    
    data = TOML.load_file(path)
    
    global_data = data.delete('global')
    user_columns = data.delete('user_columns') || {}
    
    data.each do |name, opts|
      host = SSHHost.from_hash(name, opts, global_data)
      
      @hosts[host.address] = host
      
      @connection.use(host.address,
          via: gateway_for(host.gateway, host.gateway_user),
          # via: @gateways[host.gateway],
          user: host.user,
          compression: false
        )
      
      # user defined columns
      @user_columns = user_columns
    end
    
  end
  
  def run_on_all(cmd)
    ret = {}
    
    # setthe keys in cas we get nothing back
    @hosts.each do |_, h|
      ret[h] = ""
    end
    
    channel = @connection.exec(cmd) do |ch, stream, data|
      host = @hosts[ch[:host]]
      ret[host] << data
    end
    
    channel.wait()
    ret
  end
  
  LIST_COLUMNS = %w(
    uuid
    type
    ram
    state
    alias
    nics.0.ip
  )
  
  def list_vms
    columns = LIST_COLUMNS + @user_columns.values
    
    vms = run_on_all("vmadm list -o #{columns.join(',')} -p")
    vms.each do |host, data|
      if data
        vms[host] = data.split("\n").map! do |line|
          data = {}
          line.split(':', 20).each.with_index do |val, n|
            data[columns[n]] = val
          end
          
          VirtualMachine.new(data)
        end
      else
        vms[host] = []
      end
    end
    
  end
  
  
  def sysinfo
    ret = {}
    
    # Memory size: 8157 Megabytes
    run_on_all("prtconf | head -3 | grep Mem").each do |host, data|
      _, _, mem, _ = data.split(" ")
      ret[host] = {memory: mem.to_i.megabytes}
    end
    
    # ARC Max Size
    # zfs:0:arcstats:c:2850704524
    # zfs:0:arcstats:size:1261112216
    run_on_all("kstat -C zfs:0:arcstats:c zfs:0:arcstats:size").each do |host, data|
      zfs_arc_current = nil
      zfs_arc_reserved = nil
      
      data.split("\n").each do |line|
        value = line.split(':').last.to_i
        if line.start_with?('zfs:0:arcstats:size:')
          zfs_arc_current = value
        else
          zfs_arc_reserved = value
        end
      end
      
      ret[host].merge!(
          zfs_arc_current: zfs_arc_current,
          zfs_arc_reserved: zfs_arc_reserved
        )
    end
    
    # joyent_20140207T053435Z
    run_on_all("uname -a | cut -d ' ' -f 4").each do |host, data|
      _, rev = data.strip().split('_')
      ret[host][:smartos_version] = rev
    end
    
    ret
  end
  
private
  def gateway_for(host, user)
    @gateways[host] ||= Net::SSH::Gateway.new(
        host,
        user,
        compression: false
      )
  end
    
end
