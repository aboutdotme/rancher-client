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
  - Test
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
  "services": ["Test"]
}
```

