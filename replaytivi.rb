require 'nokogiri'
require_relative 'eps_parse'
require_relative 'item'

class ReplayTivi
  NTHREADS = 4

  def min_duration; 20 * 60 end

  def episodes(url)
    uri = URI url
    uri.host == "www.replaytivi.fr" \
      && uri.path.start_with?("/programme/") \
      or return

    resp = EpsParse.request_get! uri

    eps = Nokogiri::HTML.parse(resp.body).css("a:has(.icon-video)").map do |a|
      Ep.new \
        uri: uri.dup.tap { |u|
          u.path = a["href"].tap do |path|
            path =~ /-\d+$/ or raise "invalid episode URL"
          end
        },
        item: Item.new(
          title: (a.css("img[alt]").first&.[]("alt") \
            =~ /Saison\s+(\d+)\s.*[EÉ]pisode\s+(\d+)/i \
            and "S%02dE%02d" % [$1,$2] \
            or raise "missing season+ep number in thumbnail"),
          duration: (a.css(".icon-video").text[/(\d+)\s+min/i, 1] \
            or raise "missing duration").to_i * 60
        )
    end

    q = Queue.new
    threads = NTHREADS.times.map do
      Thread.new do
        Thread.current.abort_on_exception = true
        while ep = q.shift
          ep.fetch_url!
        end
      end
    end
    eps.each { |ep| q << ep }
    q.close
    threads.each &:join

    eps
  end

  Ep = Struct.new :item, :uri, keyword_init: true do
    def fetch_url!
      item.url =
        Nokogiri::HTML.parse(EpsParse.request_get!(uri).body).
          css("a:has(.play):first").
          first&.[]("href") \
            or raise "missing episode URL"
      item.id =
        case item.url
        when /6play\.fr\/.+c_(\d+)\b/ then $1
        else raise "unsupported replay website"
        end
      item.idx = item.id.to_i
    end

    def playlist_item
      item
    end
  end
end
