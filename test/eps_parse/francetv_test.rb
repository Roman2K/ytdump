$:.unshift __dir__ + "/../.."
require 'minitest/autorun'
require 'eps_parse'

module EpsParse

class FranceTVTest < Minitest::Test
  def test_episodes_from_html
    parser = FranceTV.new

    eps = parse_eps parser, "boyard",
      "https://www.france.tv/france-2/fort-boyard/"

    assert_equal 5, eps.size

    ep = eps.fetch 0
    assert_equal "1030773", ep.id
    assert_equal 1030773, ep.idx
    assert_equal \
      "https://www.france.tv/france-2/fort-boyard/fort-boyard-saison-30/1030773-fort-boyard.html",
      ep.url
    assert_equal "Épisode du samedi 20 juillet 2019", ep.title
    assert_equal 132*60, ep.duration

    ep = eps.fetch 4
    assert_equal "1011691", ep.id
    assert_equal 1011691, ep.idx
    assert_equal \
      "https://www.france.tv/france-2/fort-boyard/1011691-fort-boyard.html",
      ep.url
  end

  private def parse_eps(parser, name, url)
    parser.episodes_from_html page(name), URI(url)
  end

  private def page(name)
    File.read __dir__ + "/../pages/#{name}.html"
  end
end

end # EpsParse
