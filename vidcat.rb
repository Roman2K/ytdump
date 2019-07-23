require 'fileutils'
require 'pathname'
require 'tempfile'
require 'utils'
require 'shellwords'

class VidCat
  DEFAULT_TMP_SUFFIX = ".vidcat_tmp"

  def initialize(basename: -> s { s }, tmp_suffix: DEFAULT_TMP_SUFFIX,
    log: Utils::Log.new
  )
    @basename = basename
    @tmp_suffix = tmp_suffix
    @log = log
  end

  def cat(files)
    ##
    # 1. For each video file, merge all related files (subtitles, etc.)
    #
    vids, other = [], []
    files.each do |f|
      if !%w(.mp4 .mkv .webm).include?(f.extname)
        other << f
        next
      end
      fs = [f, *(f.dirname.glob(f.basename(".*").to_s + ".*"))].uniq
      if fs.size <= 1
        vids << f
        next
      end
      out = add_suffix f, ".mkv"
      fs.delete out
      ffmerge fs, out
      fu :rm, fs
      vids << out
    end
    [vids, other].each { |a| a.select! &:exist? }

    ##
    # 2. Concatenate all video files
    #
    if vids.size >= 2
      out = vids.min_by { |f| remove_suffix(f).to_s.length }
      out = add_suffix out, ".mkv"
      vids.delete out
      ffconcat vids, out
      fu :rm, vids
      vids = [out]
    end

    ##
    # 3. Return single video file alongside extra files
    #
    (vids + other).map do |f|
      dest = rename(remove_suffix(f)) { |base, ext| @basename[base] + ext }
      fu :mv, f, dest if f != dest
      dest
    end
  end

private

  def fu(m, *args, &block)
    @log.debug shelljoin([m, args].flatten) do
      FileUtils.public_send m, *args, &block
    end
  end

  def shelljoin(cmd)
    Shellwords.join cmd.map &:to_s
  end

  def add_suffix(f, custom_ext=nil)
    rename f do |base, ext|
      "#{base}#{@tmp_suffix}#{custom_ext || ext}"
    end
  end

  def remove_suffix(f)
    rename f do |base, ext|
      while base.chomp! @tmp_suffix; end
      base + ext
    end
  end

  def rename(f)
    base, ext = f.basename(".*").to_s, f.extname
    f.dirname.join yield(base, ext)
  end

  def ffmerge(fs, out)
    @log["ffmerge", in: fs.size, out: out.to_s].debug "running" do
      system "ffmpeg", "-loglevel", "error", "-y",
        *fs.flat_map { |f| ["-i", f.to_s] },
        "-c:v", "copy", "-c:a", "copy", out.to_s \
          or raise "ffmerge failed"
    end
  end

  def ffconcat(fs, out)
    Tempfile.create do |list|
      fs.each { |f| list.puts "file #{ffquote f.expand_path.to_s}" }
      list.close
      @log["ffconcat", in: fs.size, out: out.to_s].info "running" do
        system "ffmpeg", "-loglevel", "error", "-y",
          "-f", "concat", "-safe", "0",
          "-i", list.path, "-c", "copy", out.to_s \
            or raise "ffconcat failed"
      end
    end
  end

  def ffquote(str)
    str.split(%(')).map { |s| %('#{s}') }.join %(\\')
  end
end

if $0 == __FILE__
  VidCat.new.cat Pathname(".").glob("*")
end
