# what is this ?

a command line tool to manage SmartOS hosts.


# Prerequisites

- you have an ssh key
- your ssh public key is in authorized_keys on the server to allow passwordless login


# Usage

first you need to create a config file to define your environment:

```toml
# show custom properties in the list
[user_columns]
  some_property = "customer_metadata.some_property"

[global]
  # gateway_user = "root"
  gateway = "x.x.x.x"

[vmhost1]
  # user = "root"
  # gateway = "a.b.c.d"
  # gateway_user = "root"
  address = "y.y.y.y"

[vmhost2]
  # user = "root"
  # gateway = "a.b.c.d"
  # gateway_user = "root"
  address = "z.z.z.z"

```

All options except address (which makes no sense) can be defined in a global section, if present a host section this one will be used, otherwise the global one will be used.

Once you have your file you can use the smanager command:

```bash
$ smanager list
```

