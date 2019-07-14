require 'net/http'
require 'digest/sha1'
require 'utils'

module EpsParse
  extend self

  REQ_HEADERS = {
    'Cache-Control' => 'no-cache',
    'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:67.0)' \
      ' Gecko/20100101 Firefox/67.0',
  }.freeze

  def request_get(uri)
    dir = @cache_path or return do_request_get uri
    path = dir.join Digest::SHA1.hexdigest(uri.to_s)
    $stderr.puts "reading cached page #{uri} at #{path.basename}"
    begin
      path.open('r') { |f| Marshal.load f }
    rescue Errno::ENOENT
      $stderr.puts "cache MISS"
      do_request_get(uri).tap do |resp|
        path.open('w') { |f| Marshal.dump resp, f }
        $stderr.puts "written %s" % Utils::Fmt.size(path.size)
      end
    end
  end

  private def do_request_get(uri)
    Net::HTTP.start uri.host, uri.port, use_ssl: uri.scheme == 'https' do |http|
      http.request_get uri, REQ_HEADERS
    end
  end

  def request_get!(uri)
    request_get(uri).tap do |resp|
      resp.kind_of? Net::HTTPSuccess or raise "unexpected response: %p" % resp
    end
  end

  def with_cache(path)
    old, @cache_path = @cache_path, path
    begin
      yield
    ensure
      @cache_path = old
    end
  end
end
