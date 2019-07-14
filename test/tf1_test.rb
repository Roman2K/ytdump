$:.unshift __dir__ + "/.."
require 'minitest/autorun'
require 'tf1'

class TF1Test < Minitest::Test
  def test_episodes_from_html
    parser = TF1.new

    eps = parse_eps parser, "nanny",
      "https://www.tf1.fr/tfx/super-nanny/videos/replay"
    assert_equal 3, eps.size

    ep = eps.fetch 0
    assert_equal 46033473, ep.idx
    assert_equal "46033473", ep.id
    assert_equal \
      "https://www.tf1.fr/tfx/super-nanny/videos/super-nanny-je-ne-sais-pas-dire-non-a-mes-enfants-46033473.html",
      ep.url
    assert_equal 5460, ep.duration
    assert_equal \
      "Replay - Vendredi 05/07/19 - 22:38 - Super Nanny - Je ne sais pas dire non à mes enfants",
      ep.title

    ep = eps.fetch 1
    assert_equal "11324868", ep.id
    assert_equal 5580, ep.duration

    ep = eps.fetch 2
    assert_equal "43922083", ep.id
    assert_equal 5160, ep.duration
  end

  private def page(name)
    File.read __dir__ + "/pages/#{name}.html"
  end

  private def parse_eps(parser, name, url)
    html = page name
    uri = URI url
    parser.episodes_from_html(html, uri)
  end
end
