# rancher-client

Rancher API client for containerized deployments and management.  This tool
wraps the rancher cli tool in a Docker image, along with a few other helper
tools so that this can be used as a standalone tool.

Items built into the image:

* bash
* yaml (for parsing docker-compose files)
* curl
* docker (for proxying docker commands through the rancher cli)

### Usage

The rancher-client relies on local credentials to be configured for dockerhub
and rancher.  These credential values can all be passed in via environment
variables or enabld by mounting configurations in as volumes.

#### Running via prebuilt image

If you don't need to log into docker, use:

```bash
docker run -it --rm -v "$HOME/.rancher:/root/.rancher" \
    aboutdotme/rancher-client <command> [options]`
```

If you need private docker credentials, use:


```bash
docker run -it --rm \
    -v "$HOME/.rancher:/root/.rancher" \
    -v "$HOME/.docker:/root/.docker" \
    aboutdotme/rancher-client <command> [options]`
```

This can be aliased for ease of use:

```bash
alias rancher-client="docker run -it --rm -v $HOME/.rancher:/root/.rancher \
    -v $HOME/.docker:/root/.docker aboutdotme/rancher-client"
```

#### Running via checked out repository

To check out the repository and run the commands directly, use:

```bash
git clone https://github.com/aboutdotme/rancher-client
cd rancher-client
docker-compose build
```

To enable rancher environment variables, uncomment the following lines in the
`docker-compose.yml` file and update them to reflect your environment.

```
    #   RANCHER_URL: ''
    #   RANCHER_ACCESS_KEY: ''
    #   RANCHER_SECRET_KEY: ''
    #   RANCHER_ENVIRONMENT: ''
```

To enable local credentials, uncomment the following lines in the
`docker-compose.yml` file.

```
    # volumes:
    #   - ./entrypoint.sh:/usr/local/bin/entrypoint
    #   - ~/.rancher/cli.json:/root/.rancher/cli.json
    #   - ~/.docker/config.json:/root/.docker/config.json
```

NOTE: If you don't mount in the docker credential file you will not be able to
pull any private Docker images.  You will have to login to the container and
configure the credentials to work around this issue.

To run the rancher-client:

`docker-compose run --rm rancher_client <command> [options]`

To make working with the Docker image easier you can create an alias:

```
alias rancher-client="docker-compose run --rm rancher_client"
```

Make sure you run the alias from the `rancher-cli` repo.

## Commands

The default `entrypoint.sh` script contains the following CLI commands.

#### upgrade

Used to upgrade services. Services must be in an "active" state to be ugpraded.

Usage:

`rancher-client upgrade [confirm] <environment> <stack> <tag> <service> [service...]`

#### rollback

Used to rollback services. Services must be in an "upgraded" state to be rolled
back. If a service has already finish the upgrade, then use ugprade again to
change the image tag.

`rancher-client upgrade [confirm] <environment> <stack> <service> [service...]`

#### rancher

Passthrough command to the rancher cli.

`rancher-client rancher`

#### test

Used to run container test suite.  Currently unused.

`rancher-client test`

#### bash

Passthrough to bash prompt.  Useful for debugging, etc.

`rancher-client bash`

#### help

Print CLI help.

```bash
$ rancher-client help
Usage: entrypoint.sh <upgrade|rollback|rancher|test|help|bash> [options]

    upgrade     Upgrade a service to a new image tag
    rollback    Roll back a service in an upgraded state
    rancher     Run commands directly using the Rancher CLI
    help        Display this help

    bash        Drop into a bash shell
    test        Run the test suite

Read the docs at https://github.com/aboutdotme/rancher-client/ for more details.
```

