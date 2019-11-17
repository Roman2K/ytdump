require 'yaml'
require 'fileutils'

FU = FileUtils::Verbose

dirs = ARGV.flat_map do |f|
  File.open(f, 'r') { |io| YAML.load io }.fetch("playlists").
    select { |k,v| next if k =~ /^_/; v["audio"] }.
    map { |k,v|
      dest = v.fetch("rclone_dest").sub!(/^drive:/, "") or raise "expected drive dest"
      dest += k if dest.end_with? "/"
      dest
    }
end

q = Queue.new
thrs = 14.times.map do
  Thread.new do
    Thread.current.abort_on_exception = true
    while block = q.shift
      block.call
    end
  end
end

dirs.each do |dir|
  drive_dir = Pathname(ENV.fetch("HOME") + "/windrive/" + dir)
  videos = drive_dir.glob("*").select(&:file?).
    reject { |f| %w(.mp3 .ogg .m4a .rb).include? f.extname }
  next if videos.empty?

  archive = drive_dir.join("archive")
  FU.mkdir_p archive

  videos.each do |_f|
    f = _f
    out = f.to_s.chomp(f.extname) + ".mp3"
    out != f or raise "already mp3"
    q << -> do
      puts "converting %s" % [f.basename]
      system "ffmpeg", "-y", "-i", f.to_s,
        "-codec:a", "libmp3lame", "-q:a", "2", out, err: '/dev/null' \
        or raise "ffmpeg failed for #{f}"
      if (dest = archive.join(f.basename)).exist?
        FU.rm dest
      end
      FU.mv f, archive
      puts "OK: %s" % [f.basename]
    end
  end
end

q.close
thrs.each &:join
