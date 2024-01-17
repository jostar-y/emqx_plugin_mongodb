-module(emqx_plugin_mongodb_schema).

-include_lib("hocon/include/hoconsc.hrl").

-export([
    roots/0
    , fields/1
    , desc/1
]).

-import(hoconsc, [enum/1]).

roots() -> [plugin_mongodb].

fields(plugin_mongodb) ->
    [
        {connection, ?HOCON(?R_REF(connection), #{desc => ?DESC("connect_timeout")})},
        {topics, ?HOCON(?ARRAY(?R_REF(topic)),
            #{
                required => true,
                default => [],
                desc => ?DESC("topics")
            })}
    ];
fields(connection) ->
    [
        {mongo_type, ?HOCON(enum([single, sharded, rs]),
            #{
                desc => ?DESC("mongo_type"),
                default => "single"
            })},
        {replica_set_name, ?HOCON(binary(),
            #{
                desc => ?DESC("replica_set_name")
            })},
        {bootstrap_hosts, bootstrap_hosts()},
        {w_mode, ?HOCON(enum([unsafe, safe]),
            #{
                desc => ?DESC("w_mode"),
                default => unsafe
            })},
        {database, ?HOCON(binary(),
            #{
                required => true,
                desc => ?DESC("database")
            })},
        {username, ?HOCON(binary(),
            #{
                desc => ?DESC("username")
            })},
        {password, emqx_connector_schema_lib:password_field()},
        {ssl, ?HOCON(?R_REF(ssl),
            #{
                desc => ?DESC("ssl")
            }
        )},
        {topology, ?HOCON(?R_REF(topology),
            #{
                desc => ?DESC("topology")
            }
        )},
        {health_check_interval, ?HOCON(emqx_schema:timeout_duration_ms(),
            #{
                default => <<"32s">>,
                desc => ?DESC("health_check_interval")
            }
        )}
    ];
fields(ssl) ->
    Schema = emqx_schema:client_ssl_opts_schema(#{}),
    lists:keydelete("user_lookup_fun", 1, Schema);
fields(topology) ->
    [
        {pool_size, ?HOCON(pos_integer(),
            #{
                desc => ?DESC("pool_size"),
                default => 8
            })},
        {max_overflow, ?HOCON(non_neg_integer(),
            #{
                desc => ?DESC("max_overflow"),
                default => 0
            })},
        {local_threshold_ms, ?HOCON(emqx_schema:timeout_duration_ms(),
            #{
                desc => ?DESC("local_threshold_ms")
            })},
        {connect_timeout_ms, ?HOCON(emqx_schema:timeout_duration_ms(),
            #{
                desc => ?DESC("connect_timeout_ms")
            })},
        {socket_timeout_ms, ?HOCON(emqx_schema:timeout_duration_ms(),
            #{
                desc => ?DESC("socket_timeout_ms")
            })},
        {server_selection_timeout_ms, ?HOCON(emqx_schema:timeout_duration_ms(),
            #{
                desc => ?DESC("server_selection_timeout_ms")
            })},
        {wait_queue_timeout_ms, ?HOCON(emqx_schema:timeout_duration_ms(),
            #{
                desc => ?DESC("wait_queue_timeout_ms")
            })},
        {heartbeat_frequency_ms, ?HOCON(emqx_schema:timeout_duration_ms(),
            #{
                desc => ?DESC("heartbeat_frequency_ms")
            })},
        {min_heartbeat_frequency_ms, ?HOCON(emqx_schema:timeout_duration_ms(),
            #{
                desc => ?DESC("min_heartbeat_frequency_ms")
            })}
    ];
fields(topic) ->
    [
        {filter, ?HOCON(binary(),
            #{
                desc => ?DESC("topic_filter"),
                default => <<"test/#">>
            })},
        {name, ?HOCON(string(),
            #{
                desc => ?DESC("topic_name"),
                default => "emqx_test"
            })},
        {collection, ?HOCON(binary(),
            #{
                desc => ?DESC("topic_collection"),
                default => <<"mqtt">>
            }
        )}
    ].

desc(_) ->
    undefined.

bootstrap_hosts() ->
    Meta = #{desc => ?DESC("bootstrap_hosts")},
    emqx_schema:servers_sc(Meta, #{default_port => 27017}).