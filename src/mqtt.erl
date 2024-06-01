%%
%% Copyright (c) 2024 RuhNet
%% All rights reserved.
%%
%% Licensed under the GPL v3.
%%

-module(mqtt).
-behavior(gen_server).

%-export([start/0]).
-export([start_link/0, init/1, handle_call/3, handle_cast/2, terminate/2]).
-export([publish/2, publish/3, publish_and_forget/2, subscribe_remote_temp/1, unsubscribe/1]).

-include("app.hrl").

start_link() ->
    io:format("Starting '~p' with ~p/~p...~n", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY]),
    {ok, _Pid} = gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
    %{ok, _Pid} = init([]).

init(_) ->
    io:format("Starting '~p' with ~p/~p...~n", [mqtt_client, start_link, 1]),
    %{ok, {no_mqtt_pid, not_ready}}.
    My_Pid = self(),
    {ok, {My_Pid, not_ready}}.
    %{ok, MQTT_PID}.

start_mqtt_client() ->
    Config = maps:get(mqtt, config:get()),
    MQTTConfig = #{
        url => maps:get(url, Config),
        client_id => ?DEVICENAME,
        disconnected_handler => fun(_MQTT_CLIENT_PID) -> io:format("yoyo disconnected from mqtt!!!!!!~n"), mqtt_client:reconnect(whereis(mqtt_client)) end,
        error_handler => fun(_MQTT_CLIENT_PID, Err) -> io:format("dah mqtt error_handler: ~p~n", [Err]) end,
        connected_handler => fun handle_connected/1
    },
    io:format("Starting 'mqtt_client'...~n"),
    {ok, _MQTT_PID} = mqtt_client:start_link({local, mqtt_client}, MQTTConfig).

handle_call(start_client, _From, {_, _ReadyStatus}) ->
    io:format("MQTT Controller received 'start_client' message from 'wifi' after obtaining IP address; starting 'mqtt_client'...~n"),
    {ok, MQTT_PID} = start_mqtt_client(),
    {reply, ok, {MQTT_PID, not_ready}};
handle_call({ready, MQTT_PID}, _From, {_, _ReadyStatus}) ->
    {reply, ok, {MQTT_PID, ready}};
handle_call({not_ready, MQTT_PID}, _From, {_, _ReadyStatus}) ->
    {reply, ok, {MQTT_PID, not_ready}};
handle_call({publish, Topic, Message}, _From, State) ->
    Reply = gen_server:call(?MODULE, {publish, Topic, default_qos, Message}),
    {reply, Reply, State};
handle_call({publish, Topic, QoS, Message}, _From, State={_MQTT_PID, ReadyStatus}) ->
    case ReadyStatus of
        ready ->
            publish_message(Topic, QoS, Message),
            {reply, ok, State};
        _ -> {reply, mqtt_not_ready, State}
    end;
handle_call(get_pid, _From, State={MQTT_PID, _ReadyStatus}) ->
    {reply, MQTT_PID, State};
handle_call(get, _From, State={_MQTT_PID, _ReadyStatus}) ->
    {reply, State, State};
handle_call(Msg, From, State) ->
    io:format("MQTT Controller received unknown message ~p from ~p~n", [Msg, From]),
    {reply, ok, State}.

handle_cast({publish, Topic, Message}, State={_MQTT_PID, ReadyStatus}) -> %Fire-and-forget publish with no response
    case ReadyStatus of
        ready -> spawn(publish_and_forget(Topic, Message) );
        _ -> ReadyStatus
    end,
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.


ac_on() ->
    io:format("Turning on AC.~n", []),
    util:set_output(?FAN3, on),
    util:set_output(?COMPRESSOR, on),
    util:set_output(?STATUS_LED, on),
    publish_message(?TOPIC_AC, <<"AC ON">>).

compressor_off() ->
    io:format("Turning off compressor.~n", []),
    util:set_output(?COMPRESSOR, off),
    publish_message(?TOPIC_AC, <<"COMPRESSOR OFF">>).

