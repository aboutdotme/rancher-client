#!/bin/bash

# Handles the subcommands for this container
main () {
    case $1 in
        upgrade)
            shift
            check_env
            upgrade "$@"
            ;;
        rollback)
            shift
            check_env
            rollback "$@"
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
            _bash "$@"
            ;;
        *)
            # Default to displaying our help
            _help
            ;;
    esac
}


###################
# Command functions
###################


# Runs a service upgrade command with helpers
upgrade () {
    local cmd
    local confirm_upgrade
    local docker_image
    local docker_tag
    local environment
    local host
    local output
    local services
    local stack

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

    # Get our environment
    get_environment "$1"
    environment="$RANCHER_ENVIRONMENT"
    shift

    # Get our stack
    get_stack "$1"
    stack="$RANCHER_STACK"
    shift

    # Get our tag
    check_arg "$1"
    docker_tag=$1
    shift

    # Get our service list
    get_services "$*"
    services="$RANCHER_SERVICES"

    # Make sure the services are all in an active state
    check_service_states active "$services"

    # Get the Rancher *-compose files
    get_config "$stack"

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

    docker_image=""

    # debug "$(cat docker-compose.yml)"

    # Iterate services and check for the image tag existing by pulling to a
    # Rancher host
    for service in $services; do
        check_arg "$service"
        # debug "Checking $service"

        cmd="yaml r docker-compose.yml services.$service.image"
        output=$($cmd)
        debug "$output"

        if [[ "$output" == "null" ]]; then
            error "Service not found: $service"
        fi

        # Modify the image with the new tag
        local image
        image=${output%%:*}
        image="$image:$docker_tag"
        docker_image+=" $image"

        # Write the new image to the compose yaml
        debug "Writing $image to docker-compose.yml"
        yaml w -i docker-compose.yml "services.$service.image" "$image"

        info "Pulling $image"

        # This command requires docker login inside the container
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
            success "${pids[$pid]}: Image verified"
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

    info "Upgrading $services"
    if [[ -n "$confirm_upgrade" ]]; then
        info "   ... and automatically finishing upgrade"
    fi
    # shellcheck disable=SC2086
    rancher up -d --pull --upgrade --force-upgrade $confirm_upgrade \
        --stack "$stack" $services

    if [[ $? -ne 0 ]]; then
        error "Upgrade failed"
    fi

    success "Upgrade successful"
    exit 0
}


rollback () {
    local environment
    local services
    local stack

    info "Rolling back $*"

    # Get our environment
    get_environment "$1"
    environment="$RANCHER_ENVIRONMENT"
    shift

    # Get our stack
    get_stack "$1"
    stack="$RANCHER_STACK"
    shift

    # Get the remaining arguments as service names
    check_arg "$1"
    services=$*

    # Make sure that we have services specified
    if [[ -z "$services" ]]; then
        error "Missing required argument: services"
    fi

    # Make sure the services are all in an active state
    check_service_states upgraded "$services"

    # Get the Rancher *-compose files
    get_config "$stack"

    info "Rolling back $stack/$services"

    # shellcheck disable=SC2086
    rancher up -d --rollback --stack "$stack" $services

    if [[ $? -ne 0 ]]; then
        error "Rollback failed"
    fi

    success "Rollback successful"
    exit 0
}


_bash () {
    # Create a useful bash prompt when we get into the container
    debug "Setting PS1 for bash shell"
    export PS1="rancher-${RANCHER_CLI_VERSION} \\$ "

    # Symlink in the development version of the entrypoint script if it exists
    if [[ -f "/usr/local/src/rancher-client/entrypoint.sh" ]]; then
        debug "Mounting development entrypoint script"
        ln -sf /usr/local/src/rancher-client/entrypoint.sh \
            /usr/local/bin/entrypoint
    fi

    debug "Launching bash shell"
    /bin/bash "$@"
}


# Run tests on this container
_test () {
    echo "> $(green "0 tests passed")"
    exit 0
}


# Show help and exit
_help () {
    # TODO: Individual command help

    cat << EOF
Usage: entrypoint.sh <upgrade|rollback|rancher|test|help|bash> [options]"

    upgrade     Upgrade a service to a new image tag
    rollback    Roll back a service in an upgraded state
    rancher     Run commands directly using the Rancher CLI
    help        Display this help

    bash        Drop into a bash shell
    test        Run the test suite

Read the docs at https://github.com/aboutdotme/rancher-client/ for more details.
EOF
    exit 0
}


##################
# Helper functions
##################


# Helper function to confirm that the Rancher CLI will have the information it
# needs to connect to a Rancher server and do things
check_env () {
    # Check for docker authentication
    debug "$(cat "$HOME/.docker/config.json" 2>/dev/null)"
    if [[ ! -f "$HOME/.docker/config.json" ]]; then
        error "Missing docker login"
    fi

    # Check if we have a cli.json mounted into the container
    debug "$(cat "$HOME/.rancher/cli.json" 2>/dev/null)"
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
    # if [[ -z "$RANCHER_ENVIRONMENT" ]]; then
    #     error "Missing required environment variable: RANCHER_ENVIRONMENT"
    # fi
}


# Make sure an argument is not a --param instead
check_arg () {
    local arg=${1:-}

    if [[ ${arg:0:1} == "-" ]]; then
        error "Invalid argument: $arg"
    fi
}


# Get the environment from the passed args
get_environment () {
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

    # Set the environment
    # shellcheck disable=SC2034
    RANCHER_ENVIRONMENT="$environment"
}


get_stack () {
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

    # Set the stack
    # shellcheck disable=SC2034
    RANCHER_STACK="$stack"
}


check_service_states () {
    local services
    local stack
    local state

    # Get our state from args
    state="$1"
    shift

    # Get our services from args
    services="$*"

    if [[ -z "$RANCHER_STACK" ]]; then
        error "Rancher stack name not set"
    fi

    stack="$RANCHER_STACK"

    debug
    debug "Service states:"
    # Iterate services and make sure that all of them are in an upgraded state
    for service in $services; do
        output=$(rancher inspect --format '{{.state}}' "$stack/$service")
        debug "$service: $output"
        if [[ "$output" != "$state" ]]; then
            error "$stack/$service is not '$state' state, got '$output'"
        fi
    done

}


get_services () {
    local services

    # All these args should be services
    services="$*"

    # Make sure that we have services specified
    if [[ -z "$services" ]]; then
        error "Missing required argument: services"
    fi

    # Make sure someone didn't try to pass a param as a service
    for service in $services; do
        check_arg "$service"
    done

    export RANCHER_SERVICES="$services"
}


get_config () {
    local stack
    stack="$1"

    # Pull the Rancher config from the API
    info "Retrieving Rancher configuration"
    rancher export "$stack"
    if [[ $? -ne 0 ]]; then
        error "Rancher export failed"
    fi

    # Move the config files into the current directory
    mv "$stack"/* .
    rmdir "$stack"
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


# Debug output
debug () {
    # Only output if we have the debug environment variable set
    if [[ -z "$DEBUG" ]]; then return; fi

    cyan "${*:-}"
    echo
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
