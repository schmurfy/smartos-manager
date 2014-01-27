
require 'net/ssh'
require 'net/ssh/multi'
require 'net/ssh/gateway'
require 'psych'
require 'size_units'


class SSHHost
  attr_reader :name
  attr_reader :address, :user
  attr_reader :gateway
  
  def self.from_yaml(name, h)
    new(
        name:         name,
        address:      h['address'],
        gateway:      h['gateway'],
        user:         h['user'],
        gateway_user: h['gateway_user']
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
  
# private
#   def connection
#     unless @connection
#       if @gateway
#         @gateway_obj = Net::SSH::Gateway.new(@gateway, @user)
#         @connection = @gateway_obj.ssh(@address, @gateway_user || @user, SSH_OPTIONS)
        
#       else
#         @connection = Net::SSH.start(@address, @user,  SSH_OPTIONS)
        
#       end

#     end
    
#     @connection
#   end
end


class VirtualMachine
  attr_reader :uid, :type, :memory, :state, :name, :admin_ip
  
  def initialize(uid, type, memory, state, name, admin_ip)
    @uid = uid
    @type = type
    @memory = memory.to_i.megabytes
    @state = state
    @name = name
    @admin_ip = admin_ip
  end
  
  # 4c1ae27f-a986-4189-a2b7-5c5e6d2e26ef:OS:300:running:backup
  def self.from_line(line)
    new(*line.split(':'))
  end
end

class HostRegistry
  def initialize(path)
    @registry = {}
    @gateways = {}
    @hosts = {}
    
    @connection = Net::SSH::Multi.start()
    
    data = Psych.load_file(path)
    data.each do |name, opts|
      host = SSHHost.from_yaml(name, opts)
      
      @hosts[host.address] = host
      
      @connection.use(host.address,
          via: gateway_for(host.gateway, host.gateway_user),
          # via: @gateways[host.gateway],
          user: host.user,
          compression: false
        )
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
  
  def list_vms
    vms = run_on_all("vmadm list -o uuid,type,ram,state,alias,nics.0.ip -p")
    vms.each do |host, data|
      if data
        vms[host] = data.split("\n").map! do |line|
          VirtualMachine.from_line(line)
        end
      else
        vms[host] = []
      end
    end
    
  end
  
  
  def sysinfo
    ret = {}
    
    # Memory size: 8157 Megabytes
    hosts = run_on_all("prtconf | head -3 | grep Mem")
    hosts.each do |host, data|
      _, _, mem, _ = data.split(" ")
      ret[host] = {memory: mem.to_i.megabytes}
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
