set -e -o pipefail

. likes.sh

exec ../../dl "$(likes_short)" --rclone_dest=drive:media/music/soundcloud/likes -x
