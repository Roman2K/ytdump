require 'yaml'

class Playlist
  def self.load(io, log:, default_proxy: nil)
    info = YAML.load io
    proxies = info.delete("proxies") || {}
    proxy_rules = info.delete("proxy_rules") || {}
    pls = info.delete("playlists") || {}
    info.empty? or raise "extra keys: %p" % [infos.keys]
    pls.delete_if { |k,| k.start_with? "_" } # YAML backreferences
    pls.map do |name, opts|
      proxy_conf = ProxyConf.new proxy_rules, proxies,
        default: opts.delete("proxy") || default_proxy
      new name, opts.transform_keys(&:to_sym), proxy_conf: proxy_conf, log: log
    end
  end

  def initialize(name, opts, proxy_conf:, log:)
    @name = name
    @opts = opts.dup
    @proxy_conf = proxy_conf
    @log = log
  end

  attr_reader :name
  attr_reader :proxy_conf
  def opts; after_filter { @opts } end
  def urls; after_filter { @urls } end

  def done(rclone)
    dest = opts[:rclone_dest] or return []
    begin
      rclone.run("-v", "lsf", dest).split("\n")
    rescue Exe::ExitError => err
      raise unless err.status == 3 && err.stderr =~ /\bdirectory not found\b/
      []
    end
  end

  private def after_filter
    filter_opts!
    yield
  end

  private def filter_opts!
    return if @opts.frozen?
    @opts.transform_values! do |v|
      if Hash === v && v.keys.size == 1 && filter = FILTERS[v.keys.fetch 0]
        filter[v.values.fetch 0]
      else
        v
      end
    end
    if @opts.delete(:audio)
      @opts[:ydl_opts] ||= []
      @opts[:ydl_opts] += %w[-x --audio-format mp3] 
    end
    @opts[:rclone_dest] += name if @opts[:rclone_dest]&.end_with? "/"
    @urls = [*@opts.delete(:url), *@opts.delete(:urls)]
    @opts.freeze
  end

  FILTERS = {
    "exe" => -> cmd {
      Bundler.with_original_env do
        IO.popen(cmd, 'r', &:read).tap do
          $?.success? or raise "command failed: %p" % [cmd]
        end
      end
    },
  }.freeze

  def setup_env
    url = @proxy_conf.url or return yield
    @log[proxy: url].info "setting HTTP proxy"
    keys = %w[http_proxy https_proxy]
    before = keys.map { |k| ENV[k] }
    keys.each { |k| ENV[k] = url }
    begin
      yield
    ensure
      keys.zip(before) { |k,old| ENV[k] = old }
    end
  end

  class ProxyConf
    def initialize(rules, proxies, default: nil)
      @rules = rules
      @proxies = proxies
      @default = default
      unless (extra = @rules.keys - EpsParse.all.map(&:name)).empty?
        raise "unknown parser in proxy rules: #{extra.inspect}"
      end
    end

    def url(parser=nil)
      key = (@rules[parser.name] if parser) || @default
      @proxies.fetch(key) { key }
    end
  end
end
