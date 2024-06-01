%
%% Copyright (c) 2024 RuhNet
%% All rights reserved.
%%
%% Licensed under the GPL v3.
%%

-include("app.hrl").

-module(control).
-behavior(gen_server).

-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
-export([set_mode/1, cycle_mode/0, set_fan/1, cycle_fan/0, set_safe/0, all_off/0 ]). %, load/0, save/0]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc This module is the master control for the air conditioner.
%%% State is tuple list of [
%%%                         {mode, off|cool|energy_saver|fan_only},
%%%                         {fan speed, 1|2|3},
%%%                         {compressor on|off},
%%%                         {compressor_safe, safe|wait}
%%%                        ]
%%% Mode 'energy_saver' turns fan on/off along with compressor, while 'on', keeps fan running constantly.
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

start_link() ->
    debugger:format("Starting '~p' with ~p/~p...~n", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY]),
    {ok, _Pid} = gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init(_) ->
    debugger:format("Starting '~p' with ~p/~p...~n", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY]),
    util:beep(880, 1000),
    %erlang:send_after(200, self(), start),
    erlang:send_after(200, ?MODULE, start),
    %set initial state:
    {ok, [{mode, off}, {fan, 3}, {compressor, off}, {compressor_safe, wait}] }.

terminate(_Reason, _State) ->
    ok.

handle_cast(set_safe, _State=[{mode, M}, {fan, F}, {compressor, C}, {compressor_safe, _CS}]) ->
    debugger:format("[~p:~p] overriding wait timer; setting compressor_safety: 'safe'~n", [?MODULE, ?FUNCTION_NAME]),
    spawn(fun() -> led:flash(?COMPRESSOR_LED, 50, 8) end),
    {noreply, [{mode, M}, {fan, F}, {compressor, C}, {compressor_safe, safe}] };

handle_cast(cycle_mode, [{mode, M}, {fan, F}, {compressor, C}, {compressor_safe, CS}]) ->
    Mode = case M of
        off -> cool;
        cool -> energy_saver;
        energy_saver -> fan_only;
        fan_only -> off
    end,
    {noreply, [{mode, Mode}, {fan, F}, {compressor, C}, {compressor_safe, CS}]};

handle_cast(cycle_fan, [{mode, M}, {fan, F}, {compressor, C}, {compressor_safe, CS}]) ->
    Fan = case F of
        1 -> 2;
        2 -> 3;
        3 -> 1
    end,
    case M of
        cool -> fan(Fan);
        fan_only -> fan(Fan);
        energy_saver -> fan(Fan);
        _ -> ok
    end,
    {noreply, [{mode, M}, {fan, Fan}, {compressor, C}, {compressor_safe, CS}]};

handle_cast(_Msg, State) ->
    {noreply, State}.


%%% MODE SELECTION  off|cool|energy_saver|fan_only
handle_call({set_mode, Mode}, _From, _State=[{mode, M}, {fan, F}, {compressor, C}, {compressor_safe, CS}]) ->
    erlang:send(?MODULE, {set_mode, Mode}),
    {reply, ok, [{mode, Mode}, {fan, F}, {compressor, C}, {compressor_safe, CS}] };

%%% FAN SELECTION 1|2|3
handle_call({set_fan, FanNew}, _From, _State=[{mode, Mode}, {fan, F}, {compressor, C}, {compressor_safe, CS}]) ->
    erlang:send(?MODULE, {set_fan, FanNew}),
    {reply, ok, [{mode, Mode}, {fan, F}, {compressor, C}, {compressor_safe, CS}] };

handle_call(Msg, _From, State) ->
    debugger:format("[~p] Received unknown ~p message: ~p~n", [?MODULE, ?FUNCTION_NAME, Msg]),
    {reply, ok, State}.


handle_info(start, State) ->
    % Start first compressor safety timer
    erlang:send(?MODULE, operation_loop),
    %[{mode, M}, {fan, F}, {compressor, C}, {compressor_safe, CS}] = State,
    %debugger:format("[control] handle_info start: State=[mode:~p f:~p comp:~p cs:~p].~n", [M, F, C, CS]),
    debugger:format("[~p:~p]start Setting initial safety delay of ~p seconds...~n", [?MODULE, ?FUNCTION_NAME, trunc(?SAFETY_DELAY / 1000)]),
    fan(0), %just in case we crashed and fan is still on.
    compressor_set(off), %just in case we crashed and compressor is still on.
    erlang:send_after(?SAFETY_DELAY, ?MODULE, {compressor_safety, safe}), %mark safe after the delay has elapsed
    {noreply, State};

