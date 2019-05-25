rclone_dest=drive:media/replay/anges

exec ../../dl_to_rclone \
  'https://www.youtube.com/channel/UC_ATXX0ACFwsGvJsFJBoLMQ' \
  "$rclone_dest" \
  --rclone_dest="$rclone_dest" \
  --nthreads=2 \
  -v
