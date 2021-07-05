require 'fileutils'
require 'pathname'
require 'tempfile'
require 'utils'
require 'shellwords'

class VidCat
  def initialize(basename: -> s { s }, tmp_suffix: ".vidcat_tmp",
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
      # Remux to MP4 instead of MKV to fix `Can't write packet with unknown
      # timestamp` -- https://trac.ffmpeg.org/ticket/3339
      out = add_suffix f, ".mp4"
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
      fix_filenames vids do |fixed_vids|
        ffconcat fixed_vids, out
      end
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
        "-c:v", "copy", "-c:a", "libmp3lame", "-q:a", "0", out.to_s \
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

  # /meta/jersey/00415 - 2021-06-04 - Season 4, Ep 15 - UMMMM... HELLO, 2021. (42m52s) - 51b1a6e8-c4b2-11eb-8774-70df2f866ace.idx01.vidcat_tmp.vidcat_tmp.mkv
  # [concat @ 0x7f03aab920c0] Impossible to open '/meta/jersey HELLO, 2021. (42m52s) - 51b1a6e8-c4b2-11eb-8774-70df2f866ace.idx01.vidcat_tmp.mp4'
  def fix_filenames(fs)
    tmp = []
    begin
      fixed = fs.map do |f|
        dest = rename f do |base, ext|
          base.gsub(/\.{2,}/) { '_' * $&.length } + ext
        end
        next f if dest == f
        raise "name fix path already exists" if dest.exist?
        fu :ln_s, f.basename, dest
        tmp << dest
        dest
      end
      yield fixed
    ensure
      tmp.each do |f|
        begin
          fu :rm, f
        rescue Errno::ENOENT
        end
      end
    end
  end
end

if $0 == __FILE__
  VidCat.new.cat Pathname(".").glob("*")
end
