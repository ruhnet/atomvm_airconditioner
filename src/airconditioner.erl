%%
%% Copyright (c) 2024 RuhNet
%% All rights reserved.
%%
%% Licensed under the GPL v3.
%%

-include("app.hrl").

-module(?APPNAME).
-behaviour(supervisor).

-export([start/0]).
-export([init/1]).

-define(SERVER, ?MODULE).

start() ->
    io:format("========================================~n"),
    io:format("==== [ RuhNet - https://ruhnet.co ] ====~n"),
    io:format("========================================~n"),
    supervisor:start_link({local, ?SERVER}, ?MODULE, []),
    timer:sleep(infinity).
    %%% if this supervisor dies, since it is linked to this main process it
    %%% will die too, and trigger a restart of the device (IF you have set
    %%% the auto-restart on exit in your AtomVM compile config.)

init([]) ->
    io:format("Starting supervisor '~p' with ~p/~p...~n", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY]),
    setup_pins(),
    util:beep(220, 200),
    util:beep(440, 600),
    util:beep(180, 100),
    util:beep(440, 200),
    util:beep(180, 50),
    %ok = ledc_pwm:start(),

    MaxRestarts = 5, % Kill everyone and die if more than MaxRestarts failures per MaxSecBetweenRestarts seconds
    MaxSecBetweenRestarts = 10,
    %Worker = {led, {led, start_link, []}, permanent, 2000, worker, [led]},
    Debugger = worker(debugger, start_link, []),
    Thermostat = worker(thermostat, start_link, []),
    TempReader = worker(temperature, start_link, []),
    MainControl = worker(control, start_link, []),
    NetworkSup = supervisor(network_sup, []),
    %LedControl = worker(led, start_link, []),
    %ButtonWatcher = worker(button_watcher, start_link, []),

    {ok, {{one_for_one, MaxRestarts, MaxSecBetweenRestarts}, [
                                                              Debugger
                                                              %,LedControl
                                                              ,TempReader
                                                              ,Thermostat
                                                              ,MainControl
                                                              %,ButtonWatcher
                                                              ,NetworkSup
                                                             ] }}.

%Create a worker spec:
worker(Name, StartFunc, Args) ->
    {Name, {Name, StartFunc, Args}, permanent, brutal_kill, worker, [Name]}.

supervisor(Name, Args) ->
    {Name, {Name, start_link, Args}, permanent, brutal_kill, supervisor, [Name]}.

setup_pins() ->
    io:format("Setting pin modes...~n"),
    setup_pins(?OUTPUT_PINS, output),
    setup_pins(?INPUT_PINS, input).
setup_pins([Pin|RemainingPins], Mode) ->
    gpio:set_pin_mode(Pin, Mode),
    %gpio:set_direction(GPIO, Pin, Mode), %gpio:start() first for Pid of GPIO
    case Mode of
        output ->
            case lists:member(Pin, ?GENERIC_OUTPUTS) of %check if this pin is a generic output
                true ->
                    case ?GENERIC_OUTPUT_ACTIVE_LOW of
                        true -> util:set_output(Pin, high); %turn active low generic outputs OFF by setting high.
                        _ -> ok
                    end;
                _ -> ok
            end;
        _ -> ok
    end,
    setup_pins(RemainingPins, Mode);
setup_pins([], _Mode) ->
    ok.

