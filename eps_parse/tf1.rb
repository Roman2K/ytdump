module EpsParse

class TF1 < Parser
  CHECK = [
    "https://www.tf1.fr/tf1-series-films/sous-le-soleil/videos/replay",
    480,
  ]

  def min_duration; 20 * 60 end

  # https://www.tf1.fr/tf1/ninja-warrior/videos/replay
  def uri_ok?(uri)
    uri.host.sub(/^www\./, "") == "tf1.fr" \
      && uri.path.split("/")[-2..-1] == %w( videos replay )
  end

  def episodes_from_html(html, uri)
    Extractor.new(uri).from_html html
  end

  class Extractor
    NTHREADS = 4

    def initialize(uri)
      @page = Page.new uri
    end

    def from_html(html)
      doc = Nokogiri::HTML.parse(html)
      pages = doc.css("nav[class^=Paging_]:first a").
        select { |el| el.text.strip =~ /^\d+$/ }.
        map { |el| Page.new(internal_uri_from_el(el)) }.
        slice(1..-1) || []

      [@page, *pages].each_cons(2) do |a,b|
        b.num == a.num+1 or raise "invalid list of pages: #{a.num} -> #{b.num}"
      end

      items = items_from_doc(doc).
        map.with_index { |it,i| Pos.new(@page.num, i, it) }.
        concat spawn_page_threads(pages).flat_map(&:value)

      items = items.sort.reverse.map! &:obj
      id_k = items.each_with_object(Hash.new 0) { |it,h|
        it.ids.to_h.each { |k,v| h[k] += 1 if v }
      }.yield_self { |h|
        %i(ep ts).find { |k| h[k] == items.size }
      } or raise "some IDs couldn't be generated"

      items.map.with_index { |it, idx|
        it.playlist_item do |pl_it|
          pl_it.id, pl_it.idx = it.ids.public_send id_k
          pl_it.idx ||= idx
        end
      }.tap { |items|
        items.group_by(&:id).each do |id, its|
          its.reverse[1..-1].each_with_index do |it, idx|
            it.id = "#{id}-#{idx+2}"
          end
        end
      }
    end

    Pos = Struct.new :page, :index, :obj do
      def <=>(other)
        self.class === other or return
        [page, index] <=> [other.page, other.index]
      end
    end

    private def spawn_page_threads(pages)
      return [] if pages.empty?
      q = Queue.new
      threads = NTHREADS.times.map do
        Thread.new do
          Thread.current.abort_on_exception = true
          pos_items = []
          while page = q.shift
            Extractor.new(page.uri).
              items_from_html(EpsParse.request_get!(page.uri).body).
              each.with_index { |it,i| pos_items << Pos.new(page.num, i, it) }
          end
          pos_items
        end
      end
      pages.each { |p| q << p }
      q.close
      threads << Thread.new do
        Thread.current.abort_on_exception = true
        pos_items = []
        pages.fetch(-1).each_succ do |page|
          items = Extractor.new(page.uri).
            items_from_html(EpsParse.request_get!(page.uri).body)
          break if items.empty?
          items.each.with_index { |it,i| pos_items << Pos.new(page.num, i, it) }
        end
        pos_items
      end
    end

    class Page
      def initialize(uri)
        uri.path =~ %r{(^.+/replay)(?:/(\d+))?$} or raise "invalid page URL"
        @uri = uri
        @prefix = $1
        @num = ($2 || "1").to_i
      end

      attr_reader :uri
      attr_reader :num

      def +(n)
        self.class.new @uri.dup.tap { |u| u.path = "#{@prefix}/#{@num + n}" }
      end

      def succ; self + 1 end
      def <=>(x); self.class === x and num <=> x.num end
      def each_succ; cur = self; loop { yield (cur = cur.succ) } end
    end

    def items_from_html(html)
      items_from_doc Nokogiri::HTML.parse html
    end

    def items_from_doc(doc)
      doc.css("[class^='VideoGrid_videos__item']").map do |el|
        ep_uri = el.css("a:first").first.
          tap { |e| e or raise "link element not found" }.
          yield_self { |e| internal_uri_from_el e }

        Ep.new \
          uri: ep_uri,
          duration: el.css("[class*='_duration_']").
            first.tap { |e| e or raise "duration not found" }.
            yield_self { |e| parse_duration e.text },
          title: \
            el.css(
              "[class*='_header_']:first" \
              ", [class*='_videoLabel_']:first"
            ).tap { |els|
              els.size == 2 or raise "header and/or description not found"
            }.map(&:text).join(" - ")
      end
    end

    Ep = Struct.new :uri, :duration, :title, keyword_init: true do
      def ids
        @ids ||= EpIDs.new uri, title
      end

      def playlist_item
        Item.new(
          url: uri.to_s,
          duration: duration,
          title: title
        ).tap { |it|
          yield it
          it.valid? or raise "invalid item after yield"
        }
      end
    end

    EpIDs = Struct.new :ep, :ts do
      def initialize(uri, title)
        super()
        if title =~ /\bS(\d+)\b.*\bEp?(\d+)\b/i
          s,e = [$1,$2].map &:to_i
          self.ep = ["s%02de%02d" % [s,e], s * 100 + e]
        end
        title =~ /\b(\d\d)\D+(\d\d)\D+(\d\d)\D+(\d\d):(\d\d)\b/ \
          or raise "failed to extract date-time from title"
        ts = Time.new("20#{$3}", $2, $1, $4, $5, 0, 0).strftime("%Y%m%d%H%M")
        self.ts = [ts, ts.to_i]
      end
    end

    private def internal_uri_from_el(el)
      path = el[:href] or raise "link URL missing"
      case path
      when %r{^/tf[x1](?:-.+)?/}
      when %r{^/tmc/}
      else raise "unexpected URL path: %p" % path
      end
      @page.uri.dup.tap { |u| u.path = path }
    end

    private def parse_duration(s)
      case s.strip
      when /^(\d+)m(\d+)?$/ then $1.to_i * 60 + $2.to_i
      when /^(\d+)h(\d+)?$/ then $1.to_i * 3600 + $2.to_i * 60
      else raise "unhandled duration format: %p" % s
      end
    end
  end
end

end # EpsParse
