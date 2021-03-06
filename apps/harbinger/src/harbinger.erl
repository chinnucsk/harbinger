%% This Source Code Form is subject to the terms of
%% the Mozilla Public License, v. 2.0.
%% A copy of the MPL can be found in the LICENSE file or
%% you can obtain it at http://mozilla.org/MPL/2.0/.
%%
%% @author Brendan Hay
%% @copyright (c) 2012 Brendan Hay <brendan@soundcloud.com>
%% @doc
%%

-module(harbinger).

-behaviour(application).

-include_lib("riak_core/include/riak_core_vnode.hrl").
-include("harbinger.hrl").

%% API
-export([start/0,
         stop/0,
         topic/0]).

%% Callbacks
-export([start/2,
         stop/1]).

%%
%% API
%%

-spec start() -> ok.
%% @doc
start() -> application:start(?MODULE).

-spec stop() -> ok.
%% @doc
stop() ->
    ok = application:stop(?MODULE),
    init:stop().

%% @doc Ping a random topic vnode
topic() ->
    ping({<<"ping">>, term_to_binary(now())},
         ?TOPIC_MASTER,
         harbinger_topic).

%%
%% Callbacks
%%

-spec start(normal, _) -> {ok, pid()} | {error, _}.
%% @hidden
start(_StartType, _StartArgs) ->
    ok = riak_core_util:start_app_deps(?MODULE),
    case harbinger_sup:start_link() of
        {ok, Pid} ->
            ok = riak_core_ring_events:add_guarded_handler(harbinger_ring_event_handler, []),
            ok = riak_core_node_watcher_events:add_guarded_handler(harbinger_node_event_handler, []),
            ok = riak_core:register([{vnode_module, harbinger_topic_vnode}]),
            ok = riak_core:register([{vnode_module, harbinger_queue_vnode}]),
            ok = riak_core_node_watcher:service_up(harbinger_topic, self()),
            ok = riak_core_node_watcher:service_up(harbinger_queue, self()),
            {ok, Pid};
        {error, Reason} ->
            {error, Reason}
    end.

-spec stop(_) -> ok.
%% @hidden
stop(_Args) -> ok.

%%
%% Private
%%

%% @private
ping(Key, VMaster, Service) ->
    DocIdx = riak_core_util:chash_key(Key),
    case riak_core_apl:get_primary_apl(DocIdx, 1, Service) of
        [{IdxNode = {_Hash, Host}, _Type}] ->
            {riak_core_vnode_master:sync_spawn_command(IdxNode, ping, VMaster), Host};
        Other ->
            lager:error("Unexpected PrefList: ~p", [Other])
    end.
