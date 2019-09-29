export http_proxy="http://wis_squid:23128"

exec ../../dl \
  'https://www.france.tv/france-3/carnets-de-julie/' \
  --rclone_dest=drive:media/replay/carnetsjulie
