# syntax = docker/dockerfile:1.11

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.3.4

# Debian image to use for base images
ARG DEBIAN_VERSION="bookworm"

# version of LiteFS to install
ARG LITEFS_VERSION=0.5

FROM ghcr.io/yettoapp/bin-tailscale:main AS tailscale
FROM ghcr.io/yettoapp/bin-op:main AS op

FROM flyio/litefs:${LITEFS_VERSION} AS litefs


# Ruby image to use for base image
FROM docker.io/ruby:${RUBY_VERSION}-${DEBIAN_VERSION}

ARG GIT_SHA
ENV GIT_SHA=$GIT_SHA

ARG RAILS_ENV
# Set environment for Ruby on Rails
ENV RAILS_ENV=${RAILS_ENV:-production}

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

ENV \
    RAILS_LOG_TO_STDOUT="1" \
    RAILS_SERVE_STATIC_FILES="true" \
    DEBIAN_FRONTEND="noninteractive" \
    RUBY_YJIT_ENABLE="1" \
    PATH="${PATH}:/opt/ruby/bin:/app/bin" \
    MALLOC_CONF="narenas:2,background_thread:true,thp:never,dirty_decay_ms:1000,muzzy_decay_ms:0"

WORKDIR /app

RUN \
    # Mount Apt cache and lib directories from Docker buildx caches
    --mount=type=cache,id=apt-cache-${RAILS_ENV},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib-${RAILS_ENV},target=/var/lib/apt,sharing=locked \
    --mount=type=tmpfs,target=/var/log \
    # Apt update & upgrade to check for security updates to Debian image
    apt-get update && \
    apt-get dist-upgrade -yq && \
    apt-get install -y --no-install-recommends  \
    # Common dependencies/tools
    vim \
    # SQL dependencies
    ca-certificates \
    fuse3 \
    sqlite3 \
    # Install jemalloc
    libjemalloc2 \
    patchelf \
    ; \
    # Patch Ruby to use jemalloc
    patchelf --add-needed libjemalloc.so.2 /usr/local/bin/ruby; \
    # Discard patchelf after use
    apt-get purge -y patchelf;


# Copy built apps
COPY --from=litefs /usr/local/bin/litefs /usr/local/bin/litefs
COPY litefs.yml /etc/litefs.yml
RUN mkdir -p /data/litefs

RUN mkdir /data/litefs<% end %> && \
    chown -R <%= user %> <%= Dir[*%w(db log storage tmp)].join(" ") %> /data<% if using_litefs? %> /litefs<% end %>

COPY --from=tailscale /usr/local/bin/tailscaled /usr/local/bin
COPY --from=tailscale /usr/local/bin/tailscale /usr/local/bin
RUN mkdir -p /var/run/tailscale /var/cache/tailscale /app/.cache /app/.local

COPY --from=op /usr/local/bin/op /usr/local/bin/op
RUN mkdir -p /home/app/.config/op && \
    chown -R "${UID}":"${GID}" /home/app/.config/op && \
    chmod 700 /home/app/.config/op

ONBUILD RUN \
    # Creates app user/group and sets home directory
    groupadd --gid "${GID}" --system app; \
    useradd --uid "${UID}" --gid app --no-create-home --system app;

# Copy app with gems from former build stage
ONBUILD COPY --from=base --chown=app:app /usr/local/bundle/ /usr/local/bundle/
ONBUILD COPY --from=base --chown=app:app /app /app

# Entrypoint sets up the container.
ONBUILD ENTRYPOINT ["/app/bin/docker-entrypoint"]

# Expose default Puma ports
EXPOSE 3000

