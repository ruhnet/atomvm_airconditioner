%%
%% Copyright (c) 2024 RuhNet
%% All rights reserved.
%%
%% Licensed under the GPL v3.
%%

-include("app.hrl").

-module(temperature).
-behavior(gen_server).

-export([get_temperature/0, set_remote_temperature/1, set_source/1]).
-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

start_link() ->
    debugger:format("Starting ~p with ~p/~p...~n", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY]),
    {ok, _Pid} = gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init(_) ->
    debugger:format("[~p:~p/~p] Reading initial temperatures from thermistors on ~p and ~p...~n", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY, ?THERMISTOR1, ?THERMISTOR2]),
    {ok, ADC_T1_PID} = adc:start(?THERMISTOR1),
    {ok, ADC_TCOIL_PID} = adc:start(?THERMISTOR2),
    TempSource = format_source(esp:nvs_get_binary(?NVS_NAMESPACE, temp_source, <<"local">>)),
    TempLocal = read_temp(ADC_T1_PID, thermistor1, 0.0),
    TempCoil = read_temp(ADC_TCOIL_PID, coil_thermistor, 0.0),
    erlang:send(self(), {subscribe_remote_temp, TempSource}),
    erlang:send_after(5000, self(), {tempread_loop, ADC_T1_PID, ADC_TCOIL_PID}),
    {ok, [{temp, TempLocal}, {coiltemp, TempCoil}, {templocal, TempLocal}, {tempremote, -1.0}, {tempsrc, TempSource}] }.


handle_info({subscribe_remote_temp, TempSource}, State) ->
    case TempSource of
        local -> ok; %do nothing for local
        _ -> debugger:format("[~p:~p] subscribe_remote_temp attempting subscribe to remote source...~n", [?MODULE, ?FUNCTION_NAME]),
            case whereis(mqtt) of
                undefined ->
                    debugger:format("'mqtt' is not yet started, trying again later.~n"),
                    erlang:send_after(10000, self(), {subscribe_remote_temp, TempSource});
                _Pid -> case gen_server:call(mqtt, get) of
                            {_, ready} ->
                                mqtt:subscribe_remote_temp(TempSource);
                            _ ->
                                debugger:format("'mqtt' is running, but not ready, trying again later.~n"),
                                erlang:send_after(10000, self(), {subscribe_remote_temp, TempSource})
                        end
            end
    end,
    {noreply, State};

handle_info({tempread_loop, ADC_T1, ADC_TCOIL}, [_, {coiltemp, TCoil}, {templocal, TLocal}, {tempremote, TRemote}, {tempsrc, TSrc}]) ->
    T1 = read_temp(ADC_T1, thermistor1, TLocal),
    Coil = read_temp(ADC_TCOIL, coil_thermistor, TCoil),
    T = temp_select(T1, TRemote, TSrc),
    %debugger:format("[~p:~p] tempread_loop [T=~.2f, TLocal=~.2f TCoil=~.2f, TRem=~p, TSrc=~p].~n", [?MODULE, ?FUNCTION_NAME, T, T1, Coil, TRemote, TSrc]),
    debugger:format("[~p:~p] tempread_loop [T=~.2f, TLocal=~.2f TCoil=~.2f, TRem=~.2f, TSrc=~p].~n", [?MODULE, ?FUNCTION_NAME, T, T1, Coil, TRemote, TSrc]),
    erlang:send_after(15000, self(), {tempread_loop, ADC_T1, ADC_TCOIL}),
    {noreply, [{temp, T}, {coiltemp, Coil}, {templocal, T1}, {tempremote, TRemote}, {tempsrc, TSrc}] }.

%set remote temperature from external source
handle_call({set_remote, TRemoteInput}, _From, [{temp, _}, {coiltemp, Coil}, {templocal, TLocal}, {tempremote, _}, {tempsrc, TSrc}]) ->
    TRemote = util:make_float(TRemoteInput),
    T = temp_select(TLocal, TRemote, TSrc),
    {reply, ok, [{temp, T}, {coiltemp, Coil}, {templocal, TLocal}, {tempremote, TRemote}, {tempsrc, TSrc}] };

