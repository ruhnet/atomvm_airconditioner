
%%
%% Copyright (c) 2024 RuhNet
%% All rights reserved.
%%
%% Licensed under the GPL v3.
%%

-include("app.hrl").

-module(button_watcher).
-export([start_link/0, init/1]).

start_link() ->
    debugger:format("Starting '~p' with ~p/~p...", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY]),
    init([]).
    %timer:sleep(1).

init(_) ->
    debugger:format("[~p:~p] Starting...", [?MODULE, ?FUNCTION_NAME]),
    led:flash(?STATUS_LED, 20, 20),
    %_Pid = spawn_link(?MODULE, read_buttons, []),
    %{ok, self()}.
    Pid = spawn(fun read_buttons/0),
    {ok, Pid}.

read_buttons() ->
    case gpio:digital_read(?BUTTON_MODE) of
        low ->
            control:cycle_mode(),
            io:format("[~p:~p] Mode button (~p) pressed!\n", [?MODULE, ?FUNCTION_NAME, ?BUTTON_MODE]);
        high ->
            io:format("[~p:~p] Mode button (~p) released!\n", [?MODULE, ?FUNCTION_NAME, ?BUTTON_MODE])
    end,
    case gpio:digital_read(?BUTTON_FAN) of
        low ->
            control:cycle_fan(),
            io:format("[~p:~p] Fan button (~p) pressed!\n", [?MODULE, ?FUNCTION_NAME, ?BUTTON_FAN]);
        high ->
            io:format("[~p:~p] Fan button (~p) released!\n", [?MODULE, ?FUNCTION_NAME, ?BUTTON_FAN])
    end,
    case gpio:digital_read(?BUTTON_TEMP_UP) of
        low ->
            thermostat:up(),
            io:format("[~p:~p] Temp up button (~p) pressed!\n", [?MODULE, ?FUNCTION_NAME, ?BUTTON_TEMP_UP]);
        high ->
            io:format("[~p:~p] Temp up button (~p) released!\n", [?MODULE, ?FUNCTION_NAME, ?BUTTON_TEMP_UP])
    end,
    case gpio:digital_read(?BUTTON_TEMP_DOWN) of
        low ->
            thermostat:down(),
            io:format("[~p:~p] Temp down button (~p) pressed!\n", [?MODULE, ?FUNCTION_NAME, ?BUTTON_TEMP_DOWN]);
        high ->
            io:format("[~p:~p] Temp down button (~p) released!\n", [?MODULE, ?FUNCTION_NAME, ?BUTTON_TEMP_DOWN])
    end,
    timer:sleep(50),
    read_buttons().



