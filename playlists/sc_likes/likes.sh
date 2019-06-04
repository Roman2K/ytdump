LONG_DURATION=420000

likes() {
  (cd code/sc-likes > /dev/null && bundle exec ruby main.rb)
}

likes_of_duration() {
  likes \
    | jq '.
      | select(.duration '"$1"')
      | {id, title, url: .uri, ie_key: "Soundcloud"}' \
    | jq -s .
}

likes_short() {
  likes_of_duration "< $LONG_DURATION"
}

likes_long() {
  likes_of_duration ">= $LONG_DURATION"
}
