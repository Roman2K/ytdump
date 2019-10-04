require 'soundcloud'
require 'utils'

class Client
  def initialize(credentials, log: Utils::Log.new)
    @log = log
    @sc = with_retry("SC.new") { SoundCloud.new credentials }
  end

  def get_paginated(path, &block)
    res = with_retry "first page" do
      @sc.get path, limit: 100, linked_partitioning: 1
    end
    loop do
      if res.kind_of? Hashie::Array
        res.each &block
        break
      end
      res.collection.each &block
      url = res.next_href or break
      res = with_retry "next page" do
        @sc.get url
      end
    end
  end

  SERVER_ERR = -> e do
    SoundCloud::ResponseError === e && e.response.code.to_s[0] == ?5
  end

  private def with_retry(action)
    Utils.retry 10, SERVER_ERR, wait: ->{ 1+rand } do |n|
      @log[attempt: n].debug "attempting #{action}" do
        yield
      end
    end
  end
end


if $0 == __FILE__
  credentials = File.open("credentials.yml", 'r') { |f| YAML.load f }.
    transform_keys &:to_sym

  cli = Client.new credentials
  cli.get_paginated '/me/favorites' do |track|
    JSON.dump track, $stdout
  end
end
