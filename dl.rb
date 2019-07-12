require 'json'
require 'open3'
require 'fileutils'
require 'pathname'
require 'utils'
require_relative 'item'
require_relative 'sixplay'
require_relative 'replaytivi'

class Downloader
  NTHREADS = 4

  def initialize(out:, meta:, done: [],
    ydl_opts: [], min_duration: nil, rclone_dest: nil, nthreads: NTHREADS,
    check_empty: true, notfound_ok: false, min_df: nil,
    cache: nil, dry_run: false, log: Utils::Log.new
  )
    @ydl = Exe.new "youtube-dl", log["youtube-dl"]
    @dry_run, @log = dry_run, log

    @ydl_opts, @min_duration, @rclone_dest, @nthreads =
      ydl_opts, min_duration, rclone_dest, nthreads
    @check_empty, @notfound_ok, @min_df =
      check_empty, notfound_ok, min_df
    @nthreads = 1 if @dry_run

    @cache = if cache
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
    @out_size = 0

    @log.info "out dir: %p" % fns([@out])
    @log.info "meta dir: %p" % fns([@meta])
    @log.info "done: %d" % @done.size
    @log.info "ydl opts: %p" % [@ydl_opts]
    @log.info "threads: %d" % @nthreads
    @log.info "min df: %s" \
      % @min_df.yield_self { |n| n ? "%f%s" % [n, DF_BLOCK_SIZE] : "-" }

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
          rclone.run("move", "-v", @out, @rclone_dest).tap do |out|
            puts out if out =~ /\S/
          end
          break if stop
        end
      end
    end
  end

  def dl_playlist(url)
    parsers = [
      SixPlay.new,
      ReplayTivi.new,
    ]
    if found = parsers.lazy.map { |p| [p, p.episodes(url)] }.find { |p,a| a }
      parser, items = found
      @min_duration ||= parser.min_duration
      return dl_playlist_items items.map &:playlist_item
    end

    pl = begin
      get_playlist url
    rescue Exe::ExitError => err
      if err.status == 1 && err.stderr =~ /404: Not Found/i && @notfound_ok
        @log.info "playlist not found but tolerated by setting, aborting"
        return
      end
      raise
    end
    dl_playlist_json "[#{pl.split("\n") * ","}]"
  end

  def dl_playlist_json(s)
    items = JSON.parse(s).
      reverse.
      map.
      with_index { |attrs, idx| Item.from_json idx+1, attrs }

    dl_playlist_items items
  end

  def dl_playlist_items(items)
    if min = @min_duration
      @log.info "selecting items >= %s" % [Utils::Fmt.duration(min)]
      items.select! do |item|
        d = item.duration or raise "missing duration in item %p" % item
        d >= min
      end
    end
    raise "empty playlist" if @check_empty && items.empty?
    @log.info "enqueueing %d playlist items" % items.size
    items.sort_by(&:idx).each { |i| @q << i }
  end

  def finish
    @q.close
    @threads.each &:join
    @log.info "downloaded %s" % [Utils::Fmt.size(@out_size)]
  end

  RETRIABLE_YTDL_PL_ERR = -> err do
    Exe::ExitError === err \
      && err.status == 1 \
      && err.stderr =~ /\bHTTP Error 5\d\d\b/i
  end

  private def get_playlist(url)
    File.read "debug"
  rescue Errno::ENOENT
    Utils.retry 3, RETRIABLE_YTDL_PL_ERR, wait: ->{ 1+rand } do
      @log.info("getting playlist") do
        @ydl.run *["-j", *("--flat-playlist" unless @min_duration), url]
      end
    end
  end

  DF_BLOCK_SIZE = 'M'
  SKIP_RETRY_DELAY = 7 * 24 * 3600

  def dl(item)
    log = @log[item.id]

    if @dled.include? item.id
      log.debug "already downloaded or downloading, skipping"
      return
    end
    @dled << item.id

    if @min_df \
      && short = [@out, @meta].find { |d| Utils.df(d, DF_BLOCK_SIZE) < @min_df }
    then
      log[short: short, min: "%f%s" % [@min_df, DF_BLOCK_SIZE]].
        error "not enough disk space left"
      return
    end

    matcher = ItemMatcher.new item.id

    ls = matcher.glob @meta
    skip, other = ls.partition { |f| f.extname == ".skip" }
    skip.tap do |a|
      skip = a.shift
      other.concat a
    end

    if !other.empty?
      log.info "deleting leftover files: %p" % fns(other) do
        FileUtils.rm other
      end
    end

    ls = matcher.glob(@out) | matcher.glob_arr(@done)
    if !ls.empty?
      log.debug "already downloaded: %p" % fns(ls)
      return
    end

    add_out_file = -> cp, f {
      %i( cp mv ).include? cp \
        or raise ArgumentError, "unknown cp method: %p" % cp
      size = f.size
      @out_size += size
      log.info "output file: %p (%s)" % [fn(f), Utils::Fmt.size(size)]
      FileUtils.public_send cp, f, @out
    }.curry 2

    ls = matcher.glob_arr @cache
    if !ls.empty?
      log.info "cache hit"
      ls.each &add_out_file[:cp]
      return
    end

    if skip && (age = Time.now - skip.ctime) >= SKIP_RETRY_DELAY
      log[last_skip: Utils::Fmt.duration(age)].info "retrying skipped"
      skip.delete
      skip = nil
    end

    if skip
      log.debug "skipping"
      return
    end

    name = ("%05d - %s%s - %s" % [
      item.idx,
      item.title,
      item.duration.yield_self { |d|
        d ? " (%s)" % Utils::Fmt.duration(d) : ""
      },
      item.id,
    ]).tr('/\\:!'"\n", '_')

    args = [
      "-o", @meta.join("#{name}.%(ext)s").to_s,
      "-q", *@ydl_opts,
      item.url
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
      case stderr
      when UNRETRIABLE_STDERR_RE
        log.error "unavailable, marking as skippable"
        File.write @meta.join(name+".skip"), stderr
      else
        log.warn "temporary error, will retry"
      end
      return
    end

    log.info "successfully downloaded"
    matcher.glob(@meta).each &add_out_file[:mv]
  end

  RETRIABLE_YTDL_ERR = -> err do
    Exe::ExitError === err \
      && err.status == 1 \
      && err.stderr =~ /Unable to extract Initial JS player/i
  end

  UNRETRIABLE_STDERR_RE = [
    "No video formats found",
    "This video is not available",
    "This video is no longer available",
    "This video is unavailable",
    "This video contains content",
    "This video has been removed",
    "The uploader has not made this video available",
    "This video is only available to Music Premium members",
  ].yield_self { |msgs|
    /ERROR: (?:#{msgs.map { |m| Regexp.escape m } * "|"})/i
  }

  private def fns(ps); ps.map { |p| fn p } end
  private def fn(p); p.basename.to_s end
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
    @pat = "* - #{id}.*"
  end

  def glob(dir)
    dir.glob @pat
  end

  def glob_arr(arr)
    arr.select { |p| p.fnmatch? @pat }
  end
end

module Commands
  def self.cmd_dl(*urls,
    audio: false, min_duration: nil, rclone_dest: nil, nthreads: nil,
    check_empty: true, notfound_ok: false, min_df: nil,
    cache: nil, dry_run: false, debug: false
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
      out: "out", meta: "meta", done: done,
      ydl_opts: audio ? %w( -x --audio-format mp3 ) : [],
      rclone_dest: rclone_dest,
      check_empty: check_empty, notfound_ok: notfound_ok,
      cache: cache, dry_run: dry_run, log: log,
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
