Item = Struct.new :idx, :id, :url, :title, keyword_init: true do
  def self.from_json(idx, attrs)
    id = attrs.fetch("id")
    new \
      idx: idx,
      id: id,
      title: attrs.fetch("title") {
        URI(attrs.fetch("url")).path.split("/").fetch(-1)
      },
      url:
        case attrs.fetch("ie_key")
        when "Youtube"
          "https://youtu.be/#{id}"
        else
          attrs.fetch "url"
        end
  end
end