compressor_on() ->
    io:format("FORCE Turning ON compressor.~n", []),
    util:set_output(?COMPRESSOR, on),
    publish_message(?TOPIC_AC, <<"COMPRESSOR OFF">>).

all_off() ->
    io:format("Turning off compressor.~n", []),
    util:set_output(?FAN3, off),
    util:set_output(?FAN2, off),
    util:set_output(?FAN1, off),
    util:set_output(?COMPRESSOR, off),
    publish_message(?TOPIC_AC, <<"ALL OFF">>).


publish(Topic, Message) ->
    publish(Topic, default_qos, Message).
publish(Topic, QoS, Message) ->
    publish_message(Topic, QoS, Message).
    %gen_server:call(?MODULE, {publish, Topic, QoS, Message}).

publish_and_forget(Topic, Message) ->
    publish_message(Topic, at_most_once, Message).
    %gen_server:cast(?MODULE, {publish, Topic, at_most_once, Message}).

handle_connected(MQTT) ->
    Config = mqtt_client:get_config(MQTT),
    debugger:format("[~p:~p] MQTT started and connected to ~p~n", [?MODULE, ?FUNCTION_NAME, maps:get(url, Config)]),
    gen_server:call(mqtt, {ready, MQTT}),
    subscribe_to_topic_list(MQTT, get_topics()).

subscribe_to_topic(MQTT, Topic, SubHandleFunc, DataHandleFunc) ->
    debugger:format("Subscribing to ~p...~n", [Topic]),
    case mqtt_client:subscribe(MQTT, util:convert_to_binary(Topic), #{
        %subscribed_handler => fun handle_subscribed/2,
        %data_handler => fun handle_data/3
        subscribed_handler => SubHandleFunc,
        data_handler => DataHandleFunc
    }) of
        ok -> ok;
        _ -> io:format("MQTT Subscribe Failed! KILLING MQTT CLIENT ~p. My PID: ~p~n", [MQTT, self()]),
             exit(MQTT)
    end.

subscribe_to_topic_list(MQTT, Topics) ->
    case Topics of
        [{Topic, SubHandleFunc, DataHandleFunc}|Remaining] ->
            subscribe_to_topic(MQTT, Topic, SubHandleFunc, DataHandleFunc),
            subscribe_to_topic_list(MQTT, Remaining);
        _ -> debugger:format("Done subscribing to MQTT topics.~n")
    end.

get_topics() ->
    [
        {?TOPIC_AC, fun handle_subscribed/2, fun handle_data/3}
        ,{?TOPIC_THERMOSTAT, fun handle_subscribed_thermostat/2, fun handle_data_thermostat/3}
        ,{?TOPIC_OUT1, fun handle_subscribed/2, fun handle_data_output/3}
        ,{?TOPIC_FAN, fun handle_subscribed/2, fun handle_data_fan/3}
    ].

handle_subscribed(_MQTT, Topic) ->
    debugger:format("Subscribed to topic: ~p.~n", [Topic]).

unsubscribe(Topic) ->
    {MQTT_PID, _ReadyStatus} = gen_server:call(?MODULE, get),
    UnsubHandlerFunc = fun(_MQTT, UnsubTopic) -> debugger:format("Unsubscribed from topic feed: ~p ~n", [UnsubTopic]) end,
    debugger:format("[mqtt:unsubscribe] Running mqtt:unsubscribe in mqtt.erl to mqtt_client ~p on topic: ~p~n",[MQTT_PID, Topic]),
    mqtt_client:unsubscribe(MQTT_PID, util:convert_to_binary(Topic), #{unsubscribed_handler => UnsubHandlerFunc}).

subscribe_remote_temp(Topic) ->
    {MQTT_PID, ReadyStatus} = gen_server:call(?MODULE, get),
    case ReadyStatus of
        ready -> subscribe_to_topic(MQTT_PID, Topic, fun handle_subscribed/2, fun handle_data_remote_temp/3);
        _ -> ReadyStatus
    end.

handle_data_remote_temp(_MQTT, Topic, Data) ->
    debugger:format("[~p:~p/~p] remote temperature [~p] received from ~p~n", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY, Data, Topic]),
    temperature:set_remote_temperature(Data).

