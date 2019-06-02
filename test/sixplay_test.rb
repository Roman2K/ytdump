$:.unshift __dir__ + "/.."
require 'minitest/autorun'
require 'sixplay'

class SixPlayTest < Minitest::Test
  MIN_DURATION = 20 * 60

  def test_episodes_from_html_season
    parser = SixPlay.new

    eps = parse_eps parser, "moundir",
      "https://www.6play.fr/moundir-et-les-apprentis-aventuriers-p_5848"
    # season 4: 8
    # season 3: 41
    # total: 49
    assert_equal 49, eps.size
    assert_equal({4 => 8, 3 => 41}, stats(eps))
    assert_equal 2280, eps.map(&:duration).min

    eps = parse_eps parser, "moundir_derchance",
      "https://www.6play.fr/moundir-et-la-plage-de-la-derniere-chance-p_14151"
    assert_equal 0, eps.size

    eps = parse_eps parser, "princes",
      "https://www.6play.fr/les-princes-et-les-princesses-de-lamour-p_3442"
    # season 0: 55 + 1 (2/2) = 56 (ep 40 has season-6 in URL)
    # season 5: 60 + 1 (2/2) = 60 (missing ep 9)
    # total: 116
    assert_equal 116, eps.size
		assert_equal({nil => 55, 6 => 1, 5 => 60}, stats(eps))
    assert_equal %w(12 2-2 12 22),
      eps.sort_by(&:id).map(&:num).select { |n| n.e == 1 }.map(&:name)

    eps = parse_eps parser, "ile",
      "https://www.6play.fr/l-ile-de-la-tentation-p_13757"
    assert_equal({nil => 4}, stats(eps))

    eps = parse_eps parser, "marseillais_asiantour",
      "https://www.6play.fr/les-marseillais-asian-tour-p_13125"
    assert_equal({nil => 61}, stats(eps))

    eps = parse_eps parser, "marseillais_australia",
      "https://www.6play.fr/les-marseillais-australia-p_8711"
    assert_equal({nil => 61}, stats(eps))

    eps = parse_eps parser, "marseillais_restedm",
      "https://www.6play.fr/les-marseillais-vs-le-reste-du-monde-p_6092"
    assert_equal({3 => 50}, stats(eps))

    eps = parse_eps parser, "marseillais_restedm",
      "https://www.6play.fr/les-marseillais-vs-le-reste-du-monde-p_6092"
    assert_equal({3 => 50}, stats(eps))
  end

  private def parse_eps(parser, name, url, min_duration: 20 * 60)
    html = page name
    uri = URI url
    parser.
      episodes_from_html(html, uri).
      select { |ep| ep.duration >= min_duration }
  end

  def test_episodes_from_html_no_season
    parser = SixPlay.new

    eps = parse_eps parser, "meillpatissier",
      "https://www.6play.fr/le-meilleur-patissier-les-professionnels-p_6762"
    assert_equal [
      "S00E02 - Le choc des nations / épisode 2",
      "S00E02 - Artus refait le match / épisode 2",
    ], eps.map { |ep| ep.playlist_item.title }

    eps = parse_eps parser, "norbert",
      "https://www.6play.fr/norbert-commis-d-office-p_4668"
    assert_equal 6, eps.size

    eps = parse_eps parser, "maisonav",
      "https://www.6play.fr/maison-a-vendre-p_874"
    assert_equal 8, eps.size

    eps = parse_eps parser, "rechappart",
      "https://www.6play.fr/recherche-appartement-ou-maison-p_918"
    assert_equal 1, eps.size

    eps = parse_eps parser, "cauchemar",
      "https://www.6play.fr/cauchemar-en-cuisine-avec-philippe-etchebest-p_841"
    assert_equal 9, eps.size
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

class SixPlay

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
    b = EpNum[1,2,"xxx"]
    a.merge! b
    assert_equal EpNum[1,7,"xxx"], a
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
