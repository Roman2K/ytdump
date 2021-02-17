# --- Build image
FROM ruby:2.7.2-alpine3.13 as builder

# bundle install deps
RUN apk add --update ca-certificates git build-base openssl-dev
RUN gem install bundler -v '>= 2'

# rclone
ARG rclone_ver=1.54.0
RUN cd /tmp \
  && wget https://github.com/rclone/rclone/releases/download/v${rclone_ver}/rclone-v${rclone_ver}-linux-amd64.zip \
  && unzip rclone-*.zip \
  && mv rclone-*/rclone /

# bundle install
WORKDIR /tmp/bundle-ytdump
COPY Gemfile* ./
RUN bundle
WORKDIR /tmp/bundle-sc-likes
COPY sc-likes/Gemfile* ./
RUN bundle

# --- Runtime image
FROM ruby:2.7.2-alpine3.13
WORKDIR /app

COPY --from=builder /rclone /opt/rclone
COPY --from=builder /usr/local/bundle /usr/local/bundle
RUN apk --update upgrade \
  && apk add --no-cache ca-certificates bash python3 py-pip ffmpeg jq \
  && apk add --no-cache --virtual tmp git 
RUN python3 -m pip install git+https://github.com/ytdl-org/youtube-dl
RUN apk del tmp

COPY . .
COPY docker/rclone /usr/bin/rclone

RUN addgroup -g 1000 -S app \
  && adduser -u 1000 -S app -G app \
  && chown -R app: .

RUN mkdir /meta \
  && chmod 700 /meta \
  && chown app: /meta

USER app
RUN cd \
  && mkdir -p .config/rclone \
  && chmod 700 .config

ENTRYPOINT ["./docker/entrypoint"]
