exec ../../dl_to_rclone \
  'https://www.6play.fr/moundir-et-la-plage-de-la-derniere-chance-p_14151' \
  drive:media/replay/moundir_derchance \
  --min_duration=`bc <<<"10 * 60"`
