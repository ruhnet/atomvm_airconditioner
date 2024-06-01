%%
%% Copyright (c) 2024 RuhNet
%% All rights reserved.
%%
%% Licensed under the GPL v3.
%%

-include("app.hrl").

-module(wifi).

-export([start_link/0]).

start_link() ->
    Config = [
        {ap, [
            {ap_started, fun ap_started/0},
            {sta_connected, fun sta_connected/1},
            {sta_ip_assigned, fun sta_ip_assigned/1},
            {sta_disconnected, fun sta_disconnected/1}
            | maps:get(ap, config:get())
        ]},
        {sta, [
            {connected, fun connected/0},
            {got_ip, fun got_ip/1},
            {disconnected, fun disconnected/0}
            | maps:get(sta, config:get())
        ]},
        {sntp, [
            {host, "time-d-b.nist.gov"},
            {synchronized, fun sntp_synchronized/1}
        ]}
    ],
    case network:start_link(Config) of
        {ok, _Pid} ->
            debugger:format("Network started.~n"),
            {ok, _Pid};
            %timer:sleep(infinity);
        Error ->
            Error
    end.

ap_started() ->
    debugger:format("AP started.~n").

sta_connected(Mac) ->
    debugger:format("WiFi AP: Station connected with mac ~p~n", [Mac]).

sta_disconnected(Mac) ->
    debugger:format("WiFi AP: Station ~p disconnected~n", [Mac]).

sta_ip_assigned(Address) ->
    debugger:format("WiFi AP: Station assigned address ~p~n", [Address]).

connected() ->
    debugger:format("WiFi Client: connected.~n").

got_ip(IpInfo) ->
    debugger:format("WiFi Client: Using IP address: ~p.~n", [IpInfo]),
%    network_services_sup:start_link(). %We have an IP address, so start our network dependant services supervisor
    case whereis(mqtt) of
        undefined ->
            debugger:format("MQTT CONTROLLER NOT RUNNING??~n");
        _Pid -> gen_server:call(mqtt, start_client)
    end,
    ok.

disconnected() ->
    debugger:format("WiFi Client: disconnected.~n"),
    timer:sleep(10000),
    debugger:format("WiFi [not] killing myself because of disconnection...~n"),
    timer:sleep(1).
    %exit(kill). %kill myself (supervisor will restart) FIXME: is this best way to handle this??

sntp_synchronized({TVSec, TVUsec}) ->
    debugger:format("Synchronized time with SNTP server. TVSec=~p TVUsec=~p~n", [TVSec, TVUsec]),
    util:print_time(),
    debugger:format("Updating system boot time..."),
    debugger:set_boot_time().

