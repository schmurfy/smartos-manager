
require 'net/ssh'
require 'net/ssh/multi'
require 'net/ssh/gateway'
require 'toml'
require 'size_units'
require 'json'


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
  attr_reader :uuid, :type, :memory, :rss, :state, :name, :admin_ip
    
  def initialize(data = {}, rss = {})
    @uuid = data.delete('uuid')
    @type = data.delete('type')
    @memory = data.delete('ram').to_i.megabytes
    @state = data.delete('state')
    @name = data.delete('alias')
    @admin_ip = data.delete('nics.0.ip')
    @rss = rss[@uuid]
    
    @user_data = data
  end
  
  def [](key)
    @user_data[key]
  end
end


class Image
  attr_reader :uuid, :name, :version, :os
  
  def initialize(data = {})
    @uuid = data.delete('uuid')
    @name = data.delete('name')
    @version = data.delete('version')
    @os = data.delete('os')
  end
end


class Registry
  LIST_COLUMNS = %w(
    uuid
    type
    ram
    state
    alias
    nics.0.ip
  )

  attr_reader :user_columns

  def initialize(path, cache_key:)
    @registry = {}
    @hosts = {}
    @config_path = path
    @cache_path = "#{path}.cache"
    @cache = load_cache()
    @cache_key = cache_key
    
    @config = TOML.load_file(path)
    
    @global_data = @config.delete('global')
    @user_columns = @config.delete('user_columns') || {}
    
    @config.each do |name, opts|
      host = SSHHost.from_hash(name, opts, @global_data)
      @hosts[host.address] = host
    end
  end
  
  def find_host(addr)
    @hosts[addr]
  end
  
  def list_vms
    columns = LIST_COLUMNS + @user_columns.values
    
    ret = {}
    rss = {}
    
    # Memory used for each VM
    run_on_all("zonememstat").each do |_, data|
      data.split("\n").each do |line|
        # ignore headers / global
        unless line.start_with?('  ')
          uuid, used_mem, cap, _, _ = line.gsub(/\s+/, ' ').split(" ")
          rss[uuid] = used_mem.to_i.megabytes
        end
      end
    end
    
    vms = run_on_all("vmadm list -o #{columns.join(',')} -p")
    vms.each do |addr, data|
      host = find_host(addr)
      if data
        ret[host] = data.split("\n").map! do |line|
          dd = {}
          line.split(':', 20).each.with_index do |val, n|
            dd[columns[n]] = val
          end
          
          VirtualMachine.new(dd, rss)
        end
      else
        ret[host] = []
      end
    end
    
    ret
  end
  
  def list_images
    ret = {}
    
    columns = %w(uuid name version os)
    
    images = run_on_all("imgadm list -j")
    images.each do |addr, data|
      host = find_host(addr)
      json = JSON.parse(data)
      
      ret[host] = json.map do |img_data|
        Image.new( img_data['manifest'] )
      end
    end
    
    ret
  end
  
  
  def diag
    ret = {}
    
    run_on_all("prtdiag").each do |addr, data|
      host = find_host(addr)
      system_id = "(none)"
      free_memory_banks = 0
      
      if matches = data.match(/^System Configuration: (.+)$/)
        system_id = matches[1]
        data.scan(/(empty).*DIMM\s+([0-9])/).each do |reg|
          free_memory_banks+= 1
        end
      end
      
      ret[host] = {
        system_id: system_id,
        free_memory_banks: free_memory_banks
      }
    end
    
    ret
  end
  
  def sysinfo
    ret = {}
    
    # Memory size: 8157 Megabytes
    run_on_all("prtconf | head -3 | grep Mem").each do |addr, data|
      host = find_host(addr)
      _, _, mem, _ = data.split(" ")
      ret[host] = {memory: mem.to_i.megabytes}
    end
    
    # main MAC address
    run_on_all("ifconfig e1000g0 | grep ether | cut -d ' ' -f 2").each do |addr, data|
      host = find_host(addr)
      ret[host][:mac0] = data.strip()
    end
    
    # disk infos
    run_on_all("diskinfo -Hp").each do |addr, data|
      host = find_host(addr)
      ret[host][:disks] = {}
      
      data.split("\n").each do |line|
        type, name, _, _, size_bytes, _, ssd = line.split("\t")
        ret[host][:disks][name] = {size: size_bytes.to_i}
      end
    end
    
    # disk size
    run_on_all("zfs list -Ho name,quota,volsize").each do |addr, data|
      host = find_host(addr)
      ret[host][:zfs_volumes] = {}
      
      data.split("\n").each do |line|
        name, quota, size = line.split("\t")
        ret[host][:zfs_volumes][name] = {size: size[0...-1].split(',').first, quota: quota[0...-1].split(',').first}
      end
    end
    
    # ARC Max Size
    # zfs:0:arcstats:c:2850704524
    # zfs:0:arcstats:size:1261112216
    run_on_all("kstat -C zfs:0:arcstats:c zfs:0:arcstats:size").each do |addr, data|
      host = find_host(addr)
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
    run_on_all("uname -a | cut -d ' ' -f 4").each do |addr, data|
      host = find_host(addr)
      _, rev = data.strip().split('_')
      ret[host][:smartos_version] = rev
    end
    
    ret
  end

private
  def cache_result(cmd, result)
    @cache[@cache_key] ||= {}
    @cache[@cache_key][cmd] = result
    data = Oj.dump(@cache, indent: 2)
        
    IO.write(@cache_path, data)
  end
  
  def load_cache
    Oj.load_file(@cache_path)
  rescue Oj::ParseError, IOError => err
    {}
  end

end


class CachedRegistry < Registry
  def initialize(*)
    puts "(( Using cached data ))"
    super
  end
  
  def run_on_all(cmd)
    if @cache[@cache_key] && @cache[@cache_key][cmd]
      @cache[@cache_key][cmd]
    else
      puts "[#{@cache_key}] missing cache for cmd: '#{cmd}'"
      {}
    end
  end
  
  def failed_connections
    []
  end
end


class SSHRegistry < Registry
  def initialize(*)
    puts "(( Using live data ))"
    super
    
    @failed_connections = []
    
    @gateways = {}
    @connection = Net::SSH::Multi.start(:on_error => ->(server){
        @failed_connections << server.host
      })
    
    @hosts.each do |_, host|
      @connection.use(host.address,
          via: gateway_for(host.gateway, host.gateway_user),
          user: host.user,
          timeout: 20,
          auth_methods: %w(publickey),
          compression: false
        )
    end
  end
  
  def run_on_all(cmd)
    ret = {}
    
    # set the keys in cas we get nothing back
    # @hosts.each do |addr, _|
    #   ret[addr] = ""
    # end
    
    channel = @connection.exec(cmd) do |ch, stream, data|
      host = @hosts[ch[:host]]
      ret[host.address] << data
    end
    
    channel.wait()
    
    cache_result(cmd, ret)
    
    ret
  end
  
  def failed_connections
    @failed_connections.map{|address| @hosts[address] }
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
