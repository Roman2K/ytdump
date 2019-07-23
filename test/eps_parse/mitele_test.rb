$:.unshift __dir__ + "/../.."
require 'minitest/autorun'
require 'eps_parse'

module EpsParse

class MiteleTest < Minitest::Test
  def test_episodes_from_html
    parser = Mitele.new

    eps = parse_eps parser, "venacenar",
      "https://www.mitele.es/programas-tv/ven-a-cenar-conmigo/1505720681723/"
    assert_equal 83, eps.size

    ep = eps.fetch 0
    assert_equal "5c9a0e4eb95c9bcd698b45ac", ep.id
    assert_equal 300, ep.idx
    assert_equal \
      "https://www.mitele.es/programas-tv/ven-a-cenar-conmigo/5c9a0e4eb95c9bcd698b45ac/player/",
      ep.url
    assert_equal "Celebramos 300 programas con poderío", ep.title
    assert_equal 2503, ep.duration

    ep = eps.fetch -1
    assert_equal "5aaf9ccab95c9b77358b484f", ep.id
    assert_equal 131, ep.idx
  end

  private def parse_eps(parser, name, url)
    parser.episodes_from_html page(name), URI(url)
  end

  private def page(name)
    File.read __dir__ + "/../pages/#{name}.html"
  end
end

end # EpsParse
