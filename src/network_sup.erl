%%
%% Copyright (c) 2024 RuhNet
%% All rights reserved.
%%
%% Licensed under the GPL v3.
%%

-module(network_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init([]) ->
    debugger:format("Starting ~p supervisor with ~p/~p...", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY]),
    MaxRestarts = 3, % Kill everyone and die if more than MaxRestarts failures per MaxSecBetweenRestarts seconds
    MaxSecBetweenRestarts = 60,
    WiFi = worker(wifi, start_link, []),
    MQTT_Controller = worker(mqtt, start_link, []),
    %MQTTClient = worker(mqtt_client, start_link, []),
    %HTTP = worker(httpsrv, start_link, []),

    % rest_for_one restart strategy would be preferrable here but is not yet supported :)
    %{ok, {{rest_for_one, MaxRestarts, MaxSecBetweenRestarts}, [
    {ok, {{one_for_one, MaxRestarts, MaxSecBetweenRestarts}, [
                                                              MQTT_Controller %start before wifi!
                                                              ,WiFi
                                                              %,MQTTClient
                                                              %,HTTP
                                                             ] }}.

%Create a worker spec:
worker(Name, StartFunc, Args) ->
    {Name, {Name, StartFunc, Args}, permanent, brutal_kill, worker, [Name]}.

