FROM node:onbuild

ENV COMPOSE_VERSION=v0.7.4
RUN curl -s https://releases.rancher.com/compose/$COMPOSE_VERSION/rancher-compose-linux-amd64-$COMPOSE_VERSION.tar.gz \
    | tar -xzf - -C /usr/local/bin --strip-components=2

ENTRYPOINT ["/usr/local/bin/node", "/usr/src/app/index.js"]

