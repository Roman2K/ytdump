set -e -o pipefail

. likes.sh

exec ../dl_to_rclone "$(likes_short)" drive:media/music/soundcloud/likes -x
