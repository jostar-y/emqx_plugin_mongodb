-module(emqx_plugin_mongodb_cli).

-export([cmd/1]).

cmd(["reload"]) ->
    emqx_plugin_mongodb:reload(),
    emqx_ctl:print("topics configuration reload complete.\n");

cmd(_) ->
    emqx_ctl:usage([{"emqx_plugin_mongodb reload", "Reload topics"}]).
