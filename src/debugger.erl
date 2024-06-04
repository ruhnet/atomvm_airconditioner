%%
%% Copyright (c) 2024 RuhNet
%% All rights reserved.
%%
%% Licensed under the GPL v3.
%%

-include("app.hrl").

-module(debugger).
-behavior(gen_server).

-export([log/1, format/1, format/2, enable/0, disable/0, mqtt_only/0, console_only/0, set_boot_time/0, uptime/0]).
-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

start_link() ->
    io:format("Starting ~p with ~p/~p...~n", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY]),
    {ok, _Pid} = gen_server:start_link({local, ?MODULE}, ?MODULE, ?DEBUG_ENABLED_BY_DEFAULT, []).

init(DebugStatus) ->
    io:format("~p:~p/~p called with arg: '~p'.~n", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY, DebugStatus]),
    %erlang:send(self(), uptime),
    %erlang:send_after(60000, self(), time),
    {ok, {DebugStatus, erlang:universaltime()}}. %set state of default debug status and bootup time

handle_call(get, _From, State={DebugType, _}) ->
    %io:format("GETTING DEBUG TYPE~n"),
    {reply, DebugType, State};
handle_call(enable, _From, _State={_, BootTime}) ->
    {reply, ok, {true, BootTime}};
handle_call(disable, _From, _State={_, BootTime}) ->
    {reply, ok, {false, BootTime}};
handle_call(console_only, _From, _State={_, BootTime}) ->
    {reply, ok, {console_only, BootTime}};
handle_call(mqtt_only, _From, _State={_, BootTime}) ->
    {reply, ok, {mqtt_only, BootTime}};
handle_call({set_boot_time, NewBootTime}, _From, {DebugType, _}) ->
    {reply, ok, {DebugType, NewBootTime}};
handle_call(boot_time, _From, State={_, BootTime}) ->
    {reply, BootTime, State};
handle_call(Call, _From, State) ->
    erlang:display(Call),
    {reply, ok, State}.

handle_cast(Msg, State={DebugType, _}) ->
    select_output(DebugType, Msg),
%    erlang:display(Call),
    {noreply, State}.


%handle_info(time, State) ->
%    {{Year, Month, Day}, {Hour, Minute, Second}} = erlang:universaltime(),
%    debugger:format("[DEBUG] Time: ~p/~2..0p/~2..0p ~2..0p:~2..0p:~2..0p", [ Year, Month, Day, Hour, Minute, Second ]),
%    erlang:send_after(60000, self(), time),
%    {noreply, State};
handle_info(uptime, State) ->
    {_, {{Year, Month, Day}, {Hour, Minute, Second}}} = State,
    debugger:format("BOOT TIME: ~p/~2..0p/~2..0p ~2..0p:~2..0p:~2..0p", [ Year, Month, Day, Hour, Minute, Second ]),
    debugger:format("UPTIME: ~p minutes ",  [trunc(erlang:monotonic_time(second)/60)]),
    %erlang:send_after(900000, self(), uptime), %repeat every 15 minutes
    {noreply, State};
handle_info(Msg, State) ->
    select_output(State, Msg),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

select_output(Mode, Msg) ->
    case Mode of
        console_only ->
            %io:format("[DEBUG]: ~p\n", [Msg]);
            io:format(Msg),
            io:format("\n");
        mqtt_only ->
            notify(?TOPIC_DEBUG, Msg);
        true ->
            %io:format("[DEBUG]: ~p~n", [Msg]),
            io:format(Msg),
            io:format("\n"),
            notify(?TOPIC_DEBUG, Msg);
        false -> ok
    end.

notify(Topic, Msg) ->
    case whereis(mqtt_client) of
        undefined -> io:format("[DEBUG MQTT dead] MSG:~p", [Msg]);
        _Pid -> spawn(mqtt:publish_and_forget(Topic, Msg))
    end.

enable() ->
    gen_server:call(?MODULE, enable).

disable() ->
    gen_server:call(?MODULE, disable).

mqtt_only() ->
    gen_server:call(?MODULE, mqtt_only).

console_only() ->
    gen_server:call(?MODULE, console_only).

log(Msg) ->
    gen_server:cast(?MODULE, Msg).
%    DebugType = gen_server:call(?MODULE, get),
%    select_output(DebugType, Msg).

format(Msg) ->
    log(Msg).

format(FmtMsg, FmtArgs) ->
    Msg = io_lib:format(FmtMsg, FmtArgs),
    %gen_server:cast(?MODULE, Msg).
    log(Msg).

uptime() ->
    erlang:send(?MODULE, uptime).

set_boot_time() ->
    gen_server:call(?MODULE, {set_boot_time, erlang:universaltime()}). %set state of default debug status and bootup time

