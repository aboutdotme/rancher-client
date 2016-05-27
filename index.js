"use strict"
/**
 * # rancher-client
 *
 * This script helps work with the Rancher API to make running rancher-compose
 * as seamless as possible.
 *
 */
// System
const fs = require('fs')
const spawn = require('child_process').spawn

// 3rd party
const _ = require('lodash')
const opts = require('nomnom')()
const yaml = require('js-yaml')
const async = require('async')
const debug = require('debug')('rancher-client')
const unzip = require('unzip')
const colors = require('colors')
const request = require('request')

// Project
const pkg = require('./package.json')

/**
 * Echos information to the user which is not debug statements.
 */
function info () {
    let args = _.map(_.slice(arguments), (arg) => colors.blue(arg))
    console.log.apply(console.log, args)
}


/**
 * Echos warn messages to the user.
 */
/*
function warn () {
    let args = _.map(_.slice(arguments), (arg) => colors.yellow(arg))
    console.log.apply(console.log, args)
}
*/


/**
 * Echos error messages to the user.
 */
function error () {
    let args = _.map(_.slice(arguments), (arg) => colors.red(arg))
    console.log.apply(console.log, args)
}



opts.scriptName('rancher-client')


opts.option('version', {
    flag: true,
    callback: () => pkg.version
})


opts.option('config', {
    help: "Specify a JSON or YAML configuration to use",
    transform: function loadConfig(filename) {
        debug(`Loading config '${filename}' ...`)
        let config = fs.readFileSync(filename, 'utf8')
        if (_.endsWith(filename, '.yml')) {
            config = yaml.safeLoad(config)
        }
        else if (_.endsWith(filename, '.json')) {
            config = JSON.parse(config)
        }
        else {
            error(`Invalid configuration type: ${filename}`)
            error("Please ensure your configuration is .yml or .json.")
            process.exit(1)
        }
        return config
    }
})


opts.command('upgrade')
    .option('environment', {
        abbr: 'e',
        help: "Specify a environment name",
    })
    .option('stack', {
        abbr: 's',
        help: "Specify a stack name",
    })
    .option('access_key', {
        full: 'access-key',
        help: "Specify Rancher API access key",
    })
    .option('secret_key', {
        full: 'secret-key',
        help: "Specify Rancher API secret key",
    })
    .option('url', {
        help: "Specify the Rancher API endpoint URL",
    })
    .option('services', {
        position: 1,
        list: true,
        required: false,
        help: "Specify the services to upgrade",
    })
    .option('tag', {
        abbr: 't',
        help: "Change the image tag for the given services",
        required: false,
    })
    .option('docker_user', {
        full: 'docker-user',
        abbr: 'u',
        required: false,
        help: "Docker Hub user name"
    })
    .option('docker_pass', {
        full: 'docker-pass',
        abbr: 'p',
        required: false,
        help: "Docker Hub password"
    })
    .option('dry_run', {
        full: 'dry-run',
        abbr: 'd',
        flag: true,
        required: false,
        help: "Don't make any actual changes"
    })
    .callback(upgrade)


function upgrade (args) {
    debug("Upgrading ...")
    let config = makeConfig(args)
    let rancher = new RancherApi(config)
    debug(rancher)
    rancher.upgrade()
}


class RancherApi {
    constructor (config) {
        _.defaults(this, config)
        this.auth = {
            user: this.access_key,
            pass: this.secret_key,
        }
    }

    get request_opts () {
        return {
            json: true,
            auth: this.auth,
        }
    }

