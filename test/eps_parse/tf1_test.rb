$:.unshift __dir__ + "/../.."
require 'minitest/autorun'
require 'eps_parse'

module EpsParse

class TF1Test < Minitest::Test
  def test_playlist_items_single_page
    with_cache { do_test_playlist_items_single_page }
  end

  def test_Page
    p = TF1::Extractor::Page.new URI \
      "https://www.tf1.fr/tf1-series-films/sous-le-soleil/videos/replay/11"
    assert_equal 11, p.num
    assert_equal 12, p.succ.num
    assert_equal \
      "https://www.tf1.fr/tf1-series-films/sous-le-soleil/videos/replay/10",
      (p + -1).uri.to_s
    assert_equal [11, 12, 13], (p .. p+2).map(&:num)
  end

  def do_test_playlist_items_single_page
    items = TF1.new.playlist_items \
      "https://www.tf1.fr/tfx/super-nanny/videos/replay"
    assert_equal 3, items.size

    ep = items.fetch 0
    assert_equal "201907121905", ep.id
    assert_equal 201907121905, ep.idx
    assert_equal \
      "https://www.tf1.fr/tfx/super-nanny/videos/super-nanny-depasses-par-nos-enfants-nous-narrivons-pas-a-organiser-notre-mariage-73252702.html",
      ep.url
    assert_equal 5220, ep.duration
    assert_equal \
      "Replay - Vendredi 12/07/19 - 19:05 - Super Nanny - Dépassés par nos enfants, nous n'arrivons pas à organiser notre mariage",
      ep.title

    ep = items.fetch 1
    assert_equal "201907122054", ep.id
    assert_equal 5580, ep.duration

    ep = items.fetch 2
    assert_equal "201907122250", ep.id
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
    assert_equal 480, items.size

    items.map(&:id).grep_v(/^s\d\de\d\d(-\d+)?$/).tap do |invalid|
      assert_equal [], invalid
    end
    assert_equal 0, items.group_by(&:id).count { |k,items| items.size != 1 }
    assert_equal %w( s06e30-2 s06e30 ),
      items.select { |it| it.idx == 630 }.map(&:id)

    it = items.fetch 0
    assert_equal \
      "Replay - Jeudi 22/08/19 - 12:01 - Sous le soleil - S13 E40 - Trois cordes au cou",
      it.title
    assert_equal "s13e40", it.id
    assert_equal 1340, it.idx
    assert_equal 3000, it.duration

    it = items.fetch -1
    assert_equal "Replay - Lundi 03/06/19 - 07:01 - Sous le soleil - S01  E01 - Plage à vendre",
      it.title
    assert_equal "s01e01", it.id
    assert_equal 101, it.idx
    assert_equal 3000, it.duration

    items = TF1.new.playlist_items \
      "https://www.tf1.fr/tfx/la-villa-des-coeurs-brises/videos/replay"
    assert_equal 341, items.size  # 17 pages * 20 eps + 1
  end
end

end # EpsParse
