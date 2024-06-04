%%
%% Copyright (c) 2024 RuhNet
%% All rights reserved.
%%
%% Licensed under the GPL v3.
%%

-include("app.hrl").

-module(led).
%-behavior(gen_server).

-export([flash/0, flash/1, flash/2, flash/3, flash_led/3, set_status_led/1]).
%-export([init/1, handle_call/3, handle_info/2, terminate/2]).
%-export([start_link/0, init/1, handle_call/3, handle_cast/2, terminate/2]).
%
%start_link() ->
%    io:format("Starting '~p' with ~p/~p...~n", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY]),
%    {ok, _Pid} = gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
%    %timer:sleep(1).
%
%init(_) ->
%    io:format("[~p:~p] Starting...~n", [?MODULE, ?FUNCTION_NAME]),
%    flash_led(?STATUS_LED, 50, 20),
%    util:set_output(?STATUS_LED, on),
%    {ok, []}.
%
%handle_call(init, _From, State) ->
%    {reply, ok, State};
%handle_call({flash, Pin, Interval, Times}, _From, State) ->
%    _Pid = spawn(fun() -> flash_led(Pin, Interval, Times) end),
%    %{reply, ok, [Pid|State]};
%    {reply, ok, State};
%handle_call(listproc, _From, State) ->
%    io:format("Processes: ~p ~n", [State]),
%    {reply, ok, State};
%handle_call(reset, _From, State) ->
%    io:format("Processes: ~p ~n", [State]),
%    kill_flashers(State),
%    {reply, ok, []};
%handle_call(Call, _From, State) ->
%    erlang:display(Call),
%    {reply, ok, State}.
%
%handle_cast(Msg, State) ->
%    erlang:display(Msg),
%    {noreply, State}.
%
%%handle_info({gpio_interrupt, 26}, SPI) ->
%%    handle_irq(SPI),
%%    {noreply, SPI}.
%
%
%terminate(_Reason, _State) ->
%    ok.
%
%kill_flashers(PidList) ->
%    case PidList of
%        [Pid|Remainder] -> exit(Pid, kill),
%            kill_flashers(Remainder);
%        [] -> ok;
%        _ -> ok
%    end.


flash() ->
    flash(?STATUS_LED, 1000, forever).
flash(Pin) ->
    flash_led(Pin, 1000, forever).
%    gen_server:call(?MODULE, {flash, Pin, 1000, forever}).
flash(Pin, Interval) ->
    io:format("Flashing Pin ~p FOREVER with interval ~p ms.~n", [Pin, Interval]),
    flash_led(Pin, Interval, forever).
%    gen_server:call(?MODULE, {flash, Pin, Interval, forever}).
flash(Pin, Interval, Times) ->
    io:format("Flashing Pin ~p ~p times with interval ~p ms.~n", [Pin, Times, Interval]),
    flash_led(Pin, Interval, Times).
%    gen_server:call(?MODULE, {flash, Pin, Interval, Times}).

flash_led(_Pin, _Interval, 0) ->
    ok;
flash_led(Pin, Interval, forever) ->
    flash_led(Pin, Interval, 1),
    flash_led(Pin, Interval, forever);
flash_led(Pin, Interval, Times) ->
    util:set_output(Pin, on),
    timer:sleep(Interval),
    util:set_output(Pin, off),
    timer:sleep(Interval),
    flash_led(Pin, Interval, Times-1).

set_status_led(Mode) ->
    led:flash_led(?STATUS_LED, 50, 3),
    case Mode of
        off ->
            util:set_output(?STATUS_LED, off),
            util:set_output(?STATUS_LED2, off);
        on ->
            util:set_output(?STATUS_LED, on),
            util:set_output(?STATUS_LED2, off);
        cool ->
            util:set_output(?STATUS_LED, on),
            util:set_output(?STATUS_LED2, off);
        energy_saver ->
            util:set_output(?STATUS_LED, on),
            util:set_output(?STATUS_LED2, on);
        fan_only ->
            util:set_output(?STATUS_LED, off),
            util:set_output(?STATUS_LED2, on);
        _ ->
            util:set_output(?STATUS_LED, off),
            util:set_output(?STATUS_LED2, off)
    end.



