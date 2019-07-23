$:.unshift __dir__ + "/../.."
require 'minitest/autorun'
require 'eps_parse'

module EpsParse

class AnabolicTVTest < Minitest::Test
  def test_episodes_from_html
    parser = AnabolicTV.new

    eps = parse_eps parser, "bostin_anabtv",
      "https://anabolictv.com/channels/team3cc-bostin-loyd"
    assert_equal 3, eps.size

    ep = eps.fetch 0
    assert_equal 20190624204231, ep.idx
    assert_equal '20190624204231', ep.id
    assert_equal \
      "https://anabolictv.com/2019/06/bostin-loyd-and-tyler-woosley-talk-about-steroids-drugs-in-bodybuilding/?channel=team3cc-bostin-loyd",
      ep.url
    assert_equal \
      "Bostin Loyd and Tyler Woosley talk about Steroids & Drugs in bodybuilding",
      ep.title

    ep = eps.fetch 1
    assert_equal 20190618161538, ep.idx

    ep = eps.fetch 2
    assert_equal 20190614202412, ep.idx
  end

  private def parse_eps(parser, name, url)
    parser.episodes_from_html page(name), URI(url)
  end

  private def page(name)
    File.read __dir__ + "/../pages/#{name}.html"
  end
end

end # EpsParse
