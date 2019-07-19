exec ../../dl \
  'https://www.tf1.fr/tf1-series-films/sous-le-soleil/videos/replay' \
  --rclone_dest=drive:media/replay/souslesoleil \
  --cache="$HOME/windrive/media/replay/archive/souslesoleil" \
  --nthreads=8 --no-cleanup
