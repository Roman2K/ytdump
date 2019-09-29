export http_proxy="http://wis_squid:23128"

exec ../../dl \
  'https://www.6play.fr/l-incroyable-famille-kardashian-p_10941' \
  --rclone_dest=drive:media/replay/kardashian \
  --no-check_empty
