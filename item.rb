Item = Struct.new :idx, :id, :url, :title, :duration, keyword_init: true do
  def self.from_json(idx, attrs)
    id = attrs.fetch("id")
    extractor = attrs["ie_key"] || attrs["extractor_key"] \
      or raise "extractor key not found"
    new \
      idx: idx,
      id: id,
      title: attrs.fetch("title") {
        URI(attrs.fetch("url")).path.split("/").fetch(-1)
      },
      duration: attrs["duration"],
      url:
        case extractor
        when "Youtube"
          "https://youtu.be/#{id}"
        else
          attrs.fetch "url"
        end
  end
end