handle_info({compressor_safety, CSafe}, _State=[{mode, M}, {fan, F}, {compressor, C}, {compressor_safe, _CS}]) ->
    debugger:format("[~p:~p] setting compressor_safety to: ~p~n", [?MODULE, ?FUNCTION_NAME, CSafe]),
    %io:format("[control] handle_info compressorsafety:~p. State=[mode:~p f:~p comp:~p cs:~p].~n", [CSafe, M, F, C, _CS]),
    %io:format("[control] handle_info compressorsafety NewState=[mode:~p f:~p comp:~p cs:~p].~n", [M, F, C, CSafe]),
    {noreply, [{mode, M}, {fan, F}, {compressor, C}, {compressor_safe, CSafe}] };

%%% MODE SELECTION  off|cool|energy_saver|fan_only
handle_info({set_mode, Mode}, _State=[{mode, M}, {fan, F}, {compressor, C}, {compressor_safe, CS}]) ->
    debugger:format("[~p:~p] changing mode from ~p to new setting: ~p~n", [?MODULE, ?FUNCTION_NAME, M, Mode]),
    {Comp, CSafe} = case Mode of
        off ->
           fan(0),
           case C of
               on -> erlang:send_after(?SAFETY_DELAY, ?MODULE, {compressor_safety, safe}),
                     {compressor_set(off), wait};
               _ -> {off, CS}
           end;
        fan_only ->
           erlang:send(?MODULE, {set_fan, fan_on(F)}),
           case C of
               on -> erlang:send_after(?SAFETY_DELAY, ?MODULE, {compressor_safety, safe}),
                     {compressor_set(off), wait};
               _ -> {off, CS}
           end;
        _ -> erlang:send(?MODULE, {set_fan, F}),
             {C, CS}
    end,
    State = [{mode, Mode}, {fan, F}, {compressor, Comp}, {compressor_safe, CSafe}],
    notify(?TOPIC_STATUS, status_binary(State, "mode_changed")),
    spawn(fun() -> util:beep(440, 100) end),
    spawn(fun() -> led:flash(?STATUS_LED, 100, 4) end),
    {noreply, State};

%%% FAN SELECTION 1|2|3
handle_info({set_fan, FanNew}, _State=[{mode, Mode}, {fan, FanPrev}, {compressor, C}, {compressor_safe, CS}]) ->
    F = case FanNew of %this keeps the fan selection between 1 and 3. Even if fan is off (mode off) the fan should be 1, 2, or 3
            0 ->
                fan(0),
                FanPrev;
            _NewFan ->
                spawn(fun() ->
                    timer:sleep(1000), %no reason for this other than to seem neat :)
                    fan(FanNew)
                end),
                case FanNew of
                    3 -> 3;
                    2 -> 2;
                    1 -> 1;
                    _ -> FanPrev
                end
    end,
    {noreply, [{mode, Mode}, {fan, F}, {compressor, C}, {compressor_safe, CS}] };


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% OPERATION LOOP
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%compressor not safe (wait)
handle_info(operation_loop, State=[{mode, Mode}, {fan, F}, {compressor, C}, {compressor_safe, wait}]) ->
    debugger:format("[~p:~p] operation_loop State=[mode:~p f:~p comp:~p cs:wait].~n", [?MODULE, ?FUNCTION_NAME, Mode, F, C]),
    case C of
        on -> compressor_set(off); %this should never happen, but if it does, we want the log message
        _ -> compressor_set_outputs(off) %silently make sure compressor is off
    end,
    case Mode of %allow fan to run even if compressor is in 'wait' stage
        cool -> fan(F);
        energy_saver ->
            debugger:format("[~p] Turning fan off since we are in energy_saver mode and compressor is off...~n", [?MODULE]),
            fan(0);
        fan_only -> fan_on(F);
        _ -> ok
    end,
    notify(?TOPIC_STATUS, status_binary(State)),
    erlang:send_after(20000, ?MODULE, operation_loop),
    {noreply, State};

