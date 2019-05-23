require 'json'
require 'open3'
require 'fileutils'
require 'pathname'
require_relative 'item'
require_relative 'sixplay'

class Exe
  def initialize(name)
    @name = name
  end

  def run(*args)
    out, err, st = Open3.capture3 @name, *args
    if !st.success?
      raise ExitError.new [@name, *args], st.exitstatus, err
    end
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

class Downloader
  NTHREADS = 4

  def initialize(out:, meta:, done: [], ydl_opts: [], check_empty: true,
    min_duration: DEFAULT_MIN_DURATION, log: Log.new
  )
    @ydl = Exe.new "youtube-dl"
    @ydl_opts, @check_empty, @min_duration, @log =
      ydl_opts, check_empty, min_duration, log

    @out, @meta = [out, meta].map { |p|
      Pathname(p).tap do |dir|
        FileUtils.mkdir_p dir
      end
    }
    @done = done.map { |p| Pathname p }

    @q = Queue.new
    @threads = NTHREADS.times.map do
      Thread.new do
        Thread.current.abort_on_exception = true
        while item = @q.shift
          dl item
        end
      end
    end

    @log.debug "out dir: %p" % fns([@out])
    @log.debug "meta dir: %p" % fns([@meta])
    @log.debug "done: %d" % @done.size
    @log.debug "threads: %d" % @threads.size
    @log.debug "ydl opts: %p" % [@ydl_opts]
  end

  DEFAULT_MIN_DURATION = 20 * 60

  def dl_playlist(url)
    @log.debug "updating youtube-dl" do
      Exe.new("pip").run "install", "--user", "--upgrade", "youtube-dl"
    end
    min_duration = @min_duration || DEFAULT_MIN_DURATION
    parsers = [
      SixPlay.new { |ep| ep.duration >= min_duration },
    ]
    if items = parsers.lazy.map { |p| p.playlist_items(url) }.find { |a| a }
      dl_playlist_items items
    else
      dl_playlist_json "[#{get_playlist(url).split("\n") * ","}]"
    end
  end

  def dl_playlist_json(s)
    items = JSON.parse(s).
      reverse.
      tap { |all| @log.info "found %d raw playlist items" % all.size }.
      map.with_index { |attrs, idx|
        begin
          Item.from_json idx+1, attrs
        rescue KeyError
        end
      }.
      compact

    dl_playlist_items items
  end

  def dl_playlist_items(items)
    raise "empty playlist" if @check_empty && items.empty?
    @log.info "enqueueing %d playlist items" % items.size
    items.sort_by(&:idx).each { |i| @q << i }
  end

  def finish
    @q.close
    @threads.each &:join
  end

  private def get_playlist(url)
    File.read("debug_ydl_out").tap do
      @log.info "read cached debug playlist"
    end
  rescue Errno::ENOENT
    @log.info("getting playlist") { @ydl.run "-j", "--flat-playlist", url }
  end

  KEEP_EXTS = %w(.mkv .mp4 .ytdl .part)

  def dl(item)
    log = @log.sub item.id
    matcher = ItemMatcher.new item.id
    name = ("%05d - %s - %s" % [item.idx, item.title, item.id]).tr('/\\:!', '_')

    ls = matcher.glob @meta
    skip, other = ls.partition { |f| f.extname == ".skip" }
    skip.tap do |a|
      skip = a.shift
      other.concat a
    end

    keep, other = other.partition { |f| KEEP_EXTS.include? f.extname }
    if !keep.empty?
      log.info "keeping leftover files: %p" % fns(keep)
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

    if skip
      log.debug "skipping"
      return
    end

    begin
      @ydl.run \
        "-o", @meta.join("#{name}.%(ext)s").to_s,
        "-q", *@ydl_opts,
        item.url
    rescue Exe::ExitError => err
      if err.status == 1
        case err.stderr
        when /unknown reason/, /urlopen/
          raise
        when /^ERROR: /
          log.info "unavailable, marking as skippable: #{err.stderr.strip}"
          FileUtils.touch @meta.join(name+".skip")
          return
        end
      end
      raise
    end

    log.info "successfully downloaded"
    matcher.glob(@meta).each do |f|
      log.info "output file: %p" % fns([f])
      FileUtils.mv f, @out
    end
  end

  private def fns(pathnames)
    pathnames.map { |p| p.basename.to_s }
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

class Log
  LEVELS = %i( debug info warn error ).freeze
  LEVELS_W = LEVELS.map(&:length).max

  def initialize(prefix=nil, level: LEVELS.first, io: $stderr, mutex: Mutex.new)
    @prefix, @io, @mu = prefix, io, mutex
    self.level = level
  end

  def level=(name)
    @level_idx = find_level name
  end

  def level
    LEVELS.fetch @level_idx
  end

  private def find_level(name)
    LEVELS.index(name) \
      or raise ArgumentError, "unknown level: %p" % name
  end

  LEVELS.each do |level|
    define_method level do |*args, &block|
      log level, *args, &block
    end
  end

  private def log(level, *args, &block)
    puts *args, level: level, &block if find_level(level) >= @level_idx
  end

  private def puts(*args, &block)
    @mu.synchronize do
      do_puts *args, &block
    end
  end

  private def do_puts(*msgs, level: nil)
    msgs.map! { |msg| "%*s %s" % [LEVELS_W, level.upcase, add_prefix(msg)] }
    @io.print msgs.join("\n")
    res = if block_given?
      @io.print "... "
      t0 = Time.now
      yield.tap do
        @io.print "%.2fs" % [Time.now - t0]
      end
    end
    @io.puts
    res
  end

  private def add_prefix(s)
    [@prefix, s].compact.join ": "
  end

  def sub(prefix)
    self.class.new add_prefix(prefix), level: level, io: @io, mutex: @mu
  end
end

module Commands
  def self.cmd_dl(*urls, audio: false, debug: false, check_empty: true,
    min_duration: Downloader::DEFAULT_MIN_DURATION
  )
    dler = Downloader.new \
      out: "out", meta: "meta",
      done: $stdin.tty? ? [] : $stdin.read.split("\n"),
      ydl_opts: audio ? %w( -x --audio-format mp3 ) : [],
      check_empty: check_empty,
      min_duration: min_duration.to_i,
      log: Log.new(level: debug ? :debug : :info)

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
  MetaCLI.new(argv).run Commands
end
