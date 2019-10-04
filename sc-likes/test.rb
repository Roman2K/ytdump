require_relative 'main'
require 'minitest/autorun'

class ClientTest < Minitest::Test
  def test_server_err
    assert Client::SERVER_ERR[make_err "500"]
    assert Client::SERVER_ERR[make_err "503"]
    refute Client::SERVER_ERR[make_err "400"]
  end

  private def make_err(code)
    SoundCloud::ResponseError.new \
      Net::HTTPResponse.allocate.tap { |r|
        r.instance_variable_set "@code", code
        assert_equal code, r.code  # sanity check
      }
  end
end
