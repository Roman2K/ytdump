require_relative 'parser_test'

module EpsParse

class MTVTest < ParserTest
  define_cached_test def do_test_playlist_items
    parser = MTV.new

    refute parser.uri_ok?(URI(
      URI "https://www.mtv.com/shows/jersey-shore-family-vacation/episode-guide"
    ))
    refute parser.uri_ok?((
      URI "http://www.mtv.com/shows/jersey-shore-family-vacation"
    ))

    items = parser.playlist_items \
      "https://www.mtv.com/shows/jersey-shore-family-vacation"
    assert_equal 20, items.size

    i = items.fetch 0
    assert_equal 419, i.idx
    assert_equal "b6fd7d86-b303-11eb-8774-70df2f866ace", i.id
    assert_equal \
      "https://www.mtv.com/episodes/1to3hc/jersey-shore-family-vacation-mr-p-season-4-ep-19",
      i.url
    assert_equal \
      "2021-07-02 - Season 4, Ep 19 - Mr. P",
      i.title
    assert_equal 2494, i.duration

    i = items.fetch -1
    assert_equal 401, i.idx

    items = parser.playlist_items \
      "https://www.mtv.com/shows/the-hills-new-beginnings"
    assert_equal 21, items.size
    indexes = items.map(&:idx).sort
    assert_equal 101, indexes.fetch(0)
    assert_equal 207, indexes.fetch(-1)
  end
end

end # EpsParse
