%%
%% Copyright (c) 2024 RuhNet
%% All rights reserved.
%%
%% Licensed under the GPL v3.
%%

-include("app.hrl").

-module(util).

-export([
         set_output/2
         ,set_output_activelow/2
         ,timer/3
         ,timer/4
         ,print_time/0
         ,uptime/0
         ,beep/2
%         ,beep_pwm/2
         ,make_int/1
         ,make_float/1
         ,convert_to_binary/1
        ]).

set_output(Pin, State) ->
    Level = level(State), %validate the pin state.
    case Level of
        ok -> ok;
        _ -> gpio:digital_write(Pin, Level)
    end.

set_output_activelow(Pin, State) ->
    Level = level_reverse(level(State)), %validate the pin state.
    case Level of
        ok -> ok;
        _ -> gpio:digital_write(Pin, Level)
    end.

print_time() ->
    %debugger:format("Printing Time with ~p...~n", [?FUNCTION_NAME]),
    {{Year, Month, Day}, {Hour, Minute, Second}} = erlang:universaltime(),
    debugger:format("Date: ~p/~2..0p/~2..0p ~2..0p:~2..0p:~2..0p (~pms)~n", [
        Year, Month, Day, Hour, Minute, Second, erlang:system_time(millisecond)
    ]),
    {{Year, Month, Day}, {Hour, Minute, Second}}.


uptime() ->
    UptimeSec = erlang:monotonic_time(second),
    Days = trunc(UptimeSec/86400),
    Hours = case (UptimeSec > 86400) of
               true -> trunc((UptimeSec rem (Days * 86400))/3600);
               _ -> trunc(UptimeSec/3600)
           end,
    Mins = case (UptimeSec > 3600) of
              true -> trunc((UptimeSec rem ((Days*86400) + (Hours*3600)))/60);
              _ -> trunc(UptimeSec/60)
        end,
    Secs = case (UptimeSec > 60) of
              true -> (UptimeSec rem ((Days*86400) + (Hours*3600) + (Mins*60)));
              _ -> UptimeSec
        end,
    {{Year, Month, Day}, {Hour, Minute, Second}} = erlang:universaltime(),
    io:format("[~p~2..0p~2..0p ~2..0p:~2..0p:~2..0p] UPTIME [~p]: ~p days, ~p hours, ~p minutes, ~p seconds",  [Year, Month, Day, Hour, Minute, Second, UptimeSec, Days, Hours, Mins, Secs]),
    UptimeMsg = io_lib:format("[~p~2..0p~2..0p ~2..0p:~2..0p:~2..0p] UPTIME [~p]: ~p days, ~p hours, ~p minutes, ~p seconds",  [Year, Month, Day, Hour, Minute, Second, UptimeSec, Days, Hours, Mins, Secs]),
    UptimeMsg.

%%% FUNCTION TIMER
timer(Param, Val, Time) when is_binary(Time) ->
    {T, M} = parse_timer_time(Time),
    io:format("PARSED TIME: ~p, ~p ", [T, M]),
    timer(Param, Val, T, M);
timer(Param, Val, Time) ->
    timer(Param, Val, Time, s),
    io:format("PARSED TIME 22222 where time is not binary: ~p, ~p ", [x, x]).