handle_subscribed_thermostat(_MQTT, Topic) ->
    debugger:format("Subscribed to topic: ~p.~n", [Topic]), %,
    debugger:format("Spawning thermostat setpoint publish loop on topic ~p~n", [?TOPIC_THERMOSTAT_SET]),
    spawn(fun() -> publish_thermostat_loop(?THERMOSTAT_PUB_INTERVAL_SEC * 1000) end).

handle_data(_MQTT, Topic, Data) ->
    debugger:format("[~p:~p/~p] received data on topic ~p: ~p ~n", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY, Topic, Data]),
    case Data of
        <<"flash">> -> spawn(fun() -> led:flash(?STATUS_LED, 100, 20) end);
        <<"flash2">> -> spawn(fun() -> led:flash(?STATUS_LED2, 300, 10) end);
        <<"flash 10">> -> spawn(fun() -> led:flash(?STATUS_LED, 200, 10) end);
        <<"flash forever">> -> spawn(fun() -> led:flash(?STATUS_LED, 200, forever) end);
        <<"listproc">> -> gen_server:call(led, listproc);
        <<"reset_led">> -> gen_server:call(led, reset);
        <<"beep">> -> spawn(fun() -> util:beep(440, 1000) end);
        <<"beep ", F/binary>> -> spawn(fun() -> util:beep(util:make_int(F), 1000) end);
        %%%
        <<"ac_on">> -> ac_on();
        <<"all_off">> -> all_off();
        <<"compressor_off">> -> compressor_off();
        <<"force_compressor_on">> -> compressor_on();
        %<<"coiltemp ", T/binary>> -> control:set_coil_templimit(util:make_int(T));
        %%%
        <<"sysinfo">> -> system_info:start();
        <<"uptime">> -> publish_message(?TOPIC_DEBUG, util:uptime());
        <<"debug">> -> debugger:enable(); %crashes after a few minutes
        <<"nodebug">> -> debugger:disable();
        <<"debug_mqtt_only">> -> debugger:mqtt_only();
        <<"debug_console_only">> -> debugger:console_only();
        %%%
        <<"off">> -> control:set_mode(off);
        <<"on">> -> control:set_mode(cool);
        <<"cool">> -> control:set_mode(cool);
        <<"fan_only">> -> control:set_mode(fan_only);
        <<"energy_saver">> -> control:set_mode(energy_saver);
        <<"mode_cycle">> -> control:cycle_mode();
        <<"fan_cycle">> -> control:cycle_fan();
        <<"fan ", F/binary>> -> control:set_fan(util:make_int(F));
        <<"temp_source ", TempSrc/binary>> -> temperature:set_source(TempSrc);
        <<"safe">> -> control:set_safe();
        <<"reset">> -> all_off(), esp:restart();
        <<"reboot">> -> all_off(), esp:restart();
        %%% Timer
        <<"timer_h off ", T/binary>> -> mode_timer(off, T*3600); %hours timer
        <<"timer_m off ", T/binary>> -> mode_timer(off, T*60); %minutes timer
        <<"timer_s off ", T/binary>> -> mode_timer(off, T); %seconds timer
        <<"timer off ", T/binary>> -> mode_timer(off, T);   %default seconds timer
        <<"timer_h cool ", T/binary>> -> mode_timer(cool, T*3600); %hours timer
        <<"timer_m cool ", T/binary>> -> mode_timer(cool, T*60); %minutes timer
        <<"timer_s cool ", T/binary>> -> mode_timer(cool, T); %seconds timer
        <<"timer cool ", T/binary>> -> mode_timer(cool, T);   %default seconds timer
        <<"timer_h on ", T/binary>> -> mode_timer(cool, T*3600); %hours timer
        <<"timer_m on ", T/binary>> -> mode_timer(cool, T*60); %minutes timer
        <<"timer_s on ", T/binary>> -> mode_timer(cool, T); %seconds timer
        <<"timer on ", T/binary>> -> mode_timer(cool, T);   %default seconds timer
        <<"timer_h energy_saver ", T/binary>> -> mode_timer(cool, T*3600); %hours timer
        <<"timer_m energy_saver ", T/binary>> -> mode_timer(cool, T*60); %minutes timer
        <<"timer_s energy_saver ", T/binary>> -> mode_timer(cool, T); %seconds timer
        <<"timer energy_saver ", T/binary>> -> mode_timer(cool, T);   %default seconds timer
        <<"timer_h fan_only ", T/binary>> -> mode_timer(fan_only, T*3600); %hours timer
        <<"timer_m fan_only ", T/binary>> -> mode_timer(fan_only, T*60); %minutes timer
        <<"timer_s fan_only ", T/binary>> -> mode_timer(fan_only, T); %seconds timer
        <<"timer fan_only ", T/binary>> -> mode_timer(fan_only, T);   %default seconds timer