%mode is on (some form or another), and compressor is off: turn on compressor if temp/thermostat requires
handle_info(operation_loop, [{mode, Mode}, {fan, F}, {compressor, off}, {compressor_safe, safe}] ) ->
    case Mode of %set the fan state first
        cool -> fan(F);
        fan_only -> fan(F);
        _ -> ok
    end,
    %[{temp, Temp}, {coiltemp, CoilTemp}, _, _, _] = temperature:get_temperature(),
    [{temp, Temp}, {coiltemp, CoilTemp} |_] = temperature:get_temperature(),
    [{temp, TSet}, {span, Span}] = thermostat:get_thermostat(),
    %HalfSpan = Span / 2, %CANNOT do math operations within an if/when clause!
    {TempIsHigh, _TempIsLow} = cutoff_check(Temp, TSet, Span),
    Comp = if
        TempIsHigh
        %Temp >= (TSet + HalfSpan)
        andalso Temp /= 0
        andalso ((Mode == cool) orelse (Mode == energy_saver))
        andalso ((CoilTemp > (?COIL_TEMP_LIMIT + 5))
                 orelse (CoilTemp =< 15)
                 orelse (CoilTemp == 0)
                 orelse ((CoilTemp >= 31.5) andalso (CoilTemp =< 32.5))) ->
            case Mode of
                energy_saver -> fan_on(F);
                _ -> ok
            end,
            compressor_set(on);
        true -> off
    end,
    State = [{mode, Mode}, {fan, F}, {compressor, Comp}, {compressor_safe, safe}],
    debugger:format("[~p:~p] operation_loop State=[mode:~p f:~p comp:~p cs:~p].~n", [?MODULE, ?FUNCTION_NAME, Mode, F, Comp, safe]),
    notify(?TOPIC_STATUS, status_binary(State)),
    erlang:send_after(20000, ?MODULE, operation_loop),
    {noreply, State};

%compressor is on; regardless of mode, turn off compressor (and set safety delay), if temp requires.
handle_info(operation_loop, [{mode, Mode}, {fan, F}, {compressor, on}, {compressor_safe, safe}]) ->
    [{temp, Temp}, {coiltemp, CoilTemp} |_] = temperature:get_temperature(),
    [{temp, TSet}, {span, Span}] = thermostat:get_thermostat(),
    %HalfSpan = Span / 2,
    {_TempIsHigh, TempIsLow} = cutoff_check(Temp, TSet, Span),
    {Comp, CS, StatusMsg} = if
        (CoilTemp =< ?COIL_TEMP_LIMIT)
                andalso ((CoilTemp =< 31.5) orelse (CoilTemp >= 32.5)) %temp sensor at 0C, (probably unplugged)
                andalso (CoilTemp >= 15) %thermistor unplugged?
                andalso (CoilTemp /= 0) ->
            compressor_set(off),
            erlang:send_after(?SAFETY_DELAY, ?MODULE, {compressor_safety, safe}),
            Msg = io_lib:format("COMPRESSOR FREEZE STOP! Coil temperature is: ~.1f", [CoilTemp]),
            spawn(fun() -> util:beep(880, 1000), util:beep(440, 1000), util:beep(880, 1000), util:beep(880, 1000) end),
            debugger:format("~p~n", [Msg]),
            {off, wait, Msg};
        %Temp =< (TSet - HalfSpan) -> %normal temp low compressor shutoff
        TempIsLow -> %normal temp low compressor shutoff
            compressor_set(off),
            erlang:send_after(?SAFETY_DELAY, ?MODULE, {compressor_safety, safe}),
            {off, wait, "thermostat compressor off"};
        true ->
            fan_on(F), %Compressor is on, so just in case, we make sure fan is also on.
            {on, safe, "ok"}
    end,
    State = [{mode, Mode}, {fan, F}, {compressor, Comp}, {compressor_safe, CS}],
    %debugger:format("[~p] ~p operation_loop T=~.2f, CT=~.2f, TS=~p, S=~.1f, State=[mode:~p f:~p comp:~p cs:~p].~n", [?MODULE, ?FUNCTION_NAME, Temp, CoilTemp,TSet, Span, Mode, F, on, safe]),
    debugger:format("[~p:~p] operation_loop State=[mode:~p f:~p comp:~p cs:~p].~n", [?MODULE, ?FUNCTION_NAME, Mode, F, Comp, CS]),
    notify(?TOPIC_STATUS, status_binary(State, StatusMsg)),
    erlang:send_after(20000, ?MODULE, operation_loop),
    {noreply, State}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Convenience functions:
