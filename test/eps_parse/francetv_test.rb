$:.unshift __dir__ + "/../.."
require 'minitest/autorun'
require 'eps_parse'

module EpsParse

class FranceTVTest < Minitest::Test
  def test_episodes_from_html
    parser = FranceTV.new

    eps = parse_eps parser, "qpour1champ",
      "https://www.france.tv/france-3/questions-pour-un-champion/"

    assert_equal 5, eps.size

    ep = eps.fetch 0
    assert_equal "2555851", ep.id
    assert_equal 2555851, ep.idx
    assert_equal \
      "https://www.france.tv/france-3/questions-pour-un-champion/2555851-emission-du-vendredi-2-juillet-2021.html",
      ep.url
    assert_equal "Émission du vendredi 2 juillet 2021", ep.title
    assert_equal 43*60, ep.duration

    ep = eps.fetch -1
    assert_equal "2547445", ep.id
  end

  private def parse_eps(parser, name, url)
    parser.episodes_from_html page(name), URI(url)
  end

  private def page(name)
    File.read __dir__ + "/../pages/#{name}.html"
  end
end

end # EpsParse
