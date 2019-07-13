$:.unshift __dir__ + "/.."
require 'minitest/autorun'
require 'item'

class ItemTest < Minitest::Test
  def test_from_json
    item = Item.from_json 2,
      "id" => "foo",
      "extractor_key" => "Youtube",
      "url" => "example.com/abc/def"

    assert_equal 2, item.idx
    assert_equal "foo", item.id
    assert_equal "def", item.title
    assert_equal "https://youtu.be/foo", item.url
  end
end
