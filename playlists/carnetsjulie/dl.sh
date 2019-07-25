export http_proxy="http://localhost:23128"

exec ../../dl \
  'https://www.france.tv/france-3/carnets-de-julie/' \
  --rclone_dest=drive:media/replay/carnetsjulie \
  `: properly detect empty output files` \
  --cleanup --nthreads=1
