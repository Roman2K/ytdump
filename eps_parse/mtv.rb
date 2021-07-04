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
        url: uri.dup.tap { |u|
          u.path = i.fetch("url").
            tap { _1.start_with? "/" or raise "invalid URL path" }
        }.to_s,
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
      each_own_item { yield _1 }
      pd = self
      while sz = pd.next_season
        slog = @log[season: sz.fetch("label")]
        uri = make_uri sz.fetch "url"
        slog[url: uri.path].info "fetching next season"
        pd = PageData.new \
          EpsParse::Parser.doc(EpsParse.request_get!(uri).body),
          uri,
          log: slog
        pd.each_own_item { yield _1 }
      end
    end

    attr_reader :next_season
    protected :next_season

    protected def each_own_item
      @log[count: @items.size].info "yielding preloaded items"
      @items.each { yield _1 }

      more_url = @more_url
      while more_url
        more_url.include?("/episode/") or raise "invalid episodes URL path"
        data = JSON.parse EpsParse.request_get!(make_uri more_url).body
        items = data.fetch "items"
        @log[count: items.size].info "loaded more items"
        has_episodes = false
        items.each do |it|
          it.fetch("itemType") == "episode" or next
          has_episodes = true
          yield it
        end
        more_url = (data["loadMore"]&.fetch("url") if has_episodes)
      end
    end

    private def make_uri(path)
      path.start_with?("/") or raise "invalid URL path"
      u = @uri.dup
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
        or return "missing MainContainer"

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