%set external source
handle_call({set_source, Src}, _From, [{temp, _T}, {coiltemp, Coil}, {templocal, TLocal}, {tempremote, TRemote}, {tempsrc, OldSrc}]) ->
    Source = change_source(Src, OldSrc),
    T = temp_select(TLocal, TRemote, Source),
    {reply, ok, [{temp, T}, {coiltemp, Coil}, {templocal, TLocal}, {tempremote, TRemote}, {tempsrc, Source}] };

handle_call(get, _From, State) ->
    {reply, State, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.


read_temp(ADC, Label, ErrDefaultVal) ->
    case adc:read(ADC) of
        {ok, {Raw, MilliVolts}} ->
            debugger:format("[~p:~p] Read values from ADC ~p ~p: [Raw: ~p Voltage: ~pmV]~n", [?MODULE, ?FUNCTION_NAME, ADC, Label, Raw, MilliVolts]),
            %MilliVolts/1000;
            convert_reading_to_F(MilliVolts);
        Error ->
            debugger:format("[~p:~p] Error taking reading from ADC ~p ~p: ~p~n", [?MODULE, ?FUNCTION_NAME, ADC, Label, Error]),
            ErrDefaultVal
    end.

get_temperature() ->
    gen_server:call(?MODULE, get).

set_remote_temperature(T) -> %set the remote temperature from MQTT or external source.
    gen_server:call(?MODULE, {set_remote, T}).
%    if
%        is_float(T) -> gen_server:call(?MODULE, {set_remote, T});
%        is_integer(T) -> gen_server:call(?MODULE, {set_remote, float(T)}); %% FUNCTION float/1 DOESN'T WORK!
%        true -> gen_server:call(?MODULE, {set_remote, -1.0})
%    end.

set_source(Src) ->
    gen_server:call(?MODULE, {set_source, Src}).

change_source(NewSrc, OldSrc) ->
    BNewSrc = util:convert_to_binary(NewSrc),
    BOldSrc = util:convert_to_binary(OldSrc),
    if
        BNewSrc == BOldSrc -> %Don't write to NVS or subscribe/unsubscribe if source is unchanged.
            debugger:format("[~p:~p] Temp source is unchanged, keeping old.~n", [?MODULE, ?FUNCTION_NAME]),
            OldSrc;
        true ->
            Unsubscribed = case OldSrc of
                local -> ok;
                _ ->
                    debugger:format("[~p:~p] Unsubscribing from old source: ~p~n",[?MODULE, ?FUNCTION_NAME, OldSrc]),
                    mqtt:unsubscribe(OldSrc)
            end,
            case NewSrc of %new source is 'local' or a topic?
                local -> save_source(local);
                <<"local">> -> save_source(local);
                _ -> case Unsubscribed of
                        ok ->
                             debugger:format("[~p:~p] We are unsubscribed from old source ~p. Subscribing to new: ~p~n",[?MODULE, ?FUNCTION_NAME, OldSrc, NewSrc]),
                             case mqtt:subscribe_remote_temp(NewSrc) of
                                ok -> save_source(NewSrc); %subscription was successful, so save only then
                                Error -> Error
                             end;
                        _ -> OldSrc %revert to old source since we are still subscribed to it!
                     end
            end
    end.

save_source(Src) ->
    case Src of
        local ->
            esp:nvs_set_binary(?NVS_NAMESPACE, temp_source, <<"local">>),
            local;
        Topic ->
            esp:nvs_set_binary(?NVS_NAMESPACE, temp_source, util:convert_to_binary(Topic)),
            Topic
    end.

format_source(<<SrcBinary/binary>>) ->
    case SrcBinary of
        <<"local">> -> local;
        _ -> SrcBinary
    end.

temp_select(TLocal, TRemote, TSrc) ->
    case TSrc of
        local -> TLocal;
        _ -> if
                 TRemote > 0 -> TRemote; %if remote temp is 0 (or less), use local temp until a valid value is received.
                 true -> TLocal
             end
    end.

convert_reading_to_F(MilliVolts) ->
    %MilliVolts/21.5. %cheapo estimation!
    %MilliVolts/15.0. %cheapo estimation!
    0.038 * MilliVolts + 32.806.



