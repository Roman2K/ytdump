$:.unshift __dir__ + "/../.."
require 'minitest/autorun'
require 'eps_parse'

module EpsParse

class TF1Test < Minitest::Test
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

  def do_test_playlist_items_empty
    items = TF1.new.playlist_items \
      "https://www.tf1.fr/tfx/super-nanny/videos/replay"
    assert_equal 0, items.size
  end

  def do_test_playlist_items_multipage
    items = TF1.new.playlist_items \
      "https://www.tf1.fr/tf1-series-films/sous-le-soleil/videos/replay"
    assert_equal 480, items.size

    items.map(&:id).grep_v(/^s\d\de\d\d(-\d+)?$/).tap do |invalid|
      assert_equal [], invalid
    end
    assert_equal 0, items.group_by(&:id).count { |k,items| items.size != 1 }
    assert_equal %w( s01e01 ), items.select { |it| it.idx == 101 }.map(&:id)
    assert_equal %w( s11e15-2 s11e15 ),
      items.select { |it| it.idx == 1115 }.map(&:id)

    it = items.fetch 0
    assert_equal \
      "Replay - Jeudi 22/08/19 - 14:01 - Sous le soleil - S13 E40 - Trois cordes au cou",
      it.title
    assert_equal "s13e40", it.id
    assert_equal 1340, it.idx
    assert_equal 3000, it.duration

    it = items.fetch -1
    assert_equal "Replay - Lundi 03/06/19 - 09:01 - Sous le soleil - S01  E01 - Plage à vendre",
      it.title
    assert_equal "s01e01", it.id
    assert_equal 101, it.idx
    assert_equal 3000, it.duration

    items = TF1.new.playlist_items \
      "https://www.tf1.fr/tfx/la-villa-des-coeurs-brises/videos/replay"
    assert_equal (25 * 4 * 4) + (10 * 4 + 1), items.size
  end

  instance_methods.each do |m|
    m =~ /^do_(test_playlist_items.+)/ or next
    define_method $1 do
      with_cache { __send__ m }
    end
  end

  private def with_cache(&block)
    EpsParse.with_cache Pathname(__dir__).join('..', 'pages_cache'), &block
  end
end

end # EpsParse
