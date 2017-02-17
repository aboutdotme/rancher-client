#!/bin/bash

# Handles the subcommands for this container
main () {
    case $1 in
        upgrade)
            shift
            check_env
            upgrade "$@"
            ;;
        rancher)
            shift
            check_env
            rancher "$@"
            ;;
        test)
            shift
            _test "$@"
            ;;
        help)
            shift
            _help "$@"
            ;;
        "bash")
            shift
            # Create a useful bash prompt when we get into the container
            export PS1="rancher-${RANCHER_CLI_VERSION} \\$ "
            /bin/bash "$@"
            ;;
        *)
            # Default to displaying our help
            _help
            ;;
    esac
}


# Helper function to confirm that the Rancher CLI will have the information it
# needs to connect to a Rancher server and do things
check_env () {
    if [[ ! -f "$HOME/.docker/config.json" ]]; then
        error "Missing docker login"
    fi

    # Check if we have a cli.json mounted into the container
    if [[ -f "$HOME/.rancher/cli.json" ]]; then return; fi

    # Otherwise check we have all the environment variables we need
    if [[ -z "$RANCHER_URL" ]]; then
        error "Missing required environment variable: RANCHER_URL"
    fi
    if [[ -z "$RANCHER_ACCESS_KEY" ]]; then
        error "Missing required environment variable: RANCHER_ACCESS_KEY"
    fi
    if [[ -z "$RANCHER_SECRET_KEY" ]]; then
        error "Missing required environment variable: RANCHER_SECRET_KEY"
    fi
    if [[ -z "$RANCHER_ENVIRONMENT" ]]; then
        error "Missing required environment variable: RANCHER_ENVIRONMENT"
    fi
}


# Runs a service upgrade command with helpers
upgrade () {
    local RANCHER_ENVIRONMENT
    local confirm_upgrade
    local docker_image
    local docker_tag
    local environment
    local host
    local services
    local stack
    local output

    info "Upgrading $* ..."

    # Command argument format
    # upgrade [confirm] <environment> <stack> <tag> <service> [service...]
    # upgrade --confirm-upgrade Staging Emu master client me-node-api
    # upgrade Staging Emu master client me-node-api

    # Check for the "--confirm" flag for automatically finishing the upgrade
    confirm_upgrade=$1
    if [[ "$confirm_upgrade" == "--confirm-upgrade" ]]; then
        shift
    else
        confirm_upgrade=""
    fi

    # Check that we have all the arguments we need
    check_arg "$1"
    environment=$1
    shift

    # Check if this environment is real
    output=$(rancher environment ls --format "{{.Environment.Name}}")
    debug
    debug "Environments found:"
    debug "$output"
    if ! (echo "$output" | grep "^${environment}$" &>/dev/null); then
        error "Environment not found: $environment"
    fi

    # Set the environment for the rest of the commands
    RANCHER_ENVIRONMENT="$environment"

    check_arg "$1"
    stack=$1
    shift

    # Check if the stack is real
    output=$(rancher stacks ls --format "{{.Stack.Name}}")
    debug
    debug "Stacks found:"
    debug "$output"

    if ! (echo "$output" | grep "^${stack}$" &>/dev/null); then
        error "Stack not found: $environment/$stack"
    fi

    check_arg "$1"
    docker_tag=$1
    shift

    # Pull the Rancher config from the API
    info "Retrieving Rancher configuration"
    rancher export "$stack"
    if [[ $? -ne 0 ]]; then
        error "Rancher export failed"
    fi

    # Move the config files into the current directory
    mv "$stack"/* .
    rmdir "$stack"

    # Find a host
    host=$(rancher host -q | head -1)
    debug
    debug "Host ID: $host"
    if [[ -z "$host" ]]; then
        error "Host not found"
    fi

    # local pids
    # pids="" # For storing backgrounded process pids
    declare -A pids

    services=$*
    docker_image=""
    for service in $services; do
        check_arg "$service"
        debug "Checking $service"
        debug "$(cat docker-compose.yml)"

        output=$(yaml r docker-compose.yml "services.$service.image")
        debug "$output"

        local image
        image=${output%%:*}
        image="$image:$docker_tag"
        docker_image+=" $image"

        # Write the new image to the compose yaml
        debug "Writing $image to docker-compose.yml"
        yaml w -i docker-compose.yml "services.$service.image" "$image"

        info "Pulling $image"

        # TODO: Figure out credential mounting, or whatever, 'cause this
        # command won't work otherwise
        local cmd
        cmd="rancher --host $host docker pull $image"

        # Handle backgrounded or inline output appropriately
        if [[ -n "$DEBUG" ]]; then
            # Run inline with full output
            if $cmd; then
                success "$image: Image verified"
            else
                error "$image: Image error"
            fi
        else
            # Background and suppress output
            $cmd &>/dev/null &
            pids[$!]="$image"
        fi
    done

    # Wait on backgrounded pull processes
    for pid in "${!pids[@]}"; do
        if wait "$pid"; then
            success "${pids[$pid]}: Image verified to exist"
        else
            error "${pids[$pid]}: Image error"
        fi
    done

    debug
    debug "Settings found:"
    debug "$(cat <<EOF
environment="$environment"
stack="$stack"
docker_image="$docker_image"
docker_tag="$docker_tag"
services="$services"
confirm_upgrade="$confirm_upgrade"
EOF
)"
    # TODO don't deploy if service it is in an upgraded state

    info "Upgrading $services"
    if [[ -n "$confirm_upgrade" ]]; then
        info "   ... and automatically finishing upgrade"
    fi
    # shellcheck disable=SC2086
    rancher up -d --pull --upgrade --force-upgrade $confirm_upgrade --stack "$stack" $services

    exit 0
}


# Make sure an argument is not a --param instead
check_arg () {
    local arg=${1:-}

    if [[ ${arg:0:1} == "-" ]]; then
        error "Invalid argument: $arg"
    fi
}


# Display informative things
info () {
    blue "${1:-}"
    echo
}


# Display informative things
success () {
    drk_green "${1:-}"
    echo
}


# Display an angry error message then give up and quit like a baby
error () {
    red "${1:-}"
    echo
    exit 1
}


debug () {
    # Only output if we have the debug environment variable set
    if [[ -z "$DEBUG" ]]; then return; fi

    cyan "${*:-}"
    echo
}


# Run tests on this container
_test () {
    echo "> $(green "0 tests passed")"
    exit 0
}


# Show help and exit
_help () {
    echo "Usage: Read the fucking docs."
    exit 0
}


# Colors
red () { printf "\033[1;31m%s\033[0m" "$*"; }
pink () { printf "\033[1;35m%s\033[0m" "$*"; }
blue () { printf "\033[1;34m%s\033[0m" "$*"; }
green () { printf "\033[1;32m%s\033[0m" "$*"; }
drk_green () { printf "\033[0;32m%s\033[0m" "$*"; }
cyan () { printf "\033[0;36m%s\033[0m" "$*"; }


# Start the main program
main "$@"