%        <<"timer_h ", Mode/binary, " ", T/binary>> -> %hours timer
%            TimeMs = util:make_int(T) * 3600 * 1000,
%            erlang:send_after(TimeMs, control, {set_mode, Mode});
%        <<"timer_m ", Mode/binary, " ", T/binary>> -> %minutes timer
%            TimeMs = util:make_int(T) * 60 * 1000,
%            erlang:send_after(TimeMs, control, {set_mode, Mode});
%        <<"timer_s ", Mode/binary, " ", T/binary>> -> %seconds timer
%            TimeMs = util:make_int(T) * 1000,
%            erlang:send_after(TimeMs, control, {set_mode, Mode});
%        <<"timer ", Mode/binary, " ", T/binary>> -> %default seconds timer
%            TimeMs = util:make_int(T) * 1000,
%            erlang:send_after(TimeMs, control, {set_mode, Mode});
            %TimeMs = case binary:last(T) of
            %    104 ->  %h
            %    72 ->  %H
            %    109 ->  %m
            %    77 ->  %M
            %    115 ->  %s
            %    83 ->  %S
            %end,
        %%%
        _ -> util:set_output(?STATUS_LED, Data)
    end.

handle_data_thermostat(_MQTT, Topic, Data) ->
    debugger:format("[~p:~p/~p] received data on topic ~p: ~p ~n", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY, Topic, Data]),
    case Data of
        <<"+">> -> thermostat:up();
        <<"up">> -> thermostat:up();
        <<"-">> -> thermostat:down();
        <<"down">> -> thermostat:down();
        <<"show">> ->
            Res = thermostat:get_thermostat(),
            io:format("Thermostat: ~p~n", [Res]),
            publish_message(?TOPIC_THERMOSTAT_SET, Res);
        <<"span ", S/binary>> -> thermostat:set_span(S);
        <<"save">> -> thermostat:save();
        <<"load">> -> thermostat:load();
        <<"default">> -> thermostat:default();
        %%% Timer
        <<"timer_h ", Temp:2/binary, " ", T/binary>> -> thermostat_timer(Temp, util:make_int(T) * 3600); %hours timer
        <<"timer_m ", Temp:2/binary, " ", T/binary>> -> thermostat_timer(Temp, util:make_int(T) * 60); %minutes timer
        <<"timer_s ", Temp:2/binary, " ", T/binary>> -> thermostat_timer(Temp, util:make_int(T)); %seconds timer
        <<"timer ", Temp:2/binary, " ", T/binary>> -> thermostat_timer(Temp, util:make_int(T)); %seconds timer
        %%%
        _ -> thermostat:set_temp(Data),
             publish_message(?TOPIC_THERMOSTAT_SET, Data)
    end.

mode_timer(Mode, TimeSec) ->
    T = util:make_int(TimeSec),
    spawn(fun() ->
        debugger:format("Setting mode to ~p via timer for ~p seconds from now...~n", [Mode, T]),
        erlang:send_after(T * 1000, control, {set_mode, Mode}),
        debugger:format("Changing mode to ~p via timer after ~p seconds!~n", [Mode, T])
    end).


