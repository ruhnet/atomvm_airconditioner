%%
%% Copyright (c) 2024 RuhNet
%% All rights reserved.
%%
%% Licensed under the GPL v3.
%%

-define(APPNAME, airconditioner).

-define(DEVICENAME, "greenwood_AC1").
-define(NVS_NAMESPACE, ac).

-define(DEBUG_ENABLED_BY_DEFAULT, console_only). % true|false|console_only|mqtt_only

%PINS/PORTS/PERIPHERALS
-define(COMPRESSOR_LED, 2).    %
-define(STATUS_LED, 0).        %
-define(STATUS_LED2, 33).      %
-define(COMPRESSOR, 4).        %
-define(BEEPER, 5).            %VSPI
-define(FAN1, 25).             %
-define(FAN2, 26).             %
-define(FAN3, 27).             %
-define(OUT1, 23).             %VSPI
%-define(OUT2, 33).             %ADC1 CH5
%-define(THERMISTOR4, 33).      %ADC1 CH5
-define(THERMISTOR3, 32).      %ADC1 CH4
-define(THERMISTOR1, 34).      %ADC1 CH6 INPUT ONLY
-define(THERMISTOR2, 35).      %ADC1 CH7 INPUT ONLY
-define(BUTTON_MODE, 18).      %VSPI
-define(BUTTON_FAN, 19).       %VSPI
-define(BUTTON_TEMP_UP, 36).   %INPUT ONLY
-define(BUTTON_TEMP_DOWN, 39). %INPUT ONLY

-define(SDA, 21).              %SDA
-define(SCL, 22).              %SDL
-define(SPI_MISO, 12).         %HSPI
-define(SPI_MOSI, 13).         %HSPI
-define(SPI_SCK, 14).          %HSPI
-define(SPI_CS, 15).           %HSPI


-define(GENERIC_OUTPUT_ACTIVE_LOW, false).
-define(GENERIC_OUTPUTS, [?OUT1]).

-define(OUTPUT_PINS, [
                      ?STATUS_LED
                      ,?STATUS_LED2
                      ,?FAN1
                      ,?FAN2
                      ,?FAN3
                      ,?COMPRESSOR
                      ,?COMPRESSOR_LED
                      ,?BEEPER
                      ,?OUT1
                     ]).

-define(INPUT_PINS, [
                     ?THERMISTOR1
                     ,?THERMISTOR2
                     ,?BUTTON_MODE
                     ,?BUTTON_FAN
                     ,?BUTTON_TEMP_UP
                     ,?BUTTON_TEMP_DOWN
                    ]).

%-define(MEASUREINTERVAL, 2000).
-define(SAFETY_DELAY, 360000).
-define(COIL_TEMP_LIMIT, 44).
-define(THERMOSTAT_DEFAULT, <<"67">>). %BINARY integer only, not float or integer
-define(THERMOSTAT_SPAN_DEFAULT, <<"4.0">>). %BINARY FLOAT ONLY
-define(MIN_THERMOSTAT, 55).
-define(MAX_THERMOSTAT, 99).
-define(THERMOSTAT_PUB_INTERVAL_SEC, 120).
-define(FLOAT_DECIMAL_LIMIT, 2). %format floats to this number of decimal places when converting to binary

%MQTT Topics
-define(TOPIC_AC, <<?DEVICENAME, "/AC">>).
-define(TOPIC_MAIN_STATUS, <<"status">>). %shared feed shows devices connecting
-define(TOPIC_STATUS, <<?DEVICENAME, "/status">>).
-define(TOPIC_DEBUG, <<?DEVICENAME, "/debug">>).
-define(TOPIC_TEMP_COIL, <<?DEVICENAME, "/coilTemp">>).
-define(TOPIC_TEMP1, <<?DEVICENAME, "/temp1">>).
-define(TOPIC_TEMP2, <<?DEVICENAME, "/temp2">>).
-define(TOPIC_TEMP_OUTSIDE, <<?DEVICENAME, "/tempOutside">>).
-define(TOPIC_FAN, <<?DEVICENAME, "/fan">>).
%-define(TOPIC_SPAN, <<?DEVICENAME, "/span">>).
-define(TOPIC_THERMOSTAT_SET, <<?DEVICENAME, "/thermostatSet">>).
-define(TOPIC_THERMOSTAT, <<?DEVICENAME, "/thermostat">>).
-define(TOPIC_OUT1, <<?DEVICENAME, "/out1">>).


