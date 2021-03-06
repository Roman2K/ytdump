require 'json'
require 'open3'
require 'fileutils'
require 'pathname'
require 'utils'
require 'set'
require_relative 'item'
require_relative 'eps_parse'
require_relative 'vidcat'
require_relative 'playlist'

class Downloader
  NTHREADS = 4

  def initialize(out:, meta:, done: [], cache: nil, log:,
    cleanup: true,
    dry_run: false,
    ydl_opts: [],
    min_duration: nil,
    rclone_dest: nil,
    nthreads: NTHREADS,
    sorted: false,
    check_empty: false,
    notfound_ok: false,
    retry_skipped: false,
    min_df: nil
  )
    @log = log
    @ydl = Exe.new "youtube-dl", *ydl_opts, log: @log["youtube-dl"]

    @cache_mv = false
    @cache = if cache
      if /^:/ =~ cache
        cache, @cache_mv = $', true
      end
      Pathname(cache).yield_self do |dir|
        dir.directory? or raise "cache is not a directory"
        dir.glob("**/*").select &:file?
      end
    else
      []
    end

    @out, @meta = [out, meta].map { |p|
      Pathname(p).tap do |dir|
        FileUtils.mkdir_p dir
      end
    }
    @done = done.map { |p| Pathname p }

    %i[ cleanup dry_run min_duration rclone_dest sorted check_empty notfound_ok
        retry_skipped min_df ].each \
    do |ivar|
      instance_variable_set "@#{ivar}", eval(ivar.to_s)
    end
    nthreads = 1 if @dry_run
    log_ivars

    @dled = Set_ThreadSafe.new
    @summary = Summary.new
    @stop = Var_ThreadSafe.new false
    @q = Queue.new
    @threads = nthreads.times.map do
      Thread.new do
        Thread.current.abort_on_exception = true
        while job = @q.shift
          dl job.fetch(:item), proxy: job.fetch(:proxy)
        end
      end
    end
    @log.info "started %d threads" % [@threads.size]

    if @rclone_dest
      rclone = Exe.new "rclone", log: @log["rclone"]
      @threads << Thread.new do
        Thread.current.abort_on_exception = true
        loop do
          sleep 1
          stop = @threads.count(&:alive?) <= 1
          rclone.run("move", "-v", "--exclude", "*.tmp", @out, @rclone_dest).
            tap { |out| puts out if out =~ /\S/ }
          break if stop
        end
      end
    end
  end

  private def log_ivars
    instance_variables.each do |ivar|
      val = instance_variable_get ivar
      val = 
        case
        when Utils::Log === val then next
        when Pathname === val then val.to_s
        when Exe === val then val.cmd
        when /_df$/ === ivar && val then fmt_df(val)
        when %i[@done @cache].include?(ivar) then val.size
        else val.inspect
        end
      @log.info "%s: %s" % [ivar.to_s.sub(/^@/, ""), val]
    end
  end

  private def parse_items(url)
    EpsParse.all.each do |p|
      items = begin
        p.playlist_items url
      rescue EpsParse::InvalidURIError
        next
      end
      return p, items
    end
    nil
  end

  def dl_playlist(url, proxy: nil)
    if File.file? url
      pl = File.read url
    elsif found = parse_items(url)
      parser, items = found
      @log[parser: parser.name, items: items.size].info "parser found items"
      @min_duration ||= parser.min_duration
      return dl_playlist_items items, proxy: proxy&.(parser).tap { |url|
        @log[parser: parser.name, proxy: url].
          info "setting parser-specific proxy" if url
      }
    else
      pl = begin
        get_playlist url
      rescue ThrottleError
        @log[err: $!].warn "throttled, aborting"
        return
      rescue Exe::ExitError => err
        if err.status == 1 && err.stderr =~ /404: Not Found/i && @notfound_ok
          @log.info "playlist not found but tolerated by setting, aborting"
          return
        end
        raise
      end
    end
    dl_playlist_json "[#{pl.split("\n") * ","}]"
  end

  def dl_playlist_json(s)
    items = JSON.parse(s).
      tap { |a| a.reverse! unless @sorted }.
      map.
      with_index { |attrs, idx| Item.from_json idx+1, attrs }

    dl_playlist_items items
  end

  def dl_playlist_items(items, proxy: nil)
    raise "empty playlist" if @check_empty && items.empty?
    if min = @min_duration
      @log[items: items.size].
        info "selecting items >= %s" % [Utils::Fmt.duration(min)]
      items.select! do |item|
        d = item.duration or raise "missing duration in item %p" % item
        d >= min
      end
    end
    @log.info "enqueueing %d playlist items" % items.size
    items.sort_by(&:idx).each { |i| @q << {item: i, proxy: proxy} }
  end

  def finish
    @q.close
    @threads.each &:join
    @log.info "downloaded #{@summary}"
  end

  class Summary
    def initialize
      @count, @size = 0, 0
    end

    def <<(size)
      @count += 1
      @size += size
      self
    end

    def to_s
      "%d files totalling %s" % [@count, Utils::Fmt.size(@size)]
    end
  end

  RETRIABLE_YTDL_PL_ERR = -> err do
    Exe::ExitError === err \
      && err.status == 1 \
      && err.stderr =~ /\bHTTP Error 5\d\d\b/i
  end

  private def get_playlist(*urls, full: !!@min_duration)
    pl_path = "pl-#{Digest::SHA256.hexdigest(urls * "|")}.json"
    @log[pl_path: pl_path].debug "attempting to read cached playlist"
    begin
      File.read(pl_path).tap do
        @log.info "read cached playlist"
      end
    rescue Errno::ENOENT
      do_get_playlist(urls, full)
    end
  end

  private def do_get_playlist(urls, full)
    urls = urls.map do |u|
      u = URI u
      orig = u.dup
      if u.host.to_s.split(".").last(2) == %w[youtube com] \
        && u.path =~ %r[/channel/] && !$'.include?("/")
      then
        u.path += "/videos" 
      end
      @log[orig: orig, fixed: u].info "fixed URL" if u != orig
      u.to_s
    end
    Utils.retry 3, RETRIABLE_YTDL_PL_ERR, wait: ->{ 1+rand } do
      @log.info("getting playlist") do
        @ydl.run *["-j", *("--flat-playlist" unless full), *urls]
      end
    end
  rescue Exe::ExitError => err
    if err.status == 1 && err.stderr =~ THROTTLE_STDERR_RE
      raise ThrottleError.new("getting playlist", err)
    end
    raise
  end

  class ThrottleError < StandardError
    def initialize(msg, exiterr)
      super()
      @msg, @exiterr = msg, exiterr
    end

    def to_s
      "got throttled (#{@msg}): #{@exiterr}"
    end
  end

  def self.logfmt_output(s)
    s.strip.gsub(/^/, "…")[1..-1]
  end

  DF_BLOCK_SIZE = 'M'
  DF_SHORT_WAIT, DF_SHORT_WAIT_MAX = 10, 5*60
  SKIP_RETRY_DELAY = 7*24*3600

  def dl(item, proxy: nil)
    log = @log[item.id]

    if @dled.include? item.id
      log.debug "already downloaded or downloading, skipping"
      return
    end
    @dled << item.id

    if @stop.get
      log.debug "stopped, skipping"
      return
    end

    matcher = ItemMatcher.new item.id

    ls = matcher.glob @meta
    skip, other = ls.partition { |f| f.extname == ".skip" }
    skip.tap do |a|
      skip = a.shift
      other.concat a
    end

    if @cleanup && !other.empty?
      log.info "deleting leftover files: %p" % [fns(other)] do
        FileUtils.rm other
      end
    end unless @dry_run

    name = CachedStringer.new do
      if item.youtube_invalid_title?
        begin
          json = get_playlist item.url, full: true
        rescue Exe::ExitError => err
          err.status == 1 or raise
          log[title: item.title, err: err].warn "failed to fix title"
        else
          fix = Item.from_json 0, JSON.parse(json)
          log[fix: Utils.path_diff(item.title, fix.title)].warn "fixing title"
          item.title = fix.title
        end
      end
      ("%05d - %s%s - %s" % [
        item.idx,
        item.title[0,100],
        item.duration.yield_self { |d|
          d ? " (%s)" % Utils::Fmt.duration(d) : ""
        },
        item.id,
      ]).tr('/\\:?!"'"\n", '_')
    end

    ls = matcher.glob(@out)
    if !ls.empty?
      log[match: :out].debug "already downloaded: %p" % [fns(ls)]
      ls.each do |f|
        dest = f.dirname.join "#{name}#{matcher.id_suffix f}"
        f != dest or next
        log[rename: Utils.path_diff(f.basename, dest.basename)].
          info "renaming existing output file"
        !dest.exist? or raise "dest already exists"
        FileUtils.mv f, dest unless @dry_run
      end
      return
    end

    ls = matcher.glob_arr(@done)
    if !ls.empty?
      log[match: :done].debug "already downloaded: %p" % [fns(ls)]
      return
    end

    df_short_wait log

    add_out_file = -> f do
      size = f.size
      @summary << size
      log[size: Utils::Fmt.size(size)].info "output file: %s" % [fn(f)]
      dest = @out.join f.basename
      tmp = dest.dirname.join "#{dest.basename}.tmp"
      # Move the .tmp to the final directory without letting rclone try to copy
      # it while the move is in process (*.tmp excluded from its glob):
      FileUtils.mv f, tmp 
      # Only then, rename atomically to the final filename, ready to be copied
      # by rclone:
      FileUtils.mv tmp, dest
    end

    ls = matcher.glob_arr @cache
    if !ls.empty?
      log.info "cache hit"
      ls.each do |f|
        FileMovePrep.new(f, "#{name}#{matcher.id_suffix f}").
          public_send(@cache_mv ? :mv : :cp, &add_out_file)
      end unless @dry_run
      return
    end

    was_skip = false
    if skip \
      && ((age = Time.now - skip.ctime) >= skip_retry_delay || @retry_skipped)
    then
      skip_log = log[last_skip: Utils::Fmt.duration(age)]
      if item.title =~ UNRETRIABLE_TITLE_RE
        skip_log.debug "won't retry skipped unretriable"
        return
      end
      skip_log.info "retrying skipped"
      skip.delete
      was_skip, skip = skip, nil
    end

    if skip
      log.debug "skipping"
      return
    end

    args = [
      "-q", "--all-subs", item.url, "-o", @meta.join(
        "#{name.to_s.gsub '%', '%%'}.idx%(playlist_index)s.%(ext)s"
      ).to_s,
    ]
    args << "--proxy" << proxy if proxy
    if [proxy, *Playlist::PROXY_ENV_KEYS.map { ENV[_1] }].
      any? { _1.to_s =~ /^socks/i } \
    then
      log.info "detected SOCKS proxy"
      args << "--hls-prefer-native"
    end

    log.info "downloading %s" % name
    if @dry_run
      log.info "dry run: youtube-dl %p" % [args]
      return
    end

    begin
      Utils.retry 3, RETRIABLE_YTDL_ERR do
        @ydl.run *args
      end
    rescue Exe::ExitError => err
      err.status == 1 or raise
      stderr = err.stderr.strip
      log = log[stderr: self.class.logfmt_output(stderr)]
      case
      when stderr =~ THROTTLE_STDERR_RE
        log.warn "throttled, stopping"
        @stop.set true
      when stderr =~ UNRETRIABLE_STDERR_RE || item.title =~ UNRETRIABLE_TITLE_RE
        log.public_send was_skip ? :debug : :error,
          "unavailable, marking as skippable"
        File.write @meta.join("#{name}.skip"), stderr
      else
        log.warn "temporary error, will retry"
      end
      return
    end

    log.info "successfully downloaded"
    ->{ matcher.glob(@meta) }.tap do |files|
      fs = files[]
      if !(empty = fs.select { |f| f.size == 0 }).empty?
        log.error "detected empty output files: %p" % [fns(empty)]
        return
      end
      cat = VidCat.new basename: -> s { s.sub /\.idx(\d+|NA)$/, "" }, log: log
      cat.cat fs.sort
      files[].each &add_out_file
    end
  end

  private def skip_retry_delay
    SKIP_RETRY_DELAY * (1 + rand(21) / 100.0 * (rand > 0.5 ? -1 : 1))
  end

  class CachedStringer
    def initialize(&to_s); @to_s = to_s end
    def to_s; @to_s = @to_s.call if Proc === @to_s; @to_s end
  end

  class FileMovePrep
    def initialize(f, ren)
      @f, @ren = f, ren
    end

    def cp
      Dir.mktmpdir do |dir|
        dest = Pathname(dir).join @ren
        FileUtils.cp @f, dest
        yield dest
      end
    end

    def mv
      dest = @f.dirname.join @ren
      if @f != dest
        !dest.exist? or raise "dest already exists"
        FileUtils.mv @f, dest
      end
      yield dest
    end
  end

  THROTTLE_STDERR_RE = /HTTP Error 429: Too Many Request/i

  RETRIABLE_YTDL_ERR = -> err do
    Exe::ExitError === err && err.status == 1 or break false
    case err.stderr
    when \
      /Unable to extract Initial JS player/i,
      /<urlopen error /,
      /No status line received - the server has closed the connection/
      true
    else
      false
    end
  end

  UNRETRIABLE_STDERR_RE = [
    # YouTube
    "No video formats found",
    "This video is not available",
    "This video is no longer available",
    "This video is unavailable",
    "This video contains content",
    "This video has been removed",
    "The uploader has not made this video available",
    "This video is unavailable on this device",
    "This video is only available to Music Premium members",
    "Sorry about that.",
    "giving up after 10 fragment retries",
    "Content Warning",
    "unable to download video data: HTTP Error 403: Forbidden",
    "Unable to extract video data",
    # FranceTV
    "Unable to extract video ID",
    # SoundCloud
    "unable to download video data: HTTP Error 401: Unauthorized",
  ].yield_self { |msgs|
    /ERROR:.*\b(?:#{msgs.map { |m| Regexp.escape m } * "|"})/i
  }

  UNRETRIABLE_TITLE_RE = /^\[Deleted video\]|\[Private video\]$/

  private def fns(ps); ps.map { |p| fn p } end
  private def fn(p); p.basename.to_s end
  private def fmt_df(n) "%s%s" % [Utils::Fmt.d(n, z: false), DF_BLOCK_SIZE] end

  private def df_short_wait(log)
    wait = 0
    last = nil
    while short = df_short
      mnt, free = short
      wait = 0 if last && free > last
      last = free
      mnt_log = log[
        mnt: mnt,
        free: fmt_df(free),
        min: fmt_df(@min_df),
        wait: Utils::Fmt.duration(wait),
      ]
      if wait < DF_SHORT_WAIT_MAX && @rclone_dest
        w = DF_SHORT_WAIT
        mnt_log[nentries: @out.entries.size-2].
          warn "waiting %s for rclone to free up disk space" % [
            Utils::Fmt.duration(w)
          ]
        sleep w; wait += w
        next
      end
      msg = "not enough disk space left"
      mnt_log.error msg
      raise msg
    end
  end

  private def df_short
    min = @min_df or return
    [@out, @meta].each do |d|
      free = Utils.df(d, DF_BLOCK_SIZE)
      return [d, free] if free < min
    end
    nil
  end
end

class Exe
  def initialize(*cmd, log: Utils::Log.new(prefix: name))
    @cmd = cmd
    @log = log
  end

  attr_reader :cmd

  def run(*args)
    cmd = @cmd + args.map(&:to_s)
    out, err, st = Open3.capture3 *cmd
    @log.debug "running %p" % [cmd]
    if !st.success?
      @log.debug "failed: %p" % st
      raise ExitError.new cmd, st.exitstatus, err
    end
    @log.debug "success: %p" % st
    out
  end

  class ExitError < StandardError
    def initialize(cmd, status, stderr)
      super()
      @cmd, @status, @stderr = cmd, status, stderr
    end

    attr_reader :cmd, :status, :stderr

    def to_s
      "`#{@cmd * " "}` exit #{@status}: #{Downloader.logfmt_output @stderr}"
    end
  end
end

class Var_ThreadSafe
  def initialize(val)
    @val = val
    @mu = Mutex.new
  end

  def set(val); @mu.synchronize { @val = val } end
  def get; @mu.synchronize { @val } end
end

class Set_ThreadSafe
  def initialize
    @set = Set.new
    @mu = Mutex.new
  end

  def <<(el)
    @mu.synchronize { @set << el }
    self
  end

  def include?(el)
    @mu.synchronize { @set.include? el }
  end
end

class ItemMatcher
  def initialize(id)
    id = id.to_s
    @pat = "* - #{id}.*"
    @suffix_re = / - #{Regexp.escape id}(\..+)$/
  end

  def id_suffix(f)
    f.basename.to_s =~ @suffix_re or raise "ID not found in filename"
    $1
  end

  def glob(dir)
    dir.glob @pat
  end

  def glob_arr(arr)
    arr.select { |p| p.fnmatch? @pat }
  end
end

module Commands
  ENV_PREFIX = "YTDUMP_"

  def self.env(key, default=nil, &transform)
    transform ||= -> v { v }
    val = ENV.fetch(ENV_PREFIX + key) { return default }
    transform[val]
  end

  def self.cmd_list
    log = Utils::Log.new
    Playlist.load($stdin, log: log).each do |pl|
      puts pl.name
    end
  end

  def self.cmd_dl(*names, out: "out", meta: "meta", cache: nil, debug: false, 
    min_df: env("MIN_DF", &:to_f), proxy: nil, **opts
  )
    log = Utils::Log.new(level: debug ? :debug : :info)
    pls = Playlist.load($stdin, default_proxy: proxy, log: log).
      each_with_object({}) { |pl,h| h[pl.name] = pl }
    names = pls.keys if names.empty?
    rclone = Exe.new "rclone", log: log["rclone"]

    { min_duration: :to_i,
      nthreads: :to_i,
      min_df: :to_f }.each \
    do |k, cast|
      val = opts[k] or next
      opts[k] = cast.to_proc[val]
    end

    names.each do |name|
      pl = pls.fetch name
      dler = Downloader.new **\
        {out: out, meta: meta, cache: cache, log: log, min_df: min_df}.
          merge(done: pl.done(rclone)).
          merge(pl.opts).
          merge(opts)
      pl.setup_env do
        pl.urls.each do |url|
          case url
          when /^\[/
            dler.dl_playlist_json url
          else
            dler.dl_playlist url, proxy: -> parser { pl.proxy_conf.url parser }
          end
        end
        dler.finish
      end
    end
  end

  def self.cmd_check
    log = Utils::Log.new
    fmt_res = -> res { res ? "OK" : "!!" }

    thrs = EpsParse.all.each_with_object({}) { |p,h|
      h[p] = Thread.new do
        Thread.current.abort_on_exception = true
        plog = log[p.name]
        p.check(plog["check"]).tap do |res|
          plog[res: fmt_res[res]].info "checked"
        end
      end
    }.transform_values! &:value

    thrs.sort_by { |p,| p.name }.each do |p, res|
      puts "%-10s: %s" % [p.name, fmt_res[res]]
    end

    exit(thrs.values.all? ? 0 : 1)
  end
end

if $0 == __FILE__
  require 'metacli'
  argv = ARGV.map do |arg|
    case arg
    when "-x" then "--audio"
    when "-v" then "--debug"
    else arg
    end
  end
  argv << "--debug" if ENV["DEBUG"] == "1"
  MetaCLI.new(argv).run Commands
end
