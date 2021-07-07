require 'minitest/autorun'
require_relative '../../eps_parse'

module EpsParse

class ParserTest < Minitest::Test
  def self.define_cached_test(m)
    m =~ /^do_(test_.+)/ or raise "unhandled uncached method name"
    define_method $1 do
      with_cache { public_send m }
    end
  end

  private def with_cache(&block)
    EpsParse.with_cache Pathname(__dir__).join('..', 'pages_cache'), &block
  end

  protected def parse_eps(parser, name, url)
    page = File.read __dir__ + "/../pages/#{name}.html"
    parser.episodes_from_html page, URI(url)
  end
end

end # EpsParse
