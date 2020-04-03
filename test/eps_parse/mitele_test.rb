$:.unshift __dir__ + "/../.."
require 'minitest/autorun'
require 'eps_parse'

module EpsParse

class MiteleTest < Minitest::Test
  def test_episodes_from_html
    parser = Mitele.new

    assert parser.uri_ok?(URI(
      "https://www.mitele.es/programas-tv/ven-a-cenar-conmigo/"
    ))
    refute parser.uri_ok?(URI(
      "https://www.mitele.es/programas-tv/ven-a-cenar-conmigo/1505720681723/"
    ))

    eps = parse_eps parser, "venacenar",
      "https://www.mitele.es/programas-tv/ven-a-cenar-conmigo/"
    assert_equal 3, eps.size

    ep = eps.fetch 0
    assert_equal "MDSEPS20200102_0032", ep.id
    assert_equal 47, ep.idx
    assert_equal \
      "https://www.mitele.es/programas-tv/ven-a-cenar-conmigo/temporada-4/especiales/topacio-fresh-gourmet-kike-sanfrancisco-mariajose-cantudo-40_1008218575032/player/",
      ep.url
    assert_equal \
      "02-ene-2019 (mié) - Programa 47 - Una final muy 'Fresh'",
      ep.title
    assert_equal 4199, ep.duration

    ep = eps.find { |e| e.idx == 46 } or raise "ep 46 not found"
    assert_equal \
      "27-dic-2019 (vie) - Programa 46 - María José Cantudo desnuda su alma",
      ep.title

    ep = eps.fetch -1
    assert_equal "MDSEPS20200107_0027", ep.id
    assert_equal 39, ep.idx
    assert_equal \
      "10-sep-2019 (mar) - Programa 39 - Un menú de 'influencer'",
      ep.title

    eps = parse_eps parser, "firstdates",
      "https://www.mitele.es/programas-tv/first-dates/"
    assert_equal 13, eps.size

    assert_equal 1104, eps.fetch(0).idx
    assert_equal "https://www.mitele.es/programas-tv/first-dates/temporada-3/programa-1104-40_1008353575016/player/",
      eps.fetch(0).url
    assert_equal 1092, eps.fetch(-1).idx
  end

  private def parse_eps(parser, name, url)
    parser.episodes_from_html page(name), URI(url)
  end

  private def page(name)
    File.read __dir__ + "/../pages/#{name}.html"
  end
end

end # EpsParse
