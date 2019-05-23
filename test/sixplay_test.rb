$:.unshift __dir__ + "/.."
require 'minitest/autorun'
require 'sixplay'

class SixPlayTest < Minitest::Test
  def test_episodes_from_html
    html = page "moundir"
    uri = URI "https://www.6play.fr/moundir-et-les-apprentis-aventuriers-p_5848"
    eps = SixPlay.episodes_from_html html, uri
    # season 4: 8
    # season 3: 41
    # total: 49
    assert_equal 49, eps.size
    assert_equal({4 => 8, 3 => 41}, stats(eps))
    assert_equal 2280, eps.map(&:duration).min

    html = page "princes"
    uri = URI "https://www.6play.fr/les-princes-et-les-princesses-de-lamour-p_3442"
    eps = SixPlay.episodes_from_html html, uri
    # season 0: 55 + 1 (2/2) = 56 (ep 40 has season-6 in URL)
    # season 5: 60 + 1 (2/2) = 60 (missing ep 9)
    # total: 116
    assert_equal 116, eps.size
		assert_equal({nil => 55, 6 => 1, 5 => 60}, stats(eps))
    assert_equal %w(12 2-2 12 22),
      eps.sort_by(&:id).map(&:num).select { |n| n.e == 1 }.map(&:name)

    html = page "ile"
    uri = URI "https://www.6play.fr/l-ile-de-la-tentation-p_13757"
    eps = SixPlay.episodes_from_html html, uri
    assert_equal({nil => 4}, stats(eps))

    html = page "marseillais_asiantour"
    uri = URI "https://www.6play.fr/les-marseillais-asian-tour-p_13125"
    eps = SixPlay.episodes_from_html html, uri
    assert_equal({nil => 61}, stats(eps))

    html = page "marseillais_australia"
    uri = URI "https://www.6play.fr/les-marseillais-australia-p_8711"
    eps = SixPlay.episodes_from_html html, uri
    assert_equal({nil => 61}, stats(eps))

    html = page "marseillais_restedm"
    uri = URI "https://www.6play.fr/les-marseillais-vs-le-reste-du-monde-p_6092"
    eps = SixPlay.episodes_from_html html, uri
    assert_equal({3 => 50}, stats(eps))
  end

  private def stats(eps)
    eps.inject(Hash.new 0) do |h,ep|
      h[ep.num.s] += 1
      h
    end
  end

  private def page(name)
    File.read __dir__ + "/pages/#{name}.html"
  end
end

module SixPlay

class EpNumTest < Minitest::Test
  def test_from_EpNum
    num = EpNum.from_url "saison-4-episode-6-c_12373263"
    assert_equal EpNum[4,6], num

    num = EpNum.from_url "episode-2-saison-3-c_12005001"
    assert_equal EpNum[3,2], num

    num = EpNum.from_url "episode-7-c_12017359"
    assert_equal EpNum[nil,7], num

    num = EpNum.from_url "episode-1-12-c_12220049"
    assert_equal EpNum[nil,1,"12"], num

    num = EpNum.from_title "Saison 4 / Épisode 6"
    assert_equal EpNum[4,6], num

    a = EpNum[nil,7]
    b = EpNum[1,2]
    a.merge! b
    assert_equal EpNum[1,7], a
  end

  def test_to_s
    assert_equal "S04E06", EpNum[4,6].to_s
    assert_equal "S00E06", EpNum[nil,6].to_s
    assert_equal "S00E01-12", EpNum[nil,1,"12"].to_s
    exc = assert_raises RuntimeError do
      EpNum[1,nil].to_s
    end
    assert_match /missing episode/, exc.message
  end
end

end # SixPlay
