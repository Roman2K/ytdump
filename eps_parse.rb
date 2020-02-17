require 'net/http'
require 'digest/sha1'
require 'utils'

module EpsParse
  @parsers = []
  def self.parser_autoload(name, path, parser: true)
    autoload(name, __dir__ + '/eps_parse/' + path).tap do
      @parsers << name if parser
    end
  end

  parser_autoload :Parser, 'parser', parser: false
  parser_autoload :ReplayTivi, 'replaytivi'
  parser_autoload :TF1, 'tf1'
  parser_autoload :AnabolicTV, 'anabolictv'
  parser_autoload :MTV, 'mtv'
  parser_autoload :FranceTV, 'francetv'
  parser_autoload :Mitele, 'mitele'

  def self.all
    @parsers.map { |name| const_get(name).new }
  end

  REQ_HEADERS = {
    'Cache-Control' => 'no-cache',
    'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:67.0)' \
      ' Gecko/20100101 Firefox/67.0',
  }.freeze

  module RequestCache
    def request_get(uri)
      dir = @cache_path or return do_request_get uri
      path = dir.join Digest::SHA1.hexdigest(uri.to_s)
      $stderr.puts "reading cached page #{uri} at #{path.basename}"
      if ENV["CLEAR_CACHE"] == "1" && path.file?
        $stderr.puts "deleting #{path}"
        path.delete
      end
      begin
        path.open('r') { |f| Marshal.load f }
      rescue Errno::ENOENT
        $stderr.puts "cache MISS"
        do_request_get(uri).tap do |resp|
          path.open('w') { |f| Marshal.dump resp, f }
          $stderr.puts "written %s" % Utils::Fmt.size(path.size)
        end
      end.tap do
        yield path if block_given?
      end
    end
  end

  module RequestCacheGC
    def self.extended(obj)
      obj.__send__ :setup_request_cache_gc_summary!
    end

    private def setup_request_cache_gc_summary!
      @cache_paths = Set.new
      @used_cache = Set.new
      Minitest.after_run do
        all = @cache_paths.inject(Set.new) { |set, dir| set.merge dir.glob "*" }
        extra = (all - @used_cache)
        pp \
          all: all.size,
          used: @used_cache.size,
          unused: extra.size,
          extra: extra
        $stdout.print "Delete %d extras? " % [extra.size]
        $stdin.gets
        require 'fileutils'
        FileUtils.rm extra.to_a
      end
    end

    def request_get(*)
      @cache_paths << @cache_path if @cache_path
      super do |path|
        @used_cache << path
      end
    end
  end

  extend self
  extend RequestCache
  extend RequestCacheGC if ENV["PAGES_CACHE_GC"] == "1"

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
