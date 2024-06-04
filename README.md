# RuhNet ESP32 `airconditioner` Control App

This is an AtomVM application, written in Erlang, that controls an air conditioning unit.

Recently, one of my window airconditioning units started exhibiting issues (strange behavior). After a bit of diagnosis, it appeared to be the [custom] microcontroller that had failed. This particular unit has 4 relays which control the compressor (on/off) and three fan speeds. There are also two thermistors; one to monitor the air temperature for the thermostat, and another on the evaporator coil for freeze protection monitoring.
The original microcontroller was connected to a ULN2003 darlington transistor driver IC, which turned the relays on/off based on logic level outputs of the microcontroller. I removed the original microcontroller from the board, and jumpered connections from the two thermistors and the ULN2003 inputs to a multi-wire cable which originally connected the control board to a front panel display/buttons board.
That multi-wire cable now connects to my ESP32 (just a standard devkit board), which is the new "brains" of the system.

The ESP32 monitors the temperature of the thermistors, and periodically checks them against temperature cutoff values supplied by a thermostat process (and a fixed freeze prevention cutoff temperature for the evaporator coil sensor).

Most things are supervised, and auto-restarted if they crash.

There is a 6 minute compressor delay initiated at bootup and any time the compressor has stopped, to prevent short cycling and damaging it.

Modes of operation are:
- `off`
- `cool`
- `energy_saver`
- `fan_only`

The `energy_saver` mode is the same as `cool`, except the fan is turned off whenever the compressor has stopped.

MQTT topics are subscribed to for general control of mode, fan speeds, and thermostat. The main control topic allows setting debug mode, showing memory usage, uptime, etc. The system also publishes status information, debug logging (if enabled), thermostat setpoint, etc. periodically.

The thermostat span can be set as well, and allows you to set the temperature swing between turning the compressor on and off. Small span values (less than 3) are split in half, whereas values larger than that are biased 75% toward the cool side.

Example 1:
- thermostat `temp` value set to 70 degrees
- thermostat `span` set to 2 degrees
- when temperature reaches 71 degrees, compressor will engage
- compressor will stay on until temperature drops to 69 degrees

Example 2:
- thermostat `temp` value set to 70 degrees
- thermostat `span` set to 8 degrees
- when temperature reaches 72 degrees (25% of span value), compressor will engage
- compressor will stay on until temperature drops to 64 degrees (six degrees is 75% of the span value of 8 degrees).

The thermostat temperature and span can be saved into NVS (non volatile storage) by sending it a `save` command.

In addition to using the built-in thermistor as the source for the temperature to compare with the thermostat setting, you can set a remote MQTT topic to subscribe to for temperature readings. I have a small ESP8266 temp sensor that publishes readings to MQTT, so I can place it in an adjoining room and the AC will keep the temperature regulated in the other room adjacent to where the unit actually is. Send `temp_source {TOPIC}` on the main control channel to set a remote temperature feed. This setting is saved in NVS. To revert back to the internal thermistor measurement, send `temp_source local`.

You can also set timers for actions to be executed after a delay: publishing `timer cool 2h` on the main control topic turns the unit on cool mode in 2 hours from now; publishing `timer 69 15m` on the thermostat topic will set the thermostat to 69 degrees (F) in 15 minutes.

There is also a generic output, controlled by the {DEVICENAME}/out1 feed, which I have connected to a relay module that turns on/off some extra house fans external to the AC unit. Timers work for that output as well.

> Set your WiFi values in `src/config.erl-template` and rename it `src/config.erl`.

> The `src/app.hrl` file contains defines for pin assignments and such. (You can add additional pins for generic outputs and they should work without other code modifications, etc.)

On my particular unit I left the I2C pins [default 21,22] unused, in case I later want to add an I2C temp sensor. Since the thermistors are read using the ADC on the ESP32, *you must compile AtomVM with the ADC driver.*

### TODO/Potential Feature Additions
- Save state in NVS, so that the mode state can be resumed after a power loss. (?)
- HTTP server that allows changing configuration options such as the WiFi client settings, MQTT broker, etc.
- HTTP server that allows setting mode/thermostat/etc. without MQTT.
- Button reading input for changing mode/thermostat.
- LCD Display
