require 'json'
require 'open3'
require 'fileutils'
require 'pathname'
require 'utils'
require_relative 'item'
require_relative 'sixplay'
require_relative 'replaytivi'

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

class Downloader
  NTHREADS = 4

  def initialize(out:, meta:, done: [],
    ydl_opts: [], min_duration: nil, rclone_dest: nil, nthreads: NTHREADS,
    check_empty: true, notfound_ok: false, min_df: nil,
    dry_run: false, log: Utils::Log.new
  )
    @ydl = Exe.new "youtube-dl", log["youtube-dl"]
    @dry_run, @log = dry_run, log

    @ydl_opts, @min_duration, @rclone_dest, @nthreads =
      ydl_opts, min_duration, rclone_dest, nthreads
    @check_empty, @notfound_ok, @min_df =
      check_empty, notfound_ok, min_df

    @nthreads = 1 if @dry_run

    @out, @meta = [out, meta].map { |p|
      Pathname(p).tap do |dir|
        FileUtils.mkdir_p dir
      end
    }
    @done = done.map { |p| Pathname p }

    @log.info "out dir: %p" % fns([@out])
    @log.info "meta dir: %p" % fns([@meta])
    @log.info "done: %d" % @done.size
    @log.info "threads: %d" % @nthreads
    @log.info "ydl opts: %p" % [@ydl_opts]

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
          puts rclone.run("move", "-v", @out, @rclone_dest)
          break if stop
        end
      end
    end
  end

  def dl_playlist(url)
    @log.debug "updating youtube-dl" do
      Exe.new("pip").run "install", "--user", "--upgrade", "youtube-dl"
    end unless @dry_run

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
    if min = @min_duration
      @log.info "selecting items >= %s" % [Duration.fmt(min)]
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
  end

  private def get_playlist(url)
    File.read "debug"
  rescue Errno::ENOENT
    @log.info("getting playlist") do
      @ydl.run *["-j", *("--flat-playlist" unless @min_duration), url]
    end
  end

  KEEP_EXTS = %w(.mkv .mp4 .ytdl .part .webm)
  DF_BLOCK_SIZE = 'M'

  def dl(item)
    log = @log[item.id]
    if @min_df \
      && short = [@out, @meta].find { |d| Utils.df(d, DF_BLOCK_SIZE) < @min_df }
    then
      log[short: short, min: "%f%s" % [@min_df, DF_BLOCK_SIZE]].
        error "not enough disk space left"
      return
    end

    matcher = ItemMatcher.new item.id
    name = ("%05d - %s%s - %s" % [
      item.idx,
      item.title,
      item.duration.yield_self { |d| d ? " (%s)" % Duration.fmt(d) : "" },
      item.id,
    ]).tr('/\\:!'"\n", '_')

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

    if skip
      log.debug "skipping"
      return
    end

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
      @ydl.run *args
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
    matcher.glob(@meta).each do |f|
      log.info "output file: %p" % fns([f])
      FileUtils.mv f, @out
    end
  end

  UNRETRIABLE_STDERR_RE = [
    "No video formats found",
    "This video is not available",
    "This video is no longer available",
    "This video is unavailable",
    "This video contains content",
    "This video has been removed",
    "The uploader has not made this video available",
  ].yield_self { |msgs|
    /ERROR: (?:#{msgs.map { |m| Regexp.escape m } * "|"})/i
  }

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

module Commands
  def self.cmd_dl(*urls,
    audio: false, min_duration: nil, rclone_dest: nil, nthreads: nil,
    check_empty: true, notfound_ok: false, min_df: nil,
    dry_run: false, debug: false
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
      dry_run: dry_run, log: log,
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
  argv << "--debug" if ENV["YTDUMP_DEBUG"] == "1"
  MetaCLI.new(argv).run Commands
end
