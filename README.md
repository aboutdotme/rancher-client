# rancher-client

Rancher API client for containerized administration.

```
Usage: rancher-client upgrade [services]... [options]

services     Specify the services to upgrade

Options:
   --version
   --config            Specify a JSON or YAML configuration to use
   -e, --environment   Specify a environment name
   -s, --stack         Specify a stack name
   --access-key        Specify Rancher API access key
   --secret-key        Specify Rancher API secret key
   --url               Specify the Rancher API endpoint URL
   -t, --tag           Change the image tag for the given services
```

##### Example Commands

Upgrade using a rancher.yml configuration file (as below):

`$ docker run -it --rm -v "$(pwd)/rancher.yml:/usr/src/app/rancher.yml" aboutdotme/rancher-client upgrade --config rancher.yml`

Upgrade with DEBUG output, using a configuration file:

`$ docker run -it --rm -v "$(pwd)/rancher.yml:/usr/src/app/rancher.yml" -e DEBUG=* aboutdotme/rancher-client upgrade --config rancher.yml`

Upgrade with command line options:

```bash
$ docker run -it --rm aboutdotme/rancher-client upgrade \
    --environment Demo \
    --stack Test \
    --access-key FFFFFFFFFFFFFFFFFFFF \
    --secret-key FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF \
    --url https://rancher.domain \
    --tag latest \
    Service1 \
    Service2
```

##### Example Configuration Files

**YAML**

```yaml
environment: Demo
stack: Test
access_key: FFFFFFFFFFFFFFFFFFFF
secret_key: FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
url: 'https://rancher.domain'
tag: latest
services:
  - Service1
  - Service2
```

**JSON**
```json
{
  "environment": "Demo",
  "stack": "Test",
  "access_key": "FFFFFFFFFFFFFFFFFFFF",
  "secret_key": "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
  "url": "https://rancher.domain",
  "tag": "latest",
  "services": ["Service1", "Service2"]
}
```
