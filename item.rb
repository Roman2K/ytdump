Item = Struct.new :idx, :id, :url, :title, :duration, keyword_init: true do
  YT_DOMAIN = "youtu.be"
  YT_URL = "https://#{YT_DOMAIN}"

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
      url: case extractor.downcase
        when "youtube"
          "#{YT_URL}/#{id}"
        else
          attrs.fetch "url" do
            attrs.fetch "webpage_url"
          end
        end
  end
  
  def youtube_invalid_title?
    URI(url).host == YT_DOMAIN && title.gsub(/[^\w\s]/, "").strip == "Play all"
  end

  def valid?
    values.all?
  end
end
