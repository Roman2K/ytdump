require 'json'
require 'open3'
require 'fileutils'
require 'pathname'

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

class Item
  def initialize(idx, attrs)
    @idx = idx
    @id, @title = %w( id title ).map { |k| attrs.fetch k }
  end

  attr_reader :idx, :id, :title

  def url
    "https://youtu.be/#{@id}"
  end
end

class Downloader
  NTHREADS = 4

  def initialize(out:, meta:, done: [], ydl_opts: [])
    @log = Log.new
    @ydl = Exe.new "youtube-dl"
    @ydl_opts = ydl_opts

    @out, @meta = [out, meta].map { |p|
      Pathname(p).tap do |dir|
        FileUtils.mkdir_p dir
      end
    }
    @done = done.map { |p| Pathname p }

    @q = Queue.new
    @threads = NTHREADS.times.map do |i|
      Thread.new do
        Thread.current.abort_on_exception = true
        while item = @q.shift
          dl item
        end
      end
    end

    @log.puts "out dir: %p" % fns([@out])
    @log.puts "meta dir: %p" % fns([@meta])
    @log.puts "done: %d" % @done.size
    @log.puts "threads: %d" % @threads.size
    @log.puts "ydl opts: %p" % [@ydl_opts]
  end

  def dl_playlist(url)
    @log.puts "updating youtube-dl" do
      Exe.new("pip").run "install", "--user", "--upgrade", "youtube-dl"
    end

    items = get_playlist(url).
      split("\n").
      reverse.
      map.with_index { |line, idx|
        begin
          Item.new idx, JSON.parse(line)
        rescue KeyError
        end
      }.
      compact

    @log.puts "got %d playlist items" % items.size
    items.each { |i| @q << i }
  end

  def finish
    @q.close
    @threads.each &:join
  end

  private def get_playlist(url)
    File.read("debug_ydl_out").tap do
      @log.puts "read cached debug playlist"
    end
  rescue Errno::ENOENT
    @log.puts("getting playlist") { @ydl.run "-j", "--flat-playlist", url }
  end

  def dl(item)
    log = @log.sub item.id
    matcher = ItemMatcher.new item.id
    name = ("%05d - %s - %s" % [item.idx+1, item.title, item.id]).tr('/\\', '_')

    ls = matcher.glob @meta
    skip, other = ls.partition { |f| f.extname == ".skip" }
    skip.tap do |a|
      skip = a.shift
      other.concat a
    end

    if !other.empty?
      log.puts "deleting leftover files: %p" % fns(other) do
        FileUtils.rm other
      end
    end
    if skip
      log.puts "skipping"
      return
    end

    ls = matcher.glob(@out) | matcher.glob_arr(@done)
    if !ls.empty?
      log.puts "already downloaded: %p" % fns(ls)
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
        when /^ERROR: /
          log.puts "unavailable, marking as skippable: #{err.stderr.strip}"
          FileUtils.touch @meta.join(name+".skip")
          return
        end
      end
      raise
    end

    log.puts "successfully downloaded"
    matcher.glob(@meta).each do |f|
      log.puts "output file: %p" % fns([f])
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
  def initialize
    @io, @mu = $stderr, Mutex.new
  end

  def puts(*args, &block)
    @mu.synchronize do
      do_puts *args, &block
    end
  end

  private def do_puts(*args)
    @io.print args.join("\n")
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

  def sub(title)
    Sub.new self, title
  end

  class Sub
    def initialize(log, title)
      @log, @title = log, title
    end

    def puts(msg, *args, &block)
      @log.puts "#{@title}: #{msg}", *args, &block
    end
  end
end

if $0 == __FILE__
  audio = !!ARGV.delete("-x")
  !ARGV.empty? or raise "usage: #{File.basename $0} [-x] PLAYLIST_URL ..."
  urls = ARGV.dup

  dler = Downloader.new \
    out: "out", meta: "meta",
    done: $stdin.tty? ? [] : $stdin.read.split("\n"),
    ydl_opts: audio ? %w( -x ) : []
  urls.each do |url|
    dler.dl_playlist url
  end
  dler.finish
end
