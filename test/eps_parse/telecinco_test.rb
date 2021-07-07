require_relative 'parser_test'

module EpsParse

class TelecincoTest < ParserTest
  define_cached_test def do_test_playlist_items
    items = Telecinco.new.playlist_items \
      "https://www.telecinco.es/la-isla-de-las-tentaciones/a-la-carta/"
    assert_equal 24, items.size

    ep = items.fetch 0
    assert_equal "3083070001", ep.id
    assert_equal 3083070001, ep.idx
    assert_equal \
      "https://www.telecinco.es/la-isla-de-las-tentaciones/a-la-carta/programa-dos-completo-29-01-2021-hd_18_3083070001.html",
      ep.url
    assert_nil ep.duration
    assert_equal \
      "La isla de las tentaciones 3 | Programa 2 completo del 28-01-2021 en HD",
      ep.title

    ep = items.fetch 1
    assert_equal "3086220388", ep.id

    ep = items.fetch 2
    assert_equal "3088845023", ep.id

    ep = items.fetch -1
    assert_equal "3115620008", ep.id
  end
end

end # EpsParse
