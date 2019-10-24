require 'json'
require 'open3'
require 'fileutils'
require 'pathname'
require 'utils'
require_relative 'item'
require_relative 'eps_parse'
require_relative 'vidcat'

class Downloader
  NTHREADS = 4

  def initialize(out:, meta:, done: [],
    ydl_opts: [], min_duration: nil, rclone_dest: nil, nthreads: NTHREADS,
    sorted: false, check_empty: true, notfound_ok: false, min_df: nil,
    cache: nil, cleanup: true, dry_run: false, log: Utils::Log.new
  )
    @ydl = Exe.new "youtube-dl", log["youtube-dl"]
    @cleanup, @dry_run, @log = cleanup, dry_run, log

    @ydl_opts, @min_duration, @rclone_dest, @nthreads =
      ydl_opts, min_duration, rclone_dest, nthreads
    @sorted, @check_empty, @notfound_ok, @min_df =
      sorted, check_empty, notfound_ok, min_df
    @nthreads = 1 if @dry_run

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
    @dled = Set_ThreadSafe.new
    @summary = Summary.new

    @log.info "out dir: %p" % [fn(@out)]
    @log.info "meta dir: %p" % [fn(@meta)]
    @log.info "done: %d" % @done.size
    @log.info "ydl opts: %p" % [@ydl_opts]
    @log.info "threads: %d" % @nthreads
    @log.info "min df: %s" % @min_df.yield_self { |n| n ? fmt_df(n) : "-" }
    @log.info "cleanup: %p" % @cleanup

    @q = Queue.new
    @threads = @nthreads.times.map do
      Thread.new do
        Thread.current.abort_on_exception = true
        while item = @q.shift
          dl item
        end
      end
    end

    if @rclone_dest
      rclone = Exe.new "rclone", @log["rclone"]
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

  private def parse_items(url)
    EpsParse.all.lazy.
      map { |p| [p, p.playlist_items(url)] }.
      find { |p,a| a }
  end

  def dl_playlist(url)
    if File.file? url
      pl = File.read url
    elsif found = parse_items(url)
      parser, items = found
      @log[parser: parser.name, items: items.size].info "parser found items"
      @min_duration ||= parser.min_duration
      return dl_playlist_items items
    else
      pl = begin
        get_playlist url
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

  def dl_playlist_items(items)
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
    items.sort_by(&:idx).each { |i| @q << i }
  end

  def finish
    @q.close
    @threads.each &:join
    @log.info "downloaded %s" % [@summary]
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
    File.read "debug"
  rescue Errno::ENOENT
    Utils.retry 3, RETRIABLE_YTDL_PL_ERR, wait: ->{ 1+rand } do
      @log.info("getting playlist") do
        @ydl.run *["-j", *("--flat-playlist" unless full), *urls]
      end
    end
  end

  DF_BLOCK_SIZE = 'M'
  DF_SHORT_WAIT, DF_SHORT_WAIT_MAX = 10, 5*60
  SKIP_RETRY_DELAY = 7*24*3600

  def dl(item)
    log = @log[item.id]

    if @dled.include? item.id
      log.debug "already downloaded or downloading, skipping"
      return
    end
    @dled << item.id

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
        item.title,
        item.duration.yield_self { |d|
          d ? " (%s)" % Utils::Fmt.duration(d) : ""
        },
        item.id,
      ]).tr('/\\:?!"'"\n", '_')
    end

    ls = matcher.glob(@out)
    if !ls.empty?
      log[in: :out].debug "already downloaded: %p" % [fns(ls)]
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
      log[in: :done].debug "already downloaded: %p" % [fns(ls)]
      return
    end

    df_short_wait log

    add_out_file = -> f do
      size = f.size
      @summary << size
      log[size: Utils::Fmt.size(size)].info "output file: %s" % [fn(f)]
      dest = @out.join f.basename
      tmp = dest.dirname.join "#{dest.basename}.tmp"
      FileUtils.mv f, tmp
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
    if skip && (age = Time.now - skip.ctime) >= SKIP_RETRY_DELAY
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
      "-q", "--all-subs", *@ydl_opts, item.url,
      "-o", @meta.join(
        "#{name.to_s.gsub '%', '%%'}.idx%(playlist_index)s.%(ext)s"
      ).to_s,
    ]

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
      log = log[status: err.status, stderr: stderr]
      if stderr =~ UNRETRIABLE_STDERR_RE || item.title =~ UNRETRIABLE_TITLE_RE
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
    "This video is only available to Music Premium members",
    "Sorry about that.",
    "giving up after 10 fragment retries",
    # FranceTV
    "Unable to extract video ID",
    # MTV
    "Unable to download XML: HTTP Error 500",
  ].yield_self { |msgs|
    /ERROR: (?:#{msgs.map { |m| Regexp.escape m } * "|"})/i
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
      if wait < DF_SHORT_WAIT_MAX \
        && (nentries = @out.entries.size-2) > 0 && @rclone_dest
      then
        w = DF_SHORT_WAIT
        mnt_log[nentries: nentries].
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
  def initialize(name, log=Utils::Log.new(prefix: name))
    @name = name
    @log = log
  end

  def run(*args)
    args.map! &:to_s
    out, err, st = Open3.capture3 @name, *args
    @log.debug "running %p %p" % [@name, args]
    if !st.success?
      @log.debug "failed: %p" % st
      raise ExitError.new [@name, *args], st.exitstatus, err
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
      "`#{@cmd * " "}` exit #{@status}: #{@stderr}"
    end
  end
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

  def self.cmd_dl(*urls,
    out: "out", meta: "meta",
    audio: false, min_duration: nil, rclone_dest: nil, nthreads: nil,
    sorted: false, check_empty: true, notfound_ok: false,
    min_df: env("MIN_DF", &:to_f),
    cache: nil, cleanup: true, dry_run: false, debug: false
  )
    log = Utils::Log.new(level: debug ? :debug : :info)

    done = if rclone_dest
      rcl = Exe.new "rclone", log["rclone"]
      rcl.run "-v", "lsf", rclone_dest
    elsif !$stdin.tty?
      $stdin.read
    else
      ""
    end.split("\n")

    dler = Downloader.new **{
      out: out, meta: meta, done: done,
      ydl_opts: audio ? %w( -x --audio-format mp3 ) : [],
      rclone_dest: rclone_dest,
      sorted: sorted, check_empty: check_empty, notfound_ok: notfound_ok,
      cache: cache, cleanup: cleanup, dry_run: dry_run, log: log,
    }.tap { |h|
      h.update({
        min_duration: min_duration&.to_i,
        nthreads: nthreads&.to_i,
        min_df: min_df&.to_f,
      }.delete_if { |k,v| v.nil? })
    }

    urls.each do |url|
      case url
      when /^\[/
        dler.dl_playlist_json url
      else
        dler.dl_playlist url
      end
    end
    dler.finish
  end

  def self.cmd_check
    log = Utils::Log.new

    thrs = EpsParse.all.each_with_object({}) { |p,h|
      h[p] = Thread.new do
        Thread.current.abort_on_exception = true
        plog = log[p.name]
        p.check(plog).tap do |res|
          plog[res: res].info "checked"
        end
      end
    }.transform_values! &:value

    thrs.sort_by { |p,| p.name }.each do |p, res|
      puts "%-10s: %s" % [p.name, res ? "OK" : "!!"]
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
