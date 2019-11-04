require 'yaml'

class Playlist
  def self.load(io)
    info = YAML.load io
    proxies = info.delete("proxies") || {}
    pls = info.delete("playlists") || {}
    info.keys.empty? or raise "extra keys: %p" % [infos.keys]
    pls.delete_if { |k,| k.start_with? "_" } # YAML backreferences
    pls.map do |name, info|
      info["proxy"] &&= proxies.fetch(info["proxy"]) { info["proxy"] }
      new name, info.transform_keys(&:to_sym)
    end
  end

  def initialize(name, opts)
    @name = name
    @opts = opts.dup
  end

  attr_reader :name
  def opts; after_filter { @opts } end
  def urls; after_filter { @urls } end
  def proxy; after_filter { @proxy } end

  def done(rclone)
    dest = opts[:rclone_dest] or return []
    rclone.run("-v", "lsf", dest).split("\n")
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
    @opts[:rclone_dest] += name if @opts[:rclone_dest].end_with? "/"
    @proxy = @opts.delete :proxy
    @urls = [*@opts.delete(:url), *@opts.delete(:urls)]
    @opts.freeze
  end

  FILTERS = {
    "exe" => -> cmd {
      Bundler.with_clean_env do
        IO.popen(cmd, 'r', &:read).tap do
          $?.success? or raise "command failed: %p" % [cmd]
        end
      end
    },
  }.freeze

  def setup_env
    @proxy or return yield
    keys = %w[http_proxy https_proxy]
    before = keys.map { |k| ENV[k] }
    keys.each { |k| ENV[k] = @proxy }
    begin
      yield
    ensure
      keys.zip(before) { |k,old| ENV[k] = old }
    end
  end
end
