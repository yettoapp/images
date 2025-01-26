# syntax = docker/dockerfile:1.11

ARG REGISTRY

FROM ${REGISTRY}yettoapp/base-ruby:main AS language

# Set environment
ONBUILD ARG APP_ENV
ONBUILD ENV RAILS_ENV=${APP_ENV:-development}

ONBUILD ARG GIT_SHA
ONBUILD ENV GIT_SHA=$GIT_SHA

RUN \
    # Mount Apt cache and lib directories from Docker buildx caches
    --mount=type=cache,id=apt-cache-${RAILS_ENV},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib-${RAILS_ENV},target=/var/lib/apt,sharing=locked \
    --mount=type=tmpfs,target=/var/log \
    # Apt update & upgrade to check for security updates to Debian image
    apt-get update && \
    apt-get dist-upgrade -yq && \
    apt-get install -y --no-install-recommends  \
    # SQL dependencies
    libpq-dev;

# Copy app with gems from former build stage
ONBUILD COPY --from=builder --chown=app:app /usr/local/bundle/ /usr/local/bundle/
ONBUILD COPY --from=builder --chown=app:app /app /app

# Entrypoint sets up the container.
ONBUILD ENTRYPOINT ["/app/bin/docker-entrypoint"]

# Expose default Puma ports
EXPOSE 3000

VOLUME /data
