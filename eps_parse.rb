require 'net/http'

module EpsParse
  REQ_HEADERS = {
    'Cache-Control' => 'no-cache',
    'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:67.0)' \
      ' Gecko/20100101 Firefox/67.0',
  }.freeze

  def self.request_get(uri)
    Net::HTTP.start uri.host, uri.port, use_ssl: uri.scheme == 'https' do |http|
      http.request_get uri, REQ_HEADERS
    end
  end

  def self.request_get!(uri)
    request_get(uri).tap do |resp|
      resp.kind_of? Net::HTTPSuccess or raise "unexpected response: %p" % resp
    end
  end
end