timer(Param, Val, Time, Multiplier) ->
    io:format("[~p:~p] processing timer...~n", [?MODULE, ?FUNCTION_NAME]),
    T = make_int(Time),
    M = multiplier_from_specifier(Multiplier),
    MultP = parse_multiplier(Multiplier),
    Delay = T * M * 1000,
    {_, {Hour, Minute, Second}} = erlang:universaltime(),
    {TimerType, ModOrFunc, Args} = case Param of
             temp -> {message_send, thermostat, [set_temp, util:make_int(Val)]};
             set_temp -> {message_send, thermostat, [set_temp, util:make_int(Val)]};
             thermostat -> {message_send, thermostat, [set_temp, util:make_int(Val)]};
             span -> {message_send, thermostat, [set_span, util:make_int(Val)]};
             mode -> {message_send, control, [set_mode, control:validate_mode(Val)]};
             set_mode -> {message_send, control, [set_mode, control:validate_mode(Val)]};
             {Func, Argz} -> {function, Func, Argz}
        end,
    case TimerType of
        function ->
            [Arg1, Arg2] = Args,
            Pid = spawn(fun() ->
                timer:sleep(Delay),
                debugger:format("Previously set [~2..0p:~2..0p:~2..0p] function timer [after ~p~p] running Func(~p, ~p)] now!", [Hour, Minute, Second, T, M, Arg1, Arg2]),
                ModOrFunc(Arg1, Arg2),
                mqtt:publish_and_forget(?TOPIC_DEBUG, io_lib:format("Previously set [~2..0p:~2..0p:~2..0p] function timer just ran function Func(~p, ~p) after [~p~p].",  [Hour, Minute, Second, Arg1, Arg2, T, MultP]))
            end),
            debugger:format("[~2..0p:~2..0p:~2..0p] Setting function timer ~p for Func(~p, ~p)] in [~p~p] from now...", [Hour, Minute, Second, Pid, Arg1, Arg2, T, Multiplier]),
            io:format("[~2..0p:~2..0p:~2..0p] Setting function timer ~p for Func(~p, ~p)] in [~p~p] from now...", [Hour, Minute, Second, Pid, Arg1, Arg2, T, Multiplier]),
            mqtt:publish_and_forget(?TOPIC_DEBUG, io_lib:format("[~2..0p:~2..0p:~2..0p] Timer ~p set to run function Func(~p, ~p) in [~p~p] from now...",  [Hour, Minute, Second, Pid, Arg1, Arg2, T, MultP]));
        message_send ->
            Mod = ModOrFunc,
            [OpMsg, Value] = Args,
            spawn(fun() ->
                erlang:send_after(Delay, Mod, {OpMsg, Value}),
                debugger:format("[~2..0p:~2..0p:~2..0p] Setting message_send timer [~p ! {~p, ~p}] in [~p~p] from now...", [Hour, Minute, Second, Mod, OpMsg, Value, T, MultP]),
                {_, {Hour, Minute, Second}} = erlang:universaltime(),
                mqtt:publish_and_forget(?TOPIC_DEBUG, io_lib:format("[~2..0p:~2..0p:~2..0p] Timer sending [~p ! {~p, ~p}] in [~p~p] from now...",  [Hour, Minute, Second, Mod, OpMsg, Value, T, MultP]))
            end)
    end.


parse_timer_time(T) when is_integer(T) -> {T, s};
parse_timer_time(T) when is_binary(T) ->
    %io:format("[~p:~p] parsing timer time from binary...~n", [?MODULE, ?FUNCTION_NAME]),
    S = byte_size(T),
    {Time, MultiplierSuffix} = case binary:last(T) of
        100 -> binary_split(T, S-1); %d = days
        68 -> binary_split(T, S-1);  %D = days
        104 -> binary_split(T, S-1); %h = hours
        72 -> binary_split(T, S-1);  %H = hours
        109 -> binary_split(T, S-1); %m = minutes
        77 -> binary_split(T, S-1);  %M = minutes
        115 -> binary_split(T, S-1); %s = seconds
        83 -> binary_split(T, S-1);  %S = seconds
        _ -> {T, <<"s">>} %empty or invalid multipler (just seconds)
    end,
    {make_int(Time), MultiplierSuffix}.
    %make_int(Time) * multiplier_from_specifier(MultiplierSuffix). %total number of seconds

binary_split(Bin, PrefixSize) ->
   <<Prefix:PrefixSize/binary, Suffix/binary>> = Bin,
   {Prefix, Suffix}.

multiplier_from_specifier(Multiplier) ->
    M = parse_multiplier(Multiplier),
    case M of
        d -> 86400;
        h -> 3600;
        m -> 60;
        s -> 1;
        _ -> 1
    end.

parse_multiplier(Multiplier) ->
    case Multiplier of
        d -> d;
        "d" -> d;
        <<"d">> -> d;
        <<"D">> -> d;
        <<"day">> -> d;
        <<"days">> -> d;
        h -> h;
        "h" -> h;
        <<"h">> -> h;
        <<"H">> -> h;
        <<"hour">> -> h;
        <<"hours">> -> h;
        m -> m;
        "m" -> m;
        <<"m">> -> m;
        <<"M">> -> m;
        <<"min">> -> m;
        <<"minute">> -> m;
        <<"minutes">> -> m;
        _ -> s
    end.

%%% Crude beep/sound functionality - this should be done with proper timers or LEDC PWM.
beep(_Freq, _Duration) when (_Duration =< 1) ->
    ok;
beep(Freq, DurationMs) ->
    CyclePeriod = 1000 / Freq, %full cycle is 2 switch time intervals
    gpio:digital_write(?BEEPER, high),
    timer:sleep(trunc(CyclePeriod / 2)),
    gpio:digital_write(?BEEPER, low),
    timer:sleep(trunc(CyclePeriod / 2)),
    beep(Freq, DurationMs - CyclePeriod). %not accurate length, but good enough

