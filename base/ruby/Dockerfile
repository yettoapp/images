# syntax = docker/dockerfile:1.11

ARG REGISTRY

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.3.4

# Debian image to use for base images
ARG DEBIAN_VERSION="bookworm"

FROM ${REGISTRY}yettoapp/bin-tailscale:main AS tailscale
FROM ${REGISTRY}yettoapp/bin-op:main AS op

# Ruby image to use for base image
FROM docker.io/ruby:${RUBY_VERSION}-slim-${DEBIAN_VERSION} AS base

# yes, you're in docker
ENV DOCKER="1"

# Linux UID (user id) for the app user
ENV UID="1666"
# Linux GID (group id) for the app user
ENV GID="1666"

# Apply timezone
ENV TZ="Etc/UTC"
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN \
    # Remove automatic apt cache Docker cleanup scripts
    rm -f /etc/apt/apt.conf.d/docker-clean;

ENV LANG=C.UTF-8

# Set environment
ARG APP_ENV
ENV APP_ENV=${APP_ENV:-development}

WORKDIR /app
ENV DEBIAN_FRONTEND="noninteractive" \
    PATH="${PATH}:/app/bin"

RUN mkdir -p /data

COPY --from=tailscale /usr/local/bin/tailscaled /usr/local/bin
COPY --from=tailscale /usr/local/bin/tailscale /usr/local/bin
RUN mkdir -p /var/run/tailscale /var/cache/tailscale /app/.cache /app/.local

COPY --from=op /usr/local/bin/op /usr/local/bin/op
ENV OP_CONFIG_DIR="/app/.config/op"
RUN mkdir -p /app/.config/op && \
    chmod 700 /app/.config/op

# Authorize app user to launch binaries
ONBUILD RUN echo "app ALL=(root) NOPASSWD:SETENV: /usr/local/bin/op" > /etc/sudoers.d/app

RUN \
    # Creates app user/group and sets home directory
    groupadd --system --gid "${GID}" app && \
    useradd app --uid "${UID}" --gid "${GID}" --create-home --shell /bin/bash && \
    mkdir -p log tmp /data && \
    chown -R "${UID}":"${GID}" log tmp /data

RUN \
    # Mount Apt cache and lib directories from Docker buildx caches
    --mount=type=cache,id=apt-cache-${APP_ENV},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib-${APP_ENV},target=/var/lib/apt,sharing=locked \
    --mount=type=tmpfs,target=/var/log \
    # Apt update & upgrade to check for security updates to Debian image
    apt-get update && \
    apt-get dist-upgrade -yq && \
    apt-get install -y --no-install-recommends  \
    # Common dependencies/tools
    vim \
    sudo

##########################################
### Language specific work starts here ###
##########################################

ENV \
    RUBY_YJIT_ENABLE="1" \
    PATH="${PATH}:/opt/ruby/bin"

RUN \
    # Mount Apt cache and lib directories from Docker buildx caches
    --mount=type=cache,id=apt-cache-${APP_ENV},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib-${APP_ENV},target=/var/lib/apt,sharing=locked \
    --mount=type=tmpfs,target=/var/log \
    # Apt update & upgrade to check for security updates to Debian image
    apt-get update && \
    apt-get dist-upgrade -yq && \
    apt-get install -y --no-install-recommends  \
    # Install jemalloc
    libjemalloc2 \
    patchelf \
    ; \
    # Patch Ruby to use jemalloc
    patchelf --add-needed libjemalloc.so.2 /usr/local/bin/ruby; \
    # Discard patchelf after use
    apt-get purge -y patchelf;
