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

    case vids.size
    when 0
    when 1
      f = vids.fetch 0
      dest = rename(f) { |base, ext| @basename[base] + ext }
      fu :mv, f, dest if f != dest
    else
      main = vids.min_by { |f| remove_suffix(f).to_s.length }
      out = add_suffix main, ".mkv"
      ffconcat vids, out
      fu :rm, vids
      final = rename(remove_suffix(out)) { |base, ext| @basename[base] + ext }
      fu :mv, out, final if out != final
      vids = [final]
    end

    vids + other
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
    run_cmd "ffmpeg", "-loglevel", "error", "-y",
      *fs.flat_map { |f| ["-i", f.to_s] },
      "-c:v", "copy", "-c:a", "copy", out.to_s,
      name: "ffmerge"
  end

  def ffconcat(fs, out)
    Tempfile.create do |list|
      fs.each { |f| list.puts "file #{ffquote f.expand_path.to_s}" }
      list.close
      run_cmd "ffmpeg", "-loglevel", "error", "-y",
        "-f", "concat", "-safe", "0", "-i", list.path, "-c", "copy", out.to_s,
        name: "ffconcat"
    end
  end

  def ffquote(str)
    str.split(%(')).map { |s| %('#{s}') }.join %(\\')
  end

  def run_cmd(*cmd, name:)
    @log.debug "running #{name}: #{shelljoin cmd}" do
      system *cmd or raise "#{name} failed"
    end
  end
end

if $0 == __FILE__
  VidCat.new.cat Pathname(".").glob("*")
end
