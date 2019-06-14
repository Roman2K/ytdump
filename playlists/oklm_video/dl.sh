. ../oklm/urls.sh

exec ../../dl "${urls[@]}" \
  --rclone_dest=drive:media/yt/oklm \
  --nthreads=1 --min_df=2048
