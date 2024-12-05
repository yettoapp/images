# syntax = docker/dockerfile:1.11

FROM debian:bookworm-slim

RUN echo "fonts-liberation libasound2 libdrm2 libgbm1 libnspr4 libnss3 libu2f-udev libvulkan1 wget xdg-utils \
    libatk-bridge2.0-0 libatk1.0-0 libatspi2.0-0 libcairo2 libcups2 libdbus-1-3 libglib2.0-0 \
    libgtk-3-dev libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2" > /tmp/chrome_dependencies

RUN --mount=type=cache,id=dev-apt-cache,sharing=locked,target=/var/cache/apt \
    --mount=type=cache,id=dev-apt-lib,sharing=locked,target=/var/lib/apt \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y sudo curl ca-certificates

# Set Chrome variables. Get versions from
# https://www.ubuntuupdates.org/package/google_chrome/stable/main/base/google-chrome-stable
ARG CHROME_URL="https://dl.google.com/linux/chrome/deb/pool/main/g/google-chrome-stable/google-chrome-stable"
ARG CHROME_VERSION="127.0.6533.88-1"
ARG CHROME_BIN_NAME="chrome"
ARG CHROME_OS_NAME="amd64"

# Install Chrome.
RUN curl -o "/tmp/${CHROME_BIN_NAME}.deb" "${CHROME_URL}_${CHROME_VERSION}_${CHROME_OS_NAME}.deb"
