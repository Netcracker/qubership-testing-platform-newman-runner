FROM node:20-alpine

ENV HOME_EX=/app

RUN echo "https://dl-cdn.alpinelinux.org/alpine/v3.22/community/" >/etc/apk/repositories && \
    echo "https://dl-cdn.alpinelinux.org/alpine/v3.22/main/" >>/etc/apk/repositories && \
    apk update && apk add --no-cache ca-certificates \
      bash=5.2.37-r0 \
      curl=8.14.1-r2 \
      jq=1.8.1-r0 \
      tar=1.35-r3 \
      unzip \
      git \
      file \
      inotify-tools \
      perl \
      nano && \
    rm -rf /var/cache/apk/*

RUN curl -L -o /tmp/s5cmd.tar.gz \
    https://github.com/peak/s5cmd/releases/download/v2.3.0/s5cmd_2.3.0_Linux-64bit.tar.gz && \
    tar -xzf /tmp/s5cmd.tar.gz -C /tmp && \
    mv /tmp/s5cmd /usr/local/bin/ && \
    chmod +x /usr/local/bin/s5cmd && \
    rm -rf /tmp/s5cmd*

RUN addgroup -g 1007 runner && \
    adduser -u 1007 -G runner -D -h "$HOME_EX" runner && \
    mkdir -p "$HOME_EX" && \
    chown -R runner:runner "$HOME_EX"

WORKDIR $HOME_EX

COPY package.json package-lock.json .npmrc ./
RUN npm set strict-ssl=false && \
    npm init -y && \
    npm ci

ENV PATH="/app/node_modules/.bin:${PATH}"
ENV NODE_PATH="/app/node_modules"

COPY --chown=runner:runner --chmod=755 scripts/ /scripts/
COPY --chown=runner:runner --chmod=755 scripts/runtimes/newman-setup.sh /scripts/runtime-setup.sh
COPY --chown=runner:runner --chmod=755 start_tests.sh /start_tests.sh
COPY --chown=runner:runner --chmod=755 entrypoint.sh /app/entrypoint.sh

USER 1007

ENTRYPOINT ["/app/entrypoint.sh"]
