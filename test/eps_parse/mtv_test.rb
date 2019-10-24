$:.unshift __dir__ + "/../.."
require 'minitest/autorun'
require 'eps_parse'

module EpsParse

class MTVTest < Minitest::Test
  def test_playlist_items
    EpsParse.with_cache Pathname(__dir__).join('..', 'pages_cache') do
      do_test_playlist_items
    end
  end

  def do_test_playlist_items
    parser = MTV.new

    items = parser.playlist_items \
      "http://www.mtv.com/shows/jersey-shore-family-vacation"
    assert_nil items

    items = parser.playlist_items \
      "http://www.mtv.com/shows/jersey-shore-family-vacation/episode-guide"
    assert_equal 55, items.size

    i = items.fetch 0
    assert_equal 310, i.idx
    assert_equal "da67eddd-c03f-11e9-9fb2-70df2f866ace", i.id
    assert_equal \
      "http://www.mtv.com/episodes/g7m5jf/jersey-shore-family-vacation-4-fists-2-bottles-1-shore-house-season-3-ep-310",
      i.url
    assert_equal \
      "2019-10-25 - Season 3, Ep 10 - 4 Fists. 2 Bottles. 1 Shore House.",
      i.title

    i = items.fetch -1
    assert_equal 102, i.idx
  end
end

end # EpsParse
