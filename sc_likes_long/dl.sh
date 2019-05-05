set -e -o pipefail

. ../sc_likes/likes.sh

exec ../dl_to_rclone "$(likes_long)" drive:media/music/soundcloud/likes_long -x
