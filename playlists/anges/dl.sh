export http_proxy="http://wis-squid:23128"

exec ../../dl \
  'https://www.youtube.com/channel/UC_ATXX0ACFwsGvJsFJBoLMQ' \
  --rclone_dest=drive:media/replay/anges
