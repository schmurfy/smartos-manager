
require 'net/ssh'
require 'net/ssh/gateway'
require 'psych'


class SSHHost
  def initialize(address, gateway: nil, gateway_user: nil user: 'root')
    if gateway
      @gateway = Net::SSH::Gateway.new(gateway, user)
      @ssh = @gateway.ssh(address, gateway_user || user, paranoid: false)
      
    else
      @ssh = Net::SSH.start(address, user, paranoid: false )
      
    end
  end
  
  def run(cmd)
    ret = nil
    @ssh.exec(cmd) do |ch, stream, data|
      ret = data
    end
    
    @ssh.loop{ ret == nil }
    
    ret.strip
  end
end


class HostRegistry
  def initialize(path)
    data = Psych.load_file(path)
    p data
  end
end
