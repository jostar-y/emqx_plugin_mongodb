-module(emqx_plugin_mongodb_connector).

-behaviour(emqx_resource).

-include_lib("emqx_resource/include/emqx_resource.hrl").
-include_lib("emqx/include/logger.hrl").

-export([
    query_mode/1
    , callback_mode/0
    , on_start/2
    , on_get_status/2
    , on_stop/2
    , on_query_async/4
]).

query_mode(_) ->
    simple_async_internal_buffer.

callback_mode() ->
    async_if_possible.

on_start(
    _InstId,
    Connection
) ->
    Type = init_mongo_type(Connection),
    Hosts = init_hosts(Connection),

    Topology = maps:get(topology, Connection, #{}),
    TopologyOptions = init_topology_options(maps:to_list(Topology), []),

    SslOpts =
        case maps:get(ssl, Connection, nil) of
            #{enable := false} ->
                [{ssl, false}];
            SSL ->
                [
                    {ssl, true},
                    {ssl_opts, emqx_tls_lib:to_client_opts(SSL)}
                ]
        end,
    WorkerOptions = init_worker_options(maps:to_list(Connection), SslOpts),
    {ok, Pid} = ensure_client(Type, Hosts, TopologyOptions, WorkerOptions),
    {ok, #{
        topology_pid => Pid
    }}.

on_get_status(
    _InstId,
    #{topology_pid := Pid} = State
) ->
    case check_topology_connectivity(Pid) of
        ok ->
            ?status_connected;
        {error, Error} ->
            {?status_disconnected, State, Error}
    end.

on_stop(_InstId, #{topology_pid := Pid}) ->
    ?SLOG(info, #{
        msg => "mongodb_client_on_stop",
        topology_pid => Pid
    }),
    deallocate_client(Pid),
    ok.

on_query_async(
    InstId,
    {Querys, Message},
    _,
    #{topology_pid := Pid} = _ConnectorState
) ->
    try
        do_send_msg(Pid, Querys, Message)
    catch
        Error:Reason:Stack ->
            ?SLOG(error, #{
                msg => "emqx_plugin_mongodb_producer on_query_async error",
                error => Error,
                instId => InstId,
                reason => Reason,
                stack => Stack
            }),
            {error, {Error, Reason}}
    end.

ensure_client(Type, Hosts, TopologyOptions, WorkerOptions) ->
    case mongo_api:connect(Type, Hosts, TopologyOptions, WorkerOptions) of
        {ok, Pid} ->
            {ok, Pid};
        {error, {already_started, Pid}} ->
            deallocate_client(Pid),
            ensure_client(Type, Hosts, TopologyOptions, WorkerOptions);
        {error, Reason} ->
            ?SLOG(error, #{
                msg => failed_to_start_mongodb_client,
                mongodb_type => Type,
                mongodb_hosts => Hosts,
                reason => Reason
            }),
            {error, Reason}
    end.

init_mongo_type(#{mongo_type := single}) ->
    single;
init_mongo_type(#{mongo_type := sharded}) ->
    sharded;
init_mongo_type(#{mongo_type := rs, replica_set_name := Name}) ->
    {rs, Name}.

init_hosts(#{bootstrap_hosts := Hosts}) ->
    hosts(Hosts).

init_topology_options([{pool_size, Val} | T], Acc) ->
    init_topology_options(T, [{pool_size, Val} | Acc]);
init_topology_options([{max_overflow, Val} | T], Acc) ->
    init_topology_options(T, [{max_overflow, Val} | Acc]);
init_topology_options([{local_threshold_ms, Val} | T], Acc) ->
    init_topology_options(T, [{localThresholdMS, Val} | Acc]);
init_topology_options([{connect_timeout_ms, Val} | T], Acc) ->
    init_topology_options(T, [{connectTimeoutMS, Val} | Acc]);
init_topology_options([{socket_timeout_ms, Val} | T], Acc) ->
    init_topology_options(T, [{socketTimeoutMS, Val} | Acc]);
init_topology_options([{server_selection_timeout_ms, Val} | T], Acc) ->
    init_topology_options(T, [{serverSelectionTimeoutMS, Val} | Acc]);
init_topology_options([{wait_queue_timeout_ms, Val} | T], Acc) ->
    init_topology_options(T, [{waitQueueTimeoutMS, Val} | Acc]);
init_topology_options([{heartbeat_frequency_ms, Val} | T], Acc) ->
    init_topology_options(T, [{heartbeatFrequencyMS, Val} | Acc]);
init_topology_options([{min_heartbeat_frequency_ms, Val} | T], Acc) ->
    init_topology_options(T, [{minHeartbeatFrequencyMS, Val} | Acc]);
init_topology_options([_ | T], Acc) ->
    init_topology_options(T, Acc);
init_topology_options([], Acc) ->
    Acc.

init_worker_options([{database, V} | R], Acc) ->
    init_worker_options(R, [{database, V} | Acc]);
init_worker_options([{username, V} | R], Acc) ->
    init_worker_options(R, [{login, V} | Acc]);
init_worker_options([{password, Secret} | R], Acc) ->
    init_worker_options(R, [{password, Secret} | Acc]);
init_worker_options([{w_mode, V} | R], Acc) ->
    init_worker_options(R, [{w_mode, V} | Acc]);
init_worker_options([_ | R], Acc) ->
    init_worker_options(R, Acc);
init_worker_options([], Acc) ->
    Acc.

hosts(Hosts) ->
    lists:map(
        fun(#{hostname := Host, port := Port}) ->
            iolist_to_binary([Host, ":", integer_to_list(Port)])
        end,
        emqx_schema:parse_servers(Hosts, #{default_port => 27017})
    ).

check_topology_connectivity(Pid) ->
    try mongo_api:find_one(Pid, <<"foo">>, #{}, #{}, 0) of
        {error, Reason} ->
            ?SLOG(warning, #{
                msg => "mongo_connection_get_status_error",
                reason => Reason
            }),
            {error, Reason};
        _ ->
            ok
    catch
        Class:Error ->
            ?SLOG(warning, #{
                msg => "mongo_connection_get_status_exception",
                class => Class,
                error => Error
            }),
            {error, {Class, Error}}
    end.

deallocate_client(Pid) ->
    _ = with_log_at_error(
        fun() -> mongo_api:disconnect(Pid) end,
        #{
            msg => "failed_to_delete_mongodb_client",
            topology_pid => Pid
        }
    ),
    ok.

with_log_at_error(Fun, Log) ->
    try
        Fun()
    catch
        C:E ->
            ?SLOG(error, Log#{
                exception => C,
                reason => E
            })
    end.

do_send_msg(Pid, Querys, Message) ->
    lists:foreach(
        fun({_, Collection}) ->
            mongo_api:insert(Pid, Collection, Message)
        end,
        Querys
    ).