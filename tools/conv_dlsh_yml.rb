##
# usage: conv.rb playlists/*/dl.sh < pl2/playlists.yml
#

require 'yaml'
require 'json'
require 'metacli'

module Commands

def self.cmd_conv(*files, check: false)
  out = YAML.load $stdin
  playlists = out["playlists"] ||= {}
  check &&= playlists.dup

  files.each do |f|
    name = f[%r{/(.+)/dl\.sh$}, 1] or raise "name not found in path"

    sh = File.read(f)
    case sh
    when /\.sh\b/
      next
    end
    urls, opts = parse_args sh

    { min_duration: :to_i,
      nthreads: :to_i,
      min_df: :to_f }.each \
    do |key, xform|
      opts.key? key or next
      opts[key] = xform.to_proc[opts.fetch(key)]
    end

    case urls.size
    when 0 then raise "missing URL"
    when 1 then opts[:url] = urls.first
    else opts[:urls] = urls
    end
      
    if opts[:rclone_dest] =~ /(.+)\//
      rclone_dir, rclone_name = $1, $'
      if rclone_name == name
        opts[:rclone_dest] = "#{rclone_dir}/"
      end
    end

    opts = {}.tap do |h|
      (%i[urls url proxy] & opts.keys | opts.keys).each do |k|
        h[k] = opts.fetch k
      end
    end
    opts.transform_keys! &:to_s

    playlists[name] = opts
  end

  if check
    pp (
      if !(diff = playlists.select { |k,v| check[k] != v }).empty?
        {diff: diff}
      else
        :ok
      end
    )
    return
  end

  YAML.dump out, $stdout
end

def self.parse_args(sh)
  sh = sh.dup
  sh.sub!(
    /\B\.\.\/\.\.\/dl\b/,
    "ruby -rjson -e 'JSON.dump [ARGV, ENV.to_hash], $stdout'",
  ) or raise "failed to replace dl"

  args, env = JSON.load(IO.popen("bash", 'w+') { |p|
    p.write sh
    p.close_write
    p.read
  })

  opts = {}
  if %w(http_proxy https_proxy).any? { |k| env.key? k }
    opts[:proxy] = "fr"
  end

  args.map! do |arg|
    case arg
    when "-x" then "--audio"
    when "-v" then "--debug"
    else arg
    end
  end

  cli = MetaCLI.new(["xxx", *args])
  if (invalid = cli.args.grep(/^-/)).size > 0
    raise "invalid args: %p" % [invalid]
  end

  [cli.args, opts.merge(cli.opts)]
end

end # Commands

if $0 == __FILE__
  MetaCLI.new(ARGV).run(Commands)
end
