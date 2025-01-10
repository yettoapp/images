# repeated below, because Docker
ARG REDIS_VERSION_MAJOR=7
ARG DEBIAN_VERSION="bookworm"

FROM redis:${REDIS_VERSION_MAJOR}-${DEBIAN_VERSION}

# Apply timezone
ENV TZ="Etc/UTC"
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

CMD [ "redis-server"]

EXPOSE 6379
