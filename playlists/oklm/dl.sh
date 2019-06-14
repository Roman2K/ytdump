. urls.sh

exec ../../dl "${urls[@]}" \
  --rclone_dest=drive:media/music/oklm \
  -x
