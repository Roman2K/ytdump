require 'minitest/autorun'
require_relative 'dl'
require 'stringio'

class LogTest < Minitest::Test
  def test_log
    io = StringIO.new
    log = Log.new io: io
    clear = -> do
      io.truncate 0
      io.rewind
    end

    clear[]
    log.debug "test"
    assert_equal <<-EOS, io.string
DEBUG test
EOS

    clear[]
    log.sub("foo").debug "test"
    assert_equal <<-EOS, io.string
DEBUG foo: test
EOS

    clear[]
    log.sub("foo").sub("bar").debug "test"
    assert_equal <<-EOS, io.string
DEBUG foo: bar: test
EOS

    clear[]
    log.level = :info
    log.debug "some debug"
    log.info "some info"
    log.sub("foo").debug "some debug 2"
    log.sub("foo").info "some info 2"
    assert_equal <<-EOS, io.string
 INFO some info
 INFO foo: some info 2
EOS
  end
end
