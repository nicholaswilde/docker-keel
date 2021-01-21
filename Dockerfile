FROM --platform=linux/amd64 golang:1.14.2 as base
ARG VERSION=0.16.1
WORKDIR /go/src/github.com/keel-hq
RUN \
  echo "**** install packages ****" && \
  apt-get update && \
  apt-get install -y --no-install-recommends \
    git=1:2.20.1-2+deb10u3 \
    curl=7.64.0-4+deb10u1 \
    gcc-arm-linux-gnueabihf=4:8.3.0-1 \
    libc6-dev-armhf-cross=2.28-7cross1 && \
  echo "**** cleanup ****" && \
  apt-get clean && \
  rm -rf \
    /tmp/* \
      /var/lib/apt/lists/ \
      /var/tmp/* && \
  echo "**** downloading keel ****" && \
  git clone https://github.com/keel-hq/keel.git --depth 1 -b ${VERSION}
WORKDIR /go/src/github.com/keel-hq/keel
RUN \
  echo "**** downloading certs ****" && \
  curl --remote-name --time-cond cacert.pem https://curl.haxx.se/ca/cacert.pem && \
  cp cacert.pem ca-certificates.crt && \
  echo "**** building keel ****" && \
  sed -i '/cd cmd/s/^	#*/	/' Makefile && \
  make build-arm && \
  make install

#########################

FROM --platform=linux/amd64 node:10.23-alpine as ui
WORKDIR /app
COPY --from=base /go/src/github.com/keel-hq/keel/ui /app
RUN \
  echo "**** install ui ****" && \
  yarn && \
  yarn run lint --no-fix && \
  yarn run build

#########################

FROM ghcr.io/linuxserver/baseimage-ubuntu:bionic as build
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="nicholaswilde"
ENV XDG_DATA_HOME /data
COPY --from=ui /app/dist /www
COPY --from=base /go/src/github.com/keel-hq/keel/ca-certificates.crt /etc/ssl/certs/
RUN \
  echo "**** install packages ****" && \
  apt-get update && \
  apt-get install -y --no-install-recommends \
    ca-certificates=20201027ubuntu0.18.04.1 && \
  echo "**** cleanup ****" && \
  apt-get clean && \
  rm -rf \
    /tmp/* \
      /var/lib/apt/lists/ \
      /var/tmp/* && \
  echo "**** setting up volumes ****" && \
  mkdir /data && \
  chown -R abc:abc /data
VOLUME /data

#########################

FROM build as build_arm
COPY --from=base /go/src/github.com/keel-hq/keel/cmd/keel/release/keel-linux-arm /bin/keel

FROM build as build_arm64
COPY --from=base /go/src/github.com/keel-hq/keel/cmd/keel/release/keel-linux-aarc64 /bin/keel

FROM build as build_amd64
COPY --from=base /go/bin/keel /bin/keel

#########################

# hadolint ignore=DL3006
FROM build_${TARGETARCH}
EXPOSE 9300
ENTRYPOINT ["/bin/keel"]
