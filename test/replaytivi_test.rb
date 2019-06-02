$:.unshift __dir__ + "/.."
require 'minitest/autorun'
require 'replaytivi'
require 'digest/sha1'

class ReplayTiviTest < Minitest::Test
  def test_episodes
    replace_method ReplayTivi, :get_response!, method(:get_response!) do
      do_test_episodes
    end
  end

  def do_test_episodes
    parser = ReplayTivi.new

    eps = parser.episodes \
      "http://www.replaytivi.fr/replay/moundir-et-les-apprentis-aventuriers-293310"
    assert_nil eps

    eps = parser.episodes \
      "http://www.replaytivi.fr/programme/moundir-et-les-apprentis-aventuriers"
    assert_equal 25, eps.size
    items = eps.map &:playlist_item

    assert_equal "S04E16", items.first.title
    assert_equal "S03E33", items.last.title

    item = items.first
    assert_equal "12381579", item.id
    assert_equal 12381579, item.idx
    assert_equal 2820, item.duration
  end

  private def get_response!(uri)
    path = File.join __dir__, "pages_cache", Digest::SHA1.hexdigest(uri.to_s)
    $stderr.puts "reading cached page #{uri} at #{path}"
    begin
      File.open(path, 'r') { |f| Marshal.load f }
    rescue Errno::ENOENT
      $stderr.puts "cache MISS"
      resp = Net::HTTP.get_response uri
      resp.kind_of? Net::HTTPSuccess or raise "unexpected response"
      File.open(path, 'w') { |f| Marshal.dump resp, f }
      $stderr.puts "written %d bytes" % File.size(path)
      resp
    end
  end

  private def replace_method(obj, m, block)
    cla = class << obj; self; end
    orig = cla.instance_method m
    cla.define_method m, &block
    begin
      yield
    ensure
      cla.define_method m, orig
    end
  end
end