thermostat_timer(Temp, TimeSec) ->
    T = util:make_int(TimeSec),
    spawn(fun() ->
        debugger:format("Setting thermostat ~p timer for ~p seconds from now...~n", [Temp, T]),
        erlang:send_after(T * 1000, thermostat, {set_temp, util:make_int(Temp)}),
        debugger:format("Set thermostat to ~p with timer after ~p seconds!~n", [Temp, T])
    end).



handle_data_fan(_MQTT, Topic, Data) ->
    debugger:format("[~p:~p/~p] received data on topic ~p: ~p ~n", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY, Topic, Data]),
    case Data of
        <<"cycle">> -> control:cycle_fan();
        <<"1">> -> control:set_fan(1);
        <<"2">> -> control:set_fan(2);
        <<"3">> -> control:set_fan(3);
        F -> control:set_fan(util:make_int(F))
    end.

%handle_data_output(_MQTT, Topic = <<"barf/out", X/binary>>, Data) ->
handle_data_output(_MQTT, Topic, Data) ->
    debugger:format("~p/~p received data on topic ~p: ~p ~n", [?FUNCTION_NAME, ?FUNCTION_ARITY, Topic, Data]),
    %binary:last gives the last byte of a binary as an integer (ASCII value in this case). Subtract 48 to get the output number. :)
    Output = binary:last(Topic)-48,
    Pin = lists:nth(Output, ?GENERIC_OUTPUTS), %select the output pin from the ?GENERIC_OUTPUTS define list.
    SetOutFunc = case ?GENERIC_OUTPUT_ACTIVE_LOW of
                     true -> fun util:set_output_activelow/2;
                     _ -> fun util:set_output/2
                 end,
    SetOutFunc(Pin, Data).

publish_thermostat_loop(Interval) ->
    [{temp, Therm}|_] = thermostat:get_thermostat(),
    publish_and_forget(?TOPIC_THERMOSTAT_SET, Therm),
    timer:sleep(Interval),
    publish_thermostat_loop(Interval).

publish_message(Topic, Data) ->
    publish_message(Topic, default_qos, Data).
publish_message(Topic, QoS, Data) ->
    publish_message(Topic, QoS, Data, 10000).

publish_message(Topic, QoS, Data, Timeout) ->
    try
        %io:format("Publishing data '~p' to topic ~p and mqtt_client pid ~p from my Pid ~p mqtt pid:~p ~n", [Data, Topic, whereis(mqtt_client), Self, whereis(mqtt)]),
        io:format("MQTT Publishing '~p' to topic ~p~n", [Data, Topic]),
        MQTT_CLIENT = whereis(mqtt_client),
        Self = self(),
        HandlePublished = fun(MQTT2, Topic2, MsgId) ->
            %io:format("published_handler about to send pub message to PID: ~p mqtt pid ~p ~n", [Self, whereis(mqtt)]),
            Self ! published,
            handle_published(MQTT2, Topic2, MsgId)
        end,
        PublishOptions = #{qos => qos(QoS), published_handler => HandlePublished},
        Msg = util:convert_to_binary(Data),
        _ = mqtt_client:publish(MQTT_CLIENT, util:convert_to_binary(Topic), Msg, PublishOptions),
        case qos(QoS) of
            at_most_once -> ok; %don't wait for confirmation message as it won't be sent!
            _ ->
                receive
                    published ->
                        ok;
                    MessageRX -> io:format("MQTT received something else besides 'published': ~p~n", [MessageRX])
                after Timeout ->
                    io:format("Timed out waiting for publish ack~n")
                end
        end
    catch
        C:E:S ->
            io:format("Error in publish: ~p:~p~p~n", [C, E, S])
    end.

handle_published(MQTT, Topic, MsgId) ->
    io:format("MQTT client ~p published message (with acknoledgement) to topic ~p msg_id=~p~n", [MQTT, Topic, MsgId]).

qos(QoS) -> %allow invalid QoS value to be accepted and set to 'at_least_once'
    case QoS of
        at_least_once -> at_least_once;
        at_most_once -> at_most_once;
        exactly_once -> exactly_once;
        %_ -> at_least_once %this is the default
        _ -> at_most_once %this is the default
    end.


