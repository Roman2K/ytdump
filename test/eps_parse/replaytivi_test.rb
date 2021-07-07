require_relative 'parser_test'

module EpsParse

class ReplayTiviTest < ParserTest
  define_cached_test def do_test_playlist_items
    parser = ReplayTivi.new

    refute parser.uri_ok?(URI(
      "http://www.replaytivi.fr/replay/moundir-et-les-apprentis-aventuriers-293310"
    ))

    items = parser.playlist_items \
      "http://www.replaytivi.fr/programme/moundir-et-les-apprentis-aventuriers"
    assert_equal 25, items.size

    assert_equal "S04E16", items.first.title
    assert_equal "S03E33", items.last.title

    item = items.first
    assert_equal "12381579", item.id
    assert_equal 12381579, item.idx
    assert_equal 2820, item.duration

    items = parser.playlist_items \
      "http://www.replaytivi.fr/programme/les-princes-et-les-princesses-de-lamour"
    assert_equal 6, items.size
    assert_equal "S07E55", items.first&.title

    items = parser.playlist_items \
      "http://www.replaytivi.fr/programme/enquete-exclusive"
    assert_equal "Sorcellerie New Age : les nouveaux gourous de l'Amérique",
      items.first&.title
  end
end

end # EpsParse