%%%
set_mode(Mode) -> % off|cool|energy_saver|fan_only
    case validate_mode(Mode) of
        invalid -> invalid_mode;
        ValidMode -> gen_server:call(?MODULE, {set_mode, ValidMode})
    end.

set_status_led(Mode) ->
    case Mode of
        off -> util:set_output(?STATUS_LED, off);
        on -> util:set_output(?STATUS_LED, on);
        cool -> util:set_output(?STATUS_LED, on);
        energy_saver -> util:set_output(?STATUS_LED, on);
        fan_only -> util:set_output(?STATUS_LED, on);
        _ -> util:set_output(?STATUS_LED, off)
    end.

%set_mode(Mode) -> % off|cool|energy_saver|fan_only
%    case mode_valid(Mode) of
%        true -> gen_server:call(?MODULE, {set_mode, Mode});
%        _ -> invalid_mode
%    end.

validate_mode(Mode) ->
    case Mode of
        off -> off;
        "off" -> off;
        "OFF" -> off;
        cool -> cool;
        "cool" -> cool;
        "COOL" -> cool;
        energy_saver -> energy_saver;
        "energy_saver" -> energy_saver;
        "ENERGY_SAVER" -> energy_saver;
        fan_only -> fan_only;
        "fan_only" -> fan_only;
        "FAN_ONLY" -> fan_only;
        fan -> fan_only;
        "fan" -> fan_only;
        "FAN" -> fan_only;
        _ -> invalid
    end.


mode_valid(Mode) ->
    case Mode of
        off -> true;
        cool -> true;
        energy_saver -> true;
        fan_only -> true;
        _ -> false
    end.

set_fan(Fan) ->
    gen_server:call(?MODULE, {set_fan, Fan}).

set_safe() ->
    util:beep(1000, 200),
    timer:sleep(200),
    util:beep(1000, 200),
    gen_server:cast(?MODULE, set_safe).

cutoff_check(Temp, TSet, Span) ->
    %determine cutoff temperature based on thermostat and span size.
    %If span size is small (<3), split it evenly. If large, bias it
    %towards cooling further under the thermostat setpoint before cutting
    %off compressor.
    HalfSpan = Span/2,
    SmallPartOfSpan = Span * 0.25,
    LargePartOfSpan = Span * 0.75,
    HighPoint = case (Span < 3) of
        true -> TSet + HalfSpan;
        _ -> TSet + SmallPartOfSpan
    end,
    LowPoint = case (Span < 3) of
        true -> TSet - HalfSpan;
        _ -> TSet - LargePartOfSpan
    end,
    debugger:format("[~p:~p] Cutoff Temps: [highpoint: ~.2f lowpoint: ~.2f]~n", [?MODULE, ?FUNCTION_NAME, HighPoint, LowPoint]),
    {Temp >= HighPoint, Temp =< LowPoint}.


%load() ->
%    gen_server:call(?MODULE, {load}).
%
%save() ->
%    gen_server:call(?MODULE, {save}).

all_off() ->
    compressor_set(off),
    fan(0).

compressor_set(C) ->
    debugger:format("[~p] ~p: TURNING ~p COMPRESSOR.~n", [?MODULE, ?FUNCTION_NAME, C]),
    compressor_set_outputs(C).

compressor_set_outputs(C) ->
    util:set_output(?COMPRESSOR, C),
    util:set_output(?COMPRESSOR_LED, C),
    C.

cycle_mode() ->
    gen_server:cast(?MODULE, cycle_mode).

cycle_fan() ->
    gen_server:cast(?MODULE, cycle_fan).

fan_on(F) ->
    case F of
        0 -> fan(3);
        _ -> fan(F)
    end.

fan(F) ->
    debugger:format("Setting fan to ~p.~n", [F]),
    case util:make_int(F) of
        0 ->
            util:set_output(?FAN1, off),
            util:set_output(?FAN2, off),
            util:set_output(?FAN3, off),
            0;
        1 ->
            util:set_output(?FAN2, off), %turn off the ones that may be on before turning on the one required
            util:set_output(?FAN3, off),
            util:set_output(?FAN1, on),
            1;
        2 ->
            util:set_output(?FAN1, off),
            util:set_output(?FAN3, off),
            util:set_output(?FAN2, on),
            2;
        3 ->
            util:set_output(?FAN1, off),
            util:set_output(?FAN2, off),
            util:set_output(?FAN3, on),
            3;
        _ -> 0
    end.