    upgrade () {
        async.waterfall([
            // Get the project (environment) data
            (callback) => {
                let url = this.url + '/v1/projects'
                this.getItem('environment', url, callback)
            },
            (project, callback) => {
                // Save the project data back to this instance
                this.project = project

                // Get the environment (stack) data
                let url = this.project.links.environments
                this.getItem('stack', url, callback)
            },
            // Save the environment data back to this instance
            (environment, callback) => {
                this.environment = environment

                // Get our rancher-compose files
                let url = this.environment.links.composeConfig
                debug(url)
                request.get(url, this.request_opts)
                    .pipe(unzip.Parse())
                    .on('error', callback)
                    .on('close', callback)
                    .on('entry', (entry) => {
                        debug(entry.path)
                        entry.pipe(fs.createWriteStream(entry.path))
                    })
            },
            // Get the list of services
            (callback) => {
                let url = this.environment.links.services
                this.getItem('services', url, callback)
            },
            // Save the list of services
            (services, callback) => {
                let available = _.map(services, (val) => val.name)

                // If no services were specified, we want all the services
                if (_.isEmpty(this.services)) {
                    this.services = available
                }

                // Filter out services we don't want
                this.service_list = _.filter(services, (service) => {
                    if (!_.includes(this.services, service.name)) return false
                    return true
                })

                // Check that all the services we specified were found
                let missing = _.filter(this.services, (service) => {
                    if (!_.includes(available, service)) return true
                    return false
                })

                if (!_.isEmpty(missing)) {
                    let err = new Error(`Services not found: ` +
                            `${missing.join(", ")}`)
                    return callback(err)
                }

                debug(available)
                debug(this.services)

                callback()
            },
            // If we have a docker tag update, we update the compose file
            (callback) => {
                if (!this.tag) return callback()
                this.updateComposeTag(this.tag, callback)
            },
            // Abort if we're doing a dry-run
            (callback) => {
                if (this.dry_run) {
                    process.exit(0)
                }
                callback()
            },
            // Pull new images
            (callback) => {
                let cmd = ['pull']
                cmd = _.concat(cmd, this.services)
                this.compose(cmd, callback)
            },
            // Force update all services
            (callback) => {
                let cmd = [
                    'up',
                    '-d',
                    '-c',
                    '--pull',
                    '--upgrade',
                    '--force-upgrade',
                    '--batch-size', '1',
                    '--interval', '2000',
                ]
                cmd = _.concat(cmd, this.services)
                this.compose(cmd, callback)
            },
        ], (err, result) => {
            if (err) {
                error(err)
                process.exit(1)
                return
            }

            info("All done.")
        })
    }

    // Helper to run a rancher-compose command with args
    compose (args, callback) {
        // Build our base params, which are needed for auth, etc.
        let cmd = [
            // `rancher-compose`,
            '--project-name', this.stack,
            '--url', this.url,
            '--access-key', this.access_key,
            '--secret-key', this.secret_key,
        ]
        // Append our supplied args
        cmd = _.concat(cmd, args)

        debug('rancher-compose ' + cmd.join(' '))

        // Call rancher-compose with args
        let child = spawn('rancher-compose', cmd)
        child.stdout.on('data', (buf) => { debug(_.trim(buf.toString())) })
        child.stderr.on('data', (buf) => { debug(_.trim(buf.toString())) })
        child.on('error', () => {
            error("Failed to start rancher-compose.")
            process.exit(1)
        })
        child.on('close', (code) => {
            if (code) {
                let err = new Error(`rancher-compose exited with: ${code}`)
                return callback(err)
            }
            callback()
        })
    }

    // Helper to make simple GET requests to the Rancher API
    apiGet (url, callback) {
        request.get(url, this.request_opts, (err, response, data) => {
            if (err) return callback(err)
            if (response.statusCode !== 200) {
                let err = new Error(`Bad status code: ${response.statusCode}`)
                return callback(err, data)
            }
            callback(null, data)
        })
    }

    // Hit the Rancher API looking for a matching entry in the response list.
    // The response looks a bit like {data: [{name: 'item1'}]} so we search
    // through that for a matching name.
    getItem (type, url, callback) {
        debug(type)
        debug(url)
        this.apiGet(url, (err, data) => {
            if (err) return callback(err, data)
            // We expect a data field which is an array
            if (!_.isArray(data.data)) {
                return callback(new Error("Bad response, missing data " +
                            "array."))
            }

            // Get all our items returned
            let items = data.data
            let match = _.isString(this[type])
            // If we specify a string name (environment, stack), then we filter
            // items looking for a matching name, otherwise we return all
            if (match) {
                items = _.filter(items, (item) => {
                    return item.name === this[type]
                })
            }

            // Make sure we found at least one matching
            if (items.length < 1) {
                return callback(new Error(`Couldn't find matching ${type}`))
            }

            // If we're not doing a match, then return everything
            if (!match) return callback(null, items)

            // If we have just one, we return just the one
            callback(null, items[0])
        })

    }

