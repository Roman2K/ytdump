set -e -o pipefail

. ../sc_likes/likes.sh

exec ../../dl \
  "$(likes_long)" \
  --rclone_dest=drive:media/music/soundcloud/likes_long \
  -x
