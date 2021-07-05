require 'json'

module EpsParse

class MTV < Parser
  CHECK = [
    "https://www.mtv.com/shows/jersey-shore-family-vacation",
    -> n { n >= 10 },
  ]

  def uri_ok?(uri)
    uri.scheme == 'https' \
      && uri.host.sub(/^www\./, "") == "mtv.com" \
      && (cs = uri.path.split("/")).size == 3 \
      && cs[0,2] == ["", "shows"] \
      && uri.query.nil?
  end

  def episodes_from_doc(doc, uri)
    PageData.new(doc, uri, log: @log["PageData"]).enum_for(:each_item).map { |i|
      i.fetch("meta").fetch("header").fetch("title").fetch("text") \
        =~ /S(\d+)\b.*E(\d+)/ or raise "season+ep number not found"
      snum, epnum = $1.to_i, $2.to_i

      i.fetch("meta").fetch("date") =~ %r{^(\d{1,2})/(\d{1,2})/(\d{4})$} \
        or raise "invalid date format"
      date = Time.new $3, $1, $2

      Item.new \
        id: i.fetch("id"),
        idx: snum * 100 + epnum,
        url: PageData.add_path(uri, i.fetch("url")).to_s,
        duration: i.fetch("media").fetch("duration").split(":").reverse.
          then { |ss,mm,hh,*rest|
            rest.empty? or raise "invalid duration format"
            ss.to_i + mm.to_i * 60 + hh.to_i * 3600
          },
        title: "%s - Season %d, Ep %d - %s" % [
          date.strftime("%Y-%m-%d"),
          snum, epnum,
          i.fetch("meta").fetch("subHeader"),
        ]
    }
  end

  class PageData
    def initialize(doc, uri, log:)
      @uri = uri
      @log = log
      @items, @more_url, @next_season = extract_items doc
    end

    def each_item
      pd = self
      loop do
        pd.each_own_item { yield _1 }
        sz = pd.next_season or break
        slog = @log[season: sz.fetch("label")]
        uri = make_uri sz.fetch "url"
        slog[url: uri.path].info "fetching next season"
        pd = PageData.new \
          EpsParse::Parser.doc(EpsParse.request_get!(uri).body),
          uri,
          log: slog
      end
    end

    attr_reader :next_season
    protected :next_season

    protected def each_own_item
      items, more_url = @items, @more_url
      @log[count: items.size].info "preloaded items"
      loop do
        has_episodes = false
        items.each do |it|
          it.fetch("itemType") == "episode" or next
          has_episodes = true
          yield it
        end
        has_episodes && more_url or break
        more_url.include?("/episode/") or raise "invalid episodes URL path"
        data = JSON.parse EpsParse.request_get!(make_uri more_url).body
        items = data.fetch "items"
        more_url = data["loadMore"]&.fetch("url")
        @log[count: items.size].info "loaded more items"
      end
    end

    private def make_uri(path)
      self.class.add_path @uri, path
    end

    def self.add_path(uri, path)
      path.start_with? "/" or raise "invalid URL path"
      u = uri.dup
      u.path, u.query = path.split '?', 2
      u
    end

    private def extract_items(doc)
      d = doc.css("script").inject(nil) { |_,el|
        if el.text =~ /\bwindow\.__DATA__\s*=\s*(.+);/
          break JSON.parse $1
        end
      } or raise "missing page data"

      d = d.fetch("children").find { _1.fetch("type") == "MainContainer" } \
        or raise "missing MainContainer"

      next_season = d.fetch("children").inject(nil) { |_,h|
        h.fetch("type") == "SeasonSelector" or next
        props = h.fetch "props"
        break props.fetch("items")[props.fetch("selectedIndex") + 1]
      }

      guide_found = false
      items, more_url = d.fetch("children").inject(nil) { |_,h|
        h.fetch("type") == "LineList" or next
        props = h.fetch("props")
        if props.fetch("type") == "video-guide"
          ok = props.fetch("isEpisodes")
          guide_found = true
        end
        ok or next
        break \
          props.fetch("items"),
          props["loadMore"]&.fetch("url")
      }

      guide_found or raise "missing episodes list"
      [ items || [], 
        more_url,
        next_season ]
    end
  end
end

end # EpsParse
