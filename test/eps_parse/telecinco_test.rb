$:.unshift __dir__ + "/../.."
require 'minitest/autorun'
require 'eps_parse'

module EpsParse

class TelecincoTest < Minitest::Test
  def test_playlist_items_single_page
    with_cache { do_test_playlist_items }
  end

  def do_test_playlist_items
    items = Telecinco.new.playlist_items \
      "https://www.telecinco.es/la-isla-de-las-tentaciones/a-la-carta/"
    assert_equal 9, items.size

    ep = items.fetch 0
    assert_equal "3079395004", ep.id
    assert_equal 3079395004, ep.idx
    assert_equal \
      "https://www.telecinco.es/la-isla-de-las-tentaciones/a-la-carta/programa-uno-completo-21-01-2021-hd_18_3079395004.html",
      ep.url
    assert_nil ep.duration
    assert_equal \
      "La isla de las tentaciones 3 | Programa 1 completo del 21-01-2021 en HD",
      ep.title

    ep = items.fetch 1
    assert_equal "3081495027", ep.id

    ep = items.fetch 2
    assert_equal "3083070001", ep.id
  end

  private def with_cache(&block)
    EpsParse.with_cache Pathname(__dir__).join('..', 'pages_cache'), &block
  end
end

end # EpsParse
