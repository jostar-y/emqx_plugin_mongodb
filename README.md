# emqx_plugin_mongodb

Mongodb plugin for EMQX >= V5.4.0

## Usage

### Release

```shell
> git clone https://github.com/jostar-y/emqx_plugin_mongodb.git
> cd emqx_plugin_mongodb
> make rel
_build/default/emqx_plugrel/emqx_plugin_mongodb-<vsn>.tar.gz
```

### Config

#### Explain

```shell
> cat priv/emqx_plugin_mongodb.hocon
plugin_mongodb {
  // required
  connection {
    // enum: single | sharded | rs
    // required
    mongo_type = single
    
    // Following parameters reference https://docs.emqx.com/zh/enterprise/v5.4/admin/api-docs.html#tag/Bridges/paths/~1bridges/post
    // bridge_mongodb.*
    
    // If mongo type is 'rs', this field required
    replica_set_name = replica_set_name
    // Mongo server address.
    // If  mongo type is 'single', only the first host address is used
    // required
    bootstrap_hosts = ["10.3.64.223:27017", "10.3.64.223:27018", "10.3.64.223:27019"]
    w_mode = unsafe
    // required
    database = "database"
    username = "username"
    password = "password"
    // broker.ssl_client_opts
    ssl {
      enable = false
    }
    topology {
      pool_size = 8
      max_overflow = 0
      local_threshold_ms = 1s
      connect_timeout_ms = 20s
      socket_timeout_ms = 100ms
      server_selection_timeout_ms = 30s
      wait_queue_timeout_ms = 1s
      heartbeat_frequency_ms = 10s
      min_heartbeat_frequency_ms = 1s
    }
    health_check_interval = 32s
  }

  // required
  topics = [
    {
      // Emqx topic pattern.
      // 1. Cannot match the system message;
      // 2. Cannot use filters that start with '+' or '#'.
      filter = "test/#"
      // Unique
      name = emqx_test
      collection = mqtt
    }
  ]
}
```

Some examples in the directory `priv/example/`.

#### Path

- Default path： `emqx/etc/emqx_plugin_mongodb.hocon`
- Attach to path:  set system environment variables  `export EMQX_PLUGIN_MONGODB_CONF="absolute_path"`

#### Reload

```shell
// emqx_ctl
> bin/emqx_ctl emqx_plugin_mongodb
emqx_plugin_mongodb reload # Reload topics
> bin/emqx_ctl emqx_plugin_mongodb reload
topics configuration reload complete.
```