%beep_pwm(Freq, Duration) ->
%    io:format("beeping at freq ~p for duration ~p ms.~n", [Freq, Duration]),
%    Freq = Freq,
%    {ok, Timer} = ledc_pwm:create_timer(Freq),
%    io:format("Timer: ~p~n", [Timer]),
%
%    {ok, Beeper} = ledc_pwm:create_channel(Timer, ?BEEPER),
%    %{ok, Beeper} = ledc_pwm:create_channel(Timer, 25),
%    io:format("Channel1: ~p~n", [Beeper]),
%
%    %FadeupMs = make_int(Duration),
%    FadeupMs = make_int(Duration/0.9),
%    ok = ledc_pwm:fade(Beeper, 100, FadeupMs),
%    timer:sleep(FadeupMs),
%
%    FadeDownMs = make_int(Duration/10),
%    ok = ledc_pwm:fade(Beeper, 0, FadeDownMs),
%    timer:sleep(FadeDownMs).


level(State) when is_list(State) ->
    level(list_to_binary(State));
level(State) ->
    case State of
        %on values:
        1 -> high;
        on -> high;
        high -> high;
        true -> high;
        <<"1">> -> high;
        <<"on">> -> high;
        <<"ON">> -> high;
        <<"On">> -> high;
        <<"high">> -> high;
        <<"true">> -> high;
        %off values:
        0 -> low;
        off -> low;
        low -> low;
        false -> low;
        <<"0">> -> low;
        <<"off">> -> low;
        <<"OFF">> -> low;
        <<"Off">> -> low;
        <<"low">> -> low;
        <<"false">> -> low;
        %fallback
        _ -> ok %do nothing
    end.

level_reverse(State) ->
    case State of
        high -> low;
        low -> high
    end.


myatom_to_binary(X) ->
    case X of
        on -> <<"on">>;
        off -> <<"off">>;
        cool -> <<"cool">>;
        fan_only -> <<"fan_only">>;
        energy_saver -> <<"energy_saver">>;
        safe -> <<"safe">>;
        wait -> <<"wait">>;
        alarm -> <<"alarm">>;
        ready -> <<"ready">>;
        not_ready -> <<"not_ready">>;
        mqtt_not_ready -> <<"mqtt_not_ready">>;
        local -> <<"local">>;
        remote -> <<"remote">>;
        low -> <<"low">>;
        high -> <<"high">>;
        true -> <<"true">>;
        false -> <<"false">>;
        yes -> <<"yes">>;
        no -> <<"no">>;
        input -> <<"input">>;
        output -> <<"output">>;
        error -> <<"error">>;
        default -> <<"default">>
    end.

convert_to_binary(X) -> %try to convert anything to a string printable binary
    if
        is_binary(X) -> X;
        %is_atom(X) -> atom_to_binary(X); %atom_to_binary DOESN'T WORK!! (It crashes.)
        is_atom(X) -> myatom_to_binary(X);
        is_tuple(X) -> list_to_binary(io_lib:format("~p", [X]));
        is_float(X) -> float_to_binary(X, [{decimals, ?FLOAT_DECIMAL_LIMIT}]);
        is_integer(X) -> integer_to_binary(X);
        is_list(X) ->
            try
                list_to_binary(X)
            catch _ ->
                try
                    list_to_binary(io_lib:format("~p", [X]))
                catch _ ->
                    case X of
                        [Y|_] -> convert_to_binary(Y);
                        _ -> <<"">>
                    end
                end
            end;
        true -> <<"">>
    end.

make_float(X) -> %Give back a float best you can from whatever input
    if
        X == [] -> 0.0;
        is_float(X) -> X;
        is_integer(X) -> X/1; %float(X) DOESN'T WORK, but division by one does.
        is_list(X) -> try % "68" "68.0" "abc"
                          make_float(list_to_binary(X))
                      catch _:_ ->
                                [Y|_]=X,
                                make_float(Y)
                      end;
        is_binary(X) -> try binary_to_float(X)
                        catch _:_ ->
                                  try binary_to_integer(X)
                                  catch _:_ -> 0.0
                                  end
                        end;
        true -> 0.0
    end.

make_int(X) -> make_integer(X).
make_integer(X) -> %Give back an int best you can from whatever input
    if
        is_integer(X) -> X;
        is_float(X) -> trunc(X);
        X == [] -> 0;
        is_list(X) -> try % "68" "68.0" "abc"
                          make_int(list_to_binary(X))
                      catch _:_ ->
                                [Y|_]=X,
                                make_int(Y)
                      end;
        is_binary(X) -> try binary_to_integer(X)
                        catch _:_ ->
                                  try trunc(binary_to_float(X))
                                  catch _:_ -> 0
                                  end
                        end;
        true -> 0
    end.

%-spec to_strip_plus(kz_term:ne_binary()) -> kz_term:ne_binary().
%to_strip_plus(Number) ->
%    case normalize(Number) of
%        <<$+,N/binary>> -> N;
%        DID -> DID
%    end.

% ->  <<"sofia/", ?SIP_INTERFACE, "/", Contact/binary>>

