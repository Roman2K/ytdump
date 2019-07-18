require 'nokogiri'
require_relative 'eps_parse'
require_relative 'item'

class TF1
  def min_duration; 20 * 60 end

  # https://www.tf1.fr/tf1/ninja-warrior/videos/replay
  def playlist_items(url)
    uri = URI url
    uri.host.sub(/^www\./, "") == "tf1.fr" \
      && uri.path.split("/")[-2..-1] == %w( videos replay ) \
      or return

    Extractor.new(uri).from_html EpsParse.request_get!(uri).body
  end

  class Extractor
    NTHREADS = 4

    def initialize(uri)
      @page = Page.new uri
    end

    def from_html(html)
      doc = Nokogiri::HTML.parse(html)
      pages = doc.css("nav[class^=Paging_] a").
        map { |el| internal_uri_from_el el }.
        slice(2..-2) || []

      q = Queue.new
      page_thrs = spawn_page_threads pages do |it|
        q << it
      end

      items = items_from_doc(doc).
        map.with_index { |it,i| Pos.new(@page.num, i, it) }
      collect_thr = Thread.new do
        Thread.current.abort_on_exception = true
        while it = q.shift
          items << it
        end
      end

      page_thrs.each &:join
      q.close
      collect_thr.join

      items = items.sort.reverse.map! &:obj
      id_k = items.each_with_object(Hash.new 0) { |it,h|
        it.ids.to_h.each { |k,v| h[k] += 1 if v }
      }.yield_self { |h|
        %i(ep id sum).find { |k| h[k] == items.size }
      } or raise "some IDs couldn't be generated"

      items.map.with_index do |it, idx|
        it.playlist_item do |pl_it|
          pl_it.id, pl_it.idx = it.ids.fetch id_k
          pl_it.idx ||= idx
        end
      end
    end

    Pos = Struct.new :page, :index, :obj do
      def <=>(other)
        self.class === other or return
        [page, index] <=> [other.page, other.index]
      end
    end

    private def spawn_page_threads(uris)
      return [] if uris.empty?
      q = Queue.new
      threads = NTHREADS.times.map do
        Thread.new do
          Thread.current.abort_on_exception = true
          while page = q.shift
            Extractor.new(page.uri).
              items_from_html(EpsParse.request_get!(page.uri).body).
              each.with_index { |it,i| yield Pos.new(page.num, i, it) }
          end
        end
      end
      uris.each { |uri| q << Page.new(uri) }
      q.close
      threads << Thread.new do
        Thread.current.abort_on_exception = true
        Page.new(uris.last).each_next do |page|
          items = Extractor.new(page.uri).
            items_from_html(EpsParse.request_get!(page.uri).body)
          break if items.empty?
          items.each.with_index { |it,i| yield Pos.new(page.num, i, it) }
        end
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

      def each_next
        num = @num
        loop do
          num += 1
          uri = @uri.dup.tap { |u| u.path = "#{@prefix}/#{num}" }
          yield self.class.new(uri)
        end
      end
    end

    def items_from_html(html)
      items_from_doc Nokogiri::HTML.parse html
    end

    def items_from_doc(doc)
      doc.css("[class^='VideoCard_card__box']").map do |el|
        ep_uri = el.css("a:first").first.
          tap { |e| e or raise "link element not found" }.
          yield_self { |e| internal_uri_from_el e }

        EpItem.new \
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

    EpItem = Struct.new :uri, :duration, :title, keyword_init: true do
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

    class EpIDs < Hash
      def initialize(uri, title)
        if title =~ /\bS(\d+)\b.*\bEp?(\d+)\b/i
          s,e = [$1,$2].map &:to_i
          store :ep, ["s%02de%02d" % [s,e], s * 100 + e]
        end
        if uri.path =~ /-(\d{2,})\.\w+$/
          id = $1
          store :id, [id, id.to_i]
        end
        if uri.path =~ %r{/videos/(.+?)\.\w+$}
          store :sum, Digest::SHA1.hexdigest($1)[0,7]
        end
        freeze
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
