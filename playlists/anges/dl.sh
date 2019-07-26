export http_proxy="http://localhost:23128"

exec ../../dl \
  'https://www.youtube.com/channel/UC_ATXX0ACFwsGvJsFJBoLMQ' \
  --rclone_dest=drive:media/replay/anges
