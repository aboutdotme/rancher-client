node {
    service = 'rancher_client'
    build.init {}

    stage 'Build'
    compose.build {}

    stage 'Push'
    compose.tag { tag = 'aboutdotme/rancher-client' }
    build.push {}
}

