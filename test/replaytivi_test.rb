$:.unshift __dir__ + "/.."
require 'minitest/autorun'
require 'replaytivi'

class ReplayTiviTest < Minitest::Test
  def test_playlist_items
    EpsParse.with_cache Pathname(__dir__).join("pages_cache") do
      do_test_playlist_items
    end
  end

  def do_test_playlist_items
    parser = ReplayTivi.new

    items = parser.playlist_items \
      "http://www.replaytivi.fr/replay/moundir-et-les-apprentis-aventuriers-293310"
    assert_nil items

    items = parser.playlist_items \
      "http://www.replaytivi.fr/programme/moundir-et-les-apprentis-aventuriers"
    assert_equal 25, items.size

    assert_equal "S04E16", items.first.title
    assert_equal "S03E33", items.last.title

    item = items.first
    assert_equal "12381579", item.id
    assert_equal 12381579, item.idx
    assert_equal 2820, item.duration
  end
end
