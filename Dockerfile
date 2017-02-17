FROM alpine:latest

# Credit to Dominik Hahn <dominik@monostream.com> for the original version of
# this Dockerfile at https://github.com/monostream/docker-rancher-cli/.

# Define rancher version
ENV RANCHER_CLI_VERSION=v0.4.1 \
    YAML_VERSION=1.5 \
    RANCHER_URL= \
    RANCHER_ACCESS_KEY= \
    RANCHER_SECRET_KEY= \
    RANCHER_ENVIRONMENT=

# Install dependencies and rancher
RUN apk add --quiet --no-cache ca-certificates bash && \
	apk add --quiet --no-cache --virtual Dockerfile curl && \
    curl -sSL https://github.com/mikefarah/yaml/releases/download/${YAML_VERSION}/yaml_linux_amd64  > /usr/local/bin/yaml && \
	chmod +x /usr/local/bin/yaml && \
	curl -sSL "https://github.com/rancher/cli/releases/download/${RANCHER_CLI_VERSION}/rancher-linux-amd64-${RANCHER_CLI_VERSION}.tar.gz" | tar -xz -C /usr/local/bin/ --strip-components=2 && \
	chmod +x /usr/local/bin/rancher && \
	apk del Dockerfile && \
	rm -rf /var/cache/*

# Set working directory
WORKDIR /workspace

COPY entrypoint.sh /usr/local/bin/entrypoint

ENTRYPOINT ["entrypoint"]

# Executing defaults
CMD ["help"]
