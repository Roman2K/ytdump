# --- Build image
FROM ruby:2.5.5-alpine3.10 as builder
ARG rclone_version=1.49.3

# bundle install deps
RUN apk add --update ca-certificates git build-base openssl-dev
RUN gem install bundler -v '>= 2'

# rclone
RUN cd /tmp \
  && wget https://github.com/rclone/rclone/releases/download/v${rclone_version}/rclone-v${rclone_version}-linux-amd64.zip \
  && unzip rclone-*.zip \
  && mv rclone-*/rclone /

# bundle install
COPY . /ytdump
RUN cd /ytdump && bundle

# --- Runtime image
FROM ruby:2.5.5-alpine3.10

COPY --from=builder /rclone /opt/rclone
COPY --from=builder /ytdump /opt/ytdump
COPY --from=builder /ytdump/docker/rclone /usr/bin/rclone
COPY --from=builder /usr/local/bundle /usr/local/bundle

RUN apk --update upgrade \
  && apk add --no-cache ca-certificates bash python3 ffmpeg
RUN pip3 install youtube-dl

RUN addgroup -g 1000 -S ytdump \
  && adduser -u 1000 -S ytdump -G ytdump \
  && chown -R ytdump: /opt/ytdump

RUN mkdir /meta \
  && chmod 700 /meta \
  && chown ytdump: /meta

VOLUME /meta

USER ytdump
RUN cd \
  && mkdir -p .config/rclone \
  && chmod 700 .config

WORKDIR /opt/ytdump
ENTRYPOINT ["./docker/entrypoint"]
