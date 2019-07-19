$:.unshift __dir__ + "/../.."
require 'minitest/autorun'
require 'eps_parse'

module EpsParse

class TF1Test < Minitest::Test
  def test_playlist_items_single_page
    with_cache { do_test_playlist_items_single_page }
  end

  def do_test_playlist_items_single_page
    items = TF1.new.playlist_items \
      "https://www.tf1.fr/tfx/super-nanny/videos/replay"
    assert_equal 3, items.size

    ep = items.fetch 0
    assert_equal 73252702, ep.idx
    assert_equal "73252702", ep.id
    assert_equal \
      "https://www.tf1.fr/tfx/super-nanny/videos/super-nanny-depasses-par-nos-enfants-nous-narrivons-pas-a-organiser-notre-mariage-73252702.html",
      ep.url
    assert_equal 5220, ep.duration
    assert_equal \
      "Replay - Vendredi 12/07/19 - 19:05 - Super Nanny - Dépassés par nos enfants, nous n'arrivons pas à organiser notre mariage",
      ep.title

    ep = items.fetch 1
    assert_equal "75742737", ep.id
    assert_equal 5580, ep.duration

    ep = items.fetch 2
    assert_equal "80995795", ep.id
    assert_equal 5400, ep.duration
  end

  private def with_cache(&block)
    EpsParse.with_cache Pathname(__dir__).join('..', 'pages_cache'), &block
  end

  def test_playlist_items_multipage
    with_cache { do_test_playlist_items_multipage }
  end

  def do_test_playlist_items_multipage
    items = TF1.new.playlist_items \
      "https://www.tf1.fr/tf1-series-films/sous-le-soleil/videos/replay"
    assert_equal 192, items.size

    items.map(&:id).grep_v(/^s\d\de\d\d$/).tap do |invalid|
      assert_equal [], invalid
    end

    it = items.first
    assert_equal "Replay - Lundi 03/06/19 - 07:01 - Sous le soleil - S01  E01 - Plage à vendre",
      it.title
    assert_equal "s01e01", it.id
    assert_equal 101, it.idx
    assert_equal 3000, it.duration

    it = items.last
    assert_equal \
      "Replay - Lundi 01/07/19 - 11:12 - Sous le soleil - S06 E40 - La femme interdite",
      it.title
    assert_equal "s06e40", it.id
    assert_equal 640, it.idx
    assert_equal 3060, it.duration
  end
end

end # EpsParse
