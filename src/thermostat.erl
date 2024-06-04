%%
%% Copyright (c) 2024 RuhNet
%% All rights reserved.
%%
%% Licensed under the GPL v3.
%%

-include("app.hrl").

-module(thermostat).
-behavior(gen_server).

-export([up/0, down/0, get_thermostat/0, set_temp/1, set_span/1, load/0, save/0, default/0]).
-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

start_link() ->
    debugger:format("Starting ~p with ~p/~p...", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY]),
    {ok, _Pid} = gen_server:start_link({local, ?MODULE}, ?MODULE, [?THERMOSTAT_DEFAULT, ?THERMOSTAT_SPAN_DEFAULT], []).

init(Args = [DefTempBinInt, DefSpanBinFloat]) ->
    debugger:format("~p:~p/~p called with args: ~p...", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY, Args]),
    StartTemp = esp:nvs_get_binary(?NVS_NAMESPACE, thermostat, DefTempBinInt),
    SpanDegrees = esp:nvs_get_binary(?NVS_NAMESPACE, span, DefSpanBinFloat),
    debugger:format("[~p:~p] Setting initial values. Temp: ~p Span: ~p", [?MODULE, ?FUNCTION_NAME, StartTemp, SpanDegrees]),
    {ok, [{temp, binary_to_integer(StartTemp)}, {span, binary_to_float(SpanDegrees)}]}.

handle_info({set_temp, Temp}, State=[_T, Span]) ->
    if
        Temp >= ?MIN_THERMOSTAT andalso Temp =< ?MAX_THERMOSTAT ->
            {noreply, [{temp, Temp}, Span]};
        true -> {noreply, State}
    end.

handle_call({set_temp, Temp}, _From, State=[_T, Span]) ->
    if
        Temp >= ?MIN_THERMOSTAT andalso Temp =< ?MAX_THERMOSTAT ->
            {reply, ok, [{temp, Temp}, Span]};
        true -> {reply, ok, State}
    end;
handle_call({up}, _From, _State=[{temp, Temp}, Span]) ->
    {reply, ok, [{temp, Temp+1}, Span]};
handle_call({down}, _From, _State=[{temp, Temp}, Span]) ->
    {reply, ok, [{temp, Temp-1}, Span]};
handle_call({default}, _From, _State=[_T, Span]) ->
    {reply, ok, [{temp, binary_to_integer(?THERMOSTAT_DEFAULT)}, Span]};
handle_call({load}, _From, _State=[_T, Span]) ->
    StoredTemp = esp:nvs_get_binary(?NVS_NAMESPACE, thermostat, ?THERMOSTAT_DEFAULT),
    {reply, ok, [{temp, binary_to_integer(StoredTemp)}, Span]};
handle_call({save}, _From, State=[{temp, Temp}, {span, Span}]) ->
    debugger:format("[~p:~p] Saving current thermostat value: ~p", [?MODULE, ?FUNCTION_NAME, Temp]),
    esp:nvs_set_binary(?NVS_NAMESPACE, thermostat, integer_to_binary(Temp)),
    esp:nvs_set_binary(?NVS_NAMESPACE, span, float_to_binary(Span, [{decimals, 1}])),
    {reply, ok, State};
handle_call({set_span, Span}, _From, [{temp, Temp}|_]) ->
    debugger:format("[~p:~p] Setting new span value: ~p", [?MODULE, ?FUNCTION_NAME, Span]),
    {reply, ok, [{temp, Temp}, {span, Span/1}]}; %divide by one forces float
handle_call(get, _From, State) ->
    {reply, State, State};
handle_call(Call, _From, State) ->
    debugger:log(Call),
    %erlang:display(Call),
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

up() ->
    gen_server:call(?MODULE, {up}).

down() ->
    gen_server:call(?MODULE, {down}).

get_thermostat() ->
    gen_server:call(?MODULE, get).

set_temp(TempInput) ->
    Temp = util:make_int(TempInput),
    gen_server:call(?MODULE, {set_temp, Temp}).

set_span(DegreesInput) ->
    Span = util:make_float(DegreesInput),
    gen_server:call(?MODULE, {set_span, Span}).

load() ->
    gen_server:call(?MODULE, {load}).

save() ->
    gen_server:call(?MODULE, {save}).

default() ->
    gen_server:call(?MODULE, {default}).