notify(Topic, Msg) ->
    case whereis(mqtt_client) of
        undefined -> io:format("MQTT is not alive; message: ~p~n", [Msg]);
        %_Pid -> spawn( fun() -> mqtt:pub(Topic, Msg) end) % this notify/2 is called from handle_call/handle_info, so need to return quickly.
        _Pid -> mqtt:publish_and_forget(Topic, Msg) % this notify/2 is called from handle_call/handle_info, so need to return quickly.
    end.

status_binary(State) ->
    status_binary(State, "ok").

status_binary([{mode, Mode}, {fan, Fan}, {compressor, Comp}, {compressor_safe, CS}], StatusMsg) ->
    [{temp, TStat}, {span, Span}] = thermostat:get_thermostat(),
    [{temp, _}, {coiltemp, CoilTemp}, {templocal, TempLocal}, {tempremote, TempRemote}, {tempsrc, TempSrc}] = temperature:get_temperature(),
    {{Year, Month, Day}, {Hour, Minute, Second}} = erlang:universaltime(),
    BMode = util:convert_to_binary(Mode),
    BFan = util:convert_to_binary(Fan),
    BComp = util:convert_to_binary(Comp),
    BTempLocal = util:convert_to_binary(TempLocal),
    BTempRemote = util:convert_to_binary(TempRemote),
    BTempSrc = util:convert_to_binary(TempSrc),
    BCoilTemp = util:convert_to_binary(CoilTemp),
    BTStat = util:convert_to_binary(TStat),
    BSpan = util:convert_to_binary(Span),
    BCS = util:convert_to_binary(CS),
    BTime = util:convert_to_binary(io_lib:format("~p~2..0p~2..0p ~2..0p:~2..0p:~2..0p", [ Year, Month, Day, Hour, Minute, Second ])),
    BStatusMsg = util:convert_to_binary(StatusMsg),
   <<"{"
   ,"\"mode\":\"", BMode/binary, "\","
   ,"\"fan\":", BFan/binary, ","
   ,"\"compressor\":\"", BComp/binary, "\","
   ,"\"temp_local\":", BTempLocal/binary, ","
   ,"\"temp_remote\":", BTempRemote/binary, ","
   ,"\"thermostat\":", BTStat/binary, ","
   ,"\"tempsource\":\"", BTempSrc/binary, "\","
   ,"\"span\":", BSpan/binary, ","
   ,"\"coil\":", BCoilTemp/binary, ","
   ,"\"comp_safe\":\"", BCS/binary, "\","
   ,"\"time\":\"", BTime/binary, "\","
   ,"\"status\":\"", BStatusMsg/binary, "\""
   ,"}">>.

%status_string([{mode, Mode}, {fan, Fan}, {compressor, Comp}, {compressor_safe, CS}]) ->
%    {Temp, TempRemote, TempSrc, CoilTemp} = temperature:get_temperature(),
%    [{temp, TStat}, {span, Span}] = thermostat:get_thermostat(),
%    "{"
%    ++ "\"mode\":\"" ++ atom_to_list(Mode) ++ "\","
%    ++ "\"fan\":" ++ integer_to_list(Fan) ++ ","
%    ++ "\"compressor\":\"" ++ atom_to_list(Comp) ++ "\","
%    ++ "\"temp_local\":" ++ float_to_list(Temp, [{decimals, 2}]) ++ ","
%    ++ "\"temp_remote\":" ++ float_to_list(TempRemote, [{decimals, 2}]) ++ ","
%    ++ "\"thermostat\":" ++ integer_to_list(TStat) ++ ","
%    ++ "\"tempsource\":\"" ++ binary_to_list(TempSrc) ++ "\","
%    ++ "\"span\":" ++ float_to_list(Span, [{decimals, 2}]) ++ ","
%    ++ "\"coil\":" ++ float_to_list(CoilTemp, [{decimals, 2}]) ++ ","
%    ++ "\"comp_safe\":\"" ++ atom_to_list(CS) ++ "\""
%    ++ "}".


