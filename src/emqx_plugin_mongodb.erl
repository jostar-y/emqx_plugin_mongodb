-module(emqx_plugin_mongodb).

-include_lib("emqx/include/emqx.hrl").
-include_lib("emqx/include/emqx_hooks.hrl").
-include_lib("emqx/include/logger.hrl").
-include("emqx_plugin_mongodb.hrl").

-export([
    load/0
    , unload/0
    , reload/0
]).

-export([on_message_publish/1]).

-export([eventmsg_publish/1]).

load() ->
    _ = ets:new(?PLUGIN_MONGODB_TAB, [named_table, public, set, {keypos, 1}, {read_concurrency, true}]),
    load(read_config()).

load(#{connection := Connection, topics := Topics}) ->
    {ok, _} = start_resource(Connection),
    topic_parse(Topics),
    hook('message.publish', {?MODULE, on_message_publish, []});
load(_) ->
    {error, "config_error"}.

on_message_publish(Message = #message{topic = <<"$SYS/", _/binary>>}) ->
    {ok, Message};
on_message_publish(Message) ->
    case select(Message) of
        {true, Querys} when Querys =/= [] ->
            query(?MODULE:eventmsg_publish(Message), Querys);
        false ->
            ok
    end,
    {ok, Message}.

unload() ->
    unhook('message.publish', {?MODULE, on_message_publish}),
    emqx_resource:remove_local(?PLUGIN_MONGODB_RESOURCE_ID).

hook(HookPoint, MFA) ->
    emqx_hooks:add(HookPoint, MFA, _Property = ?HP_HIGHEST).

unhook(HookPoint, MFA) ->
    emqx_hooks:del(HookPoint, MFA).

reload() ->
    ets:delete_all_objects(?PLUGIN_MONGODB_TAB),
    reload(read_config()).

reload(#{topics := Topics}) ->
    topic_parse(Topics).

read_config() ->
    case hocon:load(mongodb_config_file()) of
        {ok, RawConf} ->
            case emqx_config:check_config(emqx_plugin_mongodb_schema, RawConf) of
                {_, #{plugin_mongodb := Conf}} ->
                    ?SLOG(info, #{
                        msg => "emqx_plugin_mongodb config",
                        config => Conf
                    }),
                    Conf;
                _ ->
                    ?SLOG(error, #{
                        msg => "bad_hocon_file",
                        file => mongodb_config_file()
                    }),
                    {error, bad_hocon_file}

            end;
        {error, Error} ->
            ?SLOG(error, #{
                msg => "bad_hocon_file",
                file => mongodb_config_file(),
                reason => Error
            }),
            {error, bad_hocon_file}
    end.

mongodb_config_file() ->
    Env = os:getenv("EMQX_PLUGIN_MONGODB_CONF"),
    case Env =:= "" orelse Env =:= false of
        true -> "etc/emqx_plugin_mongodb.hocon";
        false -> Env
    end.

start_resource(Connection = #{health_check_interval := HealthCheckInterval}) ->
    ResId = ?PLUGIN_MONGODB_RESOURCE_ID,
    ok = emqx_resource:create_metrics(ResId),
    Result = emqx_resource:create_local(
        ResId,
        ?PLUGIN_MONGODB_RESOURCE_GROUP,
        emqx_plugin_mongodb_connector,
        Connection,
        #{health_check_interval => HealthCheckInterval}),
    start_resource_if_enabled(Result).

start_resource_if_enabled({ok, _Result = #{error := undefined, id := ResId}}) ->
    {ok, ResId};
start_resource_if_enabled({ok, #{error := Error, id := ResId}}) ->
    ?SLOG(error, #{
        msg => "start resource error",
        error => Error,
        resource_id => ResId
    }),
    emqx_resource:stop(ResId),
    error.

query(EvtMsg, Querys) ->
    query_ret(
        emqx_resource:query(?PLUGIN_MONGODB_RESOURCE_ID, {Querys, EvtMsg}),
        EvtMsg,
        Querys
    ).

query_ret({_, ok}, _, _) ->
    ok;
query_ret(Ret, EvtMsg, Querys) ->
    ?SLOG(error,
        #{
            msg => "failed_to_query_mongodb_resource",
            ret => Ret,
            evt_msg => EvtMsg,
            querys => Querys
        }).

eventmsg_publish(
    Message = #message{
        id = Id,
        from = ClientId,
        qos = QoS,
        flags = Flags,
        topic = Topic,
        payload = Payload,
        timestamp = Timestamp
    }
) ->
    with_basic_columns(
        'message.publish',
        #{
            id => emqx_guid:to_hexstr(Id),
            clientid => ClientId,
            username => emqx_message:get_header(username, Message, undefined),
            payload => Payload,
            peerhost => ntoa(emqx_message:get_header(peerhost, Message, undefined)),
            topic => Topic,
            qos => QoS,
            flags => Flags,
            pub_props => printable_maps(emqx_message:get_header(properties, Message, #{})),
            publish_received_at => Timestamp
        }
    ).

with_basic_columns(EventName, Columns) when is_map(Columns) ->
    Columns#{
        event => EventName,
        timestamp => erlang:system_time(millisecond),
        node => node()
    }.

ntoa(undefined) -> undefined;
ntoa({IpAddr, Port}) -> iolist_to_binary([inet:ntoa(IpAddr), ":", integer_to_list(Port)]);
ntoa(IpAddr) -> iolist_to_binary(inet:ntoa(IpAddr)).

printable_maps(undefined) ->
    #{};
printable_maps(Headers) ->
    maps:fold(
        fun
            (K, V0, AccIn) when K =:= peerhost; K =:= peername; K =:= sockname ->
                AccIn#{K => ntoa(V0)};
            ('User-Property', V0, AccIn) when is_list(V0) ->
                AccIn#{
                    %% The 'User-Property' field is for the convenience of querying properties
                    %% using the '.' syntax, e.g. "SELECT 'User-Property'.foo as foo"
                    %% However, this does not allow duplicate property keys. To allow
                    %% duplicate keys, we have to use the 'User-Property-Pairs' field instead.
                    'User-Property' => maps:from_list(V0),
                    'User-Property-Pairs' => [
                        #{
                            key => Key,
                            value => Value
                        }
                        || {Key, Value} <- V0
                    ]
                };
            (_K, V, AccIn) when is_tuple(V) ->
                %% internal headers
                AccIn;
            (K, V, AccIn) ->
                AccIn#{K => V}
        end,
        #{'User-Property' => #{}},
        Headers
    ).

topic_parse([]) ->
    ok;
topic_parse([#{filter := Filter, name := Name, collection := Collection} | T]) ->
    Item = {Name, Filter, Collection},
    ets:insert(?PLUGIN_MONGODB_TAB, Item),
    topic_parse(T);
topic_parse([_ | T]) ->
    topic_parse(T).

select(Message) ->
    select(ets:tab2list(?PLUGIN_MONGODB_TAB), Message, []).

select([], _, Acc) ->
    {true, Acc};
select([{Name, Filter, Collection} | T], Message, Acc) ->
    case match_topic(Message, Filter) of
        true ->
            select(T, Message, [{Name, Collection} | Acc]);
        false ->
            select(T, Message, Acc)
    end.

match_topic(_, <<$#, _/binary>>) ->
    false;
match_topic(_, <<$+, _/binary>>) ->
    false;
match_topic(#message{topic = <<"$SYS/", _/binary>>}, _) ->
    false;
match_topic(#message{topic = Topic}, Filter) ->
    emqx_topic:match(Topic, Filter);
match_topic(_, _) ->
    false.