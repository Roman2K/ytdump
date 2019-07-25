export http_proxy="http://localhost:23128"

exec ../../dl \
  'https://www.france.tv/france-2/fort-boyard/' \
  --rclone_dest=drive:media/replay/boyard
