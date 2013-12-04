require 'rubygems'

gem "eventmachine"
gem "eventmachine_httpserver"

require './eval'
require './client'
require './commands'
require "eventmachine"
require "evma_httpserver"

class Client < EM::Connection
  @@clients = {}

  def unbind
    @@clients.delete id
  end

  def initialize
    @@clients[id] = self
  end

  def id
    [self.hash].pack("Q").unpack("H*")[0]
  end

  def self.[](v)
    @@clients[v]
  end

  def receive_data(data)

  end
end

class MyHttpServer < EM::Connection
  include EM::HttpServer

  def post_init
    super
    no_environment_strings
  end

  def process_http_request
    port, ip = Socket.unpack_sockaddr_in(get_peername)
    p "#{ip}:#{port} #{@http_request_method} #{@http_path_info}"

    response = EM::DelegatedHttpResponse.new(self)
    response.status = 200
    response.content_type 'text/html'

    case @http_path_info
    when "/connect"

    else
      response.status = 404
    end

    response.send_response
  end
end

EM.run do
  EM.start_server '::1', 8080, MyHttpServer
end
