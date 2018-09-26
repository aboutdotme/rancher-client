FROM alpine:latest

# Credit to Dominik Hahn <dominik@monostream.com> for the original version of
# this Dockerfile at https://github.com/monostream/docker-rancher-cli/.

# Define rancher version
ENV RANCHER_CLI_VERSION=v0.5.0 \
    RANCHER_URL= \
    RANCHER_ACCESS_KEY= \
    RANCHER_SECRET_KEY= \
    RANCHER_ENVIRONMENT=

# Install dependencies and rancher
RUN apk update && \
    apk add --quiet --no-cache ca-certificates bash docker && \
    rm /usr/bin/docker?* && \
	apk add --quiet --no-cache --virtual Dockerfile curl && \
	curl -sSL "https://github.com/rancher/cli/releases/download/${RANCHER_CLI_VERSION}/rancher-linux-amd64-${RANCHER_CLI_VERSION}.tar.gz" | tar -xz -C /usr/local/bin/ --strip-components=2 && \
	chmod +x /usr/local/bin/rancher && \
	apk del Dockerfile && \
	rm -rf /var/cache/*

# Set working directory
WORKDIR /workspace

COPY entrypoint.sh /usr/local/bin/entrypoint
COPY yaml /usr/local/bin/yaml
RUN chmod +x /usr/local/bin/yaml

ENTRYPOINT ["entrypoint"]

# Executing defaults
CMD ["help"]
