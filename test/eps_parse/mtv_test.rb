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
    assert_equal 20, items.size

    i = items.fetch 0
    assert_equal 219, i.idx
    assert_equal "4bc40c1b-7bab-11e9-9fb2-70df2f866ace", i.id
    assert_equal \
      "http://www.mtv.com/episodes/uiez7n/jersey-shore-family-vacation-the-united-states-v-the-situation-pt-2-season-2-ep-219",
      i.url
    assert_equal \
      "2019-07-12 - Season 2, Ep 19 - The United States v. The Situation, Pt. 2",
      i.title

    i = items.fetch -1
    assert_equal 201, i.idx
  end
end

end # EpsParse
