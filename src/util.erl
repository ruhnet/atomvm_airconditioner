%%
%% Copyright (c) 2024 RuhNet
%% All rights reserved.
%%
%% Licensed under the GPL v3.
%%

-include("app.hrl").

-module(util).

-export([ set_output/2, set_output_activelow/2, print_time/0, uptime/0, beep/2, make_int/1, make_float/1, convert_to_binary/1 ]).

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
              true -> trunc((UptimeSec rem (Hours * 3600))/60);
              _ -> trunc(UptimeSec/60)
        end,
    Secs = case (UptimeSec > 60) of
              true -> UptimeSec rem (Mins * 60);
              _ -> UptimeSec
        end,
    {{Y,M,D}, {H,M,S}} = erlang:universaltime(),
    Timestamp = io_lib:format("~p~2..0p~2..0p ~2..0p:~2..0p:~2..0p", [Y, M, D, H, M, S]),
    UptimeMsg = io_lib:format("~p UPTIME: ~p days, ~p hours, ~p minutes, ~p seconds",  [Timestamp, Days, Hours, Mins, Secs]),
    io:format("~p~n", [UptimeMsg]),
    UptimeMsg.


%%% Crude beep/sound functionality
beep(_Freq, _Duration) when (_Duration =< 1) ->
    ok;
beep(Freq, DurationMs) ->
    CyclePeriod = 1000 / Freq, %full cycle is 2 switch time intervals
    gpio:digital_write(?BEEPER, high),
    timer:sleep(trunc(CyclePeriod / 2)),
    gpio:digital_write(?BEEPER, low),
    timer:sleep(trunc(CyclePeriod / 2)),
    beep(Freq, DurationMs - CyclePeriod). %not accurate length, but good enough

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

make_int(X) -> %Give back an int best you can from whatever input
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

