#!/bin/bash
export PS1="rancher-${RANCHER_CLI_VERSION} \\$ "

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
        help)
            shift
            _help "$@"
            ;;
        "bash")
            shift
            /bin/bash "$@"
            ;;
        *)
            main help
            ;;
    esac
}


# Show help and exit
_help () {
    echo "Usage: Read the fucking docs."
    exit 0
}


check_env () { 
    if [[ -z "$RANCHER_URL" ]]; then
        echo "Missing required environment variable: RANCHER_URL"
        exit 1
    fi
    if [[ -z "$RANCHER_ACCESS_KEY" ]]; then
        echo "Missing required environment variable: RANCHER_ACCESS_KEY"
        exit 1
    fi
    if [[ -z "$RANCHER_SECRET_KEY" ]]; then
        echo "Missing required environment variable: RANCHER_SECRET_KEY"
        exit 1
    fi
    if [[ -z "$RANCHER_ENVIRONMENT" ]]; then
        echo "Missing required environment variable: RANCHER_ENVIRONMENT"
        exit 1
    fi
}


# Start the main program
main "$@"