    // Update the docker-compose file for our services to use `tag`
    updateComposeTag (tag, callback) {
        // Read our docker-compose file
        let compose = fs.readFileSync('docker-compose.yml', 'utf8')
        compose = yaml.safeLoad(compose)

        // List of modified images
        let images = []

        // Update the tags for our services
        _.forEach(this.services, (service) => {
            let image = compose[service].image
            if (!image) {
                debug(`Skipping '${service}', it doesn't use an image.`)
                return
            }
            // Split the image name
            image = image.split(':')

            // Remove the current tag
            if (image.length >= 2) image.pop()

            // Add the new tag
            image.push(tag)

            // Get the full image name
            image = image.join(':')

            // Hang on to it so we can check it
            images.push(image)

            // Save it back to the compose file
            compose[service].image = image
        })

        debug(compose)

        if (!this.docker_user || !this.docker_pass) {
            // No credentials exist, so no check needed for image existence
            // Write the compose file back
            compose = yaml.safeDump(compose)
            fs.writeFileSync('docker-compose.yml', compose)
            return callback()
        }

        // Check if our images exist
        this.dockerLogin((err) => {
            if (err) return callback(err)
            async.filter(images, this.checkImage.bind(this), (err, results) => {
                // If we have anything in the results, then it's an image that
                // doesn't exist
                if (!_.isEmpty(results)) {
                    error(`Missing images: ${results.join(', ')}`)
                    process.exit(1)
                }
                // Write the compose file back
                compose = yaml.safeDump(compose)
                fs.writeFileSync('docker-compose.yml', compose)
                callback()
            })
        })
    }

    dockerLogin(callback) {
        // Don't make a request if we already have the token
        if (this.docker_token) {
            return callback()
        }
        // Build our request options to get a JWT token
        let options = {
            uri: 'https://hub.docker.com/v2/users/login/',
            json: true,
            formData: {
                username: this.docker_user,
                password: this.docker_pass,
            },
        }
        request.post(options, (err, response, body) => {
            if (err) return callback(err)
            if (!body.token) {
                return callback(new Error("JWT token not found in body"))
            }
            this.docker_token = body.token
            debug(`${this.docker_token.slice(0,32)}...`)
            callback()
        })
    }

    checkImage(image, callback) {
        let tag = 'latest'
        image = image.split(':')
        tag = image[1] || tag
        image = image[0]

        if (!this.docker_token) {
            return false
        }

        debug(`Checking ${image}:${tag} ...`)
        async.waterfall([
            // Hit the API to check if our tag exists
            (callback) => {
                let uri = (`https://hub.docker.com/v2/repositories/${image}` +
                    `/tags/${tag}`)
                let options = {
                    uri: uri,
                    json: true,
                    headers: {
                        Authorization: `JWT ${this.docker_token}`,
                    },
                }
                debug(uri)
                request.get(options, callback)
            },
            (response, body, callback) => {
                debug(body)
                // If the tag wasn't found, we get on up
                if (body.detail == 'Not found' || body.name != tag) {
                    return callback(null, true)
                }
                callback(null, false)
            },
        ], (err, result) => {
            if (err) {
                error(err)
                process.exit(1)
            }
            callback(null, result)
        })
    }
}


/**
 * Return a config object based on merging the config file if specified and
 * parameters given.
 */
function makeConfig (args) {
    // Create our base configuation, which is empty
    let config = {}

    // Make sure we're not working with undefined
    args.config = args.config || {}

    // Iterate over the options we have and try to get some
    _.forEach(opts.commands.upgrade.specs, (opt, name) => {
        let val = args[name] || args.config[name] || null
        if (val === null && opt.required !== false) {
            error(`Missing required argument '${opt.full || opt.name}'`)
            process.exit(1)
        }

        if (name === 'services') {
            debug("Parsing services")
            debug(val)
            let services = []
            _.forEach(val, (service) => {
                services.push.apply(services, service.split(','))
            })

            val = services
        }

        config[name] = val
    })

    return config
}


opts.parse()

