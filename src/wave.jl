"""
Clears all waveforms and any data added by calls to the
[*wave_add_**] functions.

...
wave_clear(pi, )
...
"""
function wave_clear(self::Pi)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVCLR, 0, 0))
end

"""
Starts a new empty waveform.

You would not normally need to call this function as it is
automatically called after a waveform is created with the
[*wave_create*] function.

...
wave_add_new(pi, )
...
"""
function wave_add_new(self::Pi)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVNEW, 0, 0))
end

"""
Adds a list of pulses to the current waveform.

pulses:= list of pulses to add to the waveform.

Returns the new total number of pulses in the current waveform.

The pulses are interleaved in time order within the existing
waveform (if any).

Merging allows the waveform to be built in parts, that is the
settings for GPIO#1 can be added, and then GPIO#2 etc.

If the added waveform is intended to start after or within
the existing waveform then the first pulse should consist
solely of a delay.

...
G1=4
G2=24

set_mode(pi, G1, pigpio.OUTPUT)
set_mode(pi, G2, pigpio.OUTPUT)

flash_500=[] # flash every 500 ms
flash_100=[] # flash every 100 ms

#                              ON     OFF  DELAY

flash_500.append(pigpio.pulse(1<<G1, 1<<G2, 500000))
flash_500.append(pigpio.pulse(1<<G2, 1<<G1, 500000))

flash_100.append(pigpio.pulse(1<<G1, 1<<G2, 100000))
flash_100.append(pigpio.pulse(1<<G2, 1<<G1, 100000))

wave_clear(pi, ) # clear any existing waveforms

wave_add_generic(pi, flash_500) # 500 ms flashes
f500 = wave_create(pi, ) # create and save id

wave_add_generic(pi, flash_100) # 100 ms flashes
f100 = wave_create(pi, ) # create and save id

wave_send_repeat(pi, f500)

time.sleep(4)

wave_send_repeat(pi, f100)

time.sleep(4)

wave_send_repeat(pi, f500)

time.sleep(4)

wave_tx_stop(pi, ) # stop waveform

wave_clear(pi, ) # clear all waveforms
...
"""
function wave_add_generic(self::Pi, pulses)
    # pigpio message format

    # I p1 0
    # I p2 0
    # I p3 pulses * 12
    ## extension ##
    # III on/off/delay * pulses
    if length(pulses)
        ext = bytearray()
        for p in pulses
        ext.extend(pack("III", p.gpio_on, p.gpio_off, p.delay))
        end
        extents = [ext]
        return _u2i(_pigpio_command_ext(
            self.sl, _PI_CMD_WVAG, 0, 0, length(pulses)*12, extents))
    else
        return 0
    end
end

"""
Adds a waveform representing serial data to the existing
waveform (if any).  The serial data starts [*offset*]
microseconds from the start of the waveform.

user_gpio:= GPIO to transmit data.  You must set the GPIO mode
   to output.
baud:= 50-1000000 bits per second.
data:= the bytes to write.
offset:= number of microseconds from the start of the
   waveform, default 0.
bb_bits:= number of data bits, default 8.
bb_stop:= number of stop half bits, default 2.

Returns the new total number of pulses in the current waveform.

The serial data is formatted as one start bit, [*bb_bits*]
data bits, and [*bb_stop*]/2 stop bits.

It is legal to add serial data streams with different baud
rates to the same waveform.

The bytes required for each character depend upon [*bb_bits*].

For [*bb_bits*] 1-8 there will be one byte per character.
For [*bb_bits*] 9-16 there will be two bytes per character.
For [*bb_bits*] 17-32 there will be four bytes per character.

...
wave_add_serial(pi, 4, 300, 'Hello world')

wave_add_serial(pi, 4, 300, b"Hello world")

wave_add_serial(pi, 4, 300, b'\\x23\\x01\\x00\\x45')

wave_add_serial(pi, 17, 38400, [23, 128, 234], 5000)
...
"""
function wave_add_serial(
    self::Pi, user_gpio, baud, data, offset=0, bb_bits=8, bb_stop=2)
    if length(data)
        extents = [pack("III", bb_bits, bb_stop, offset), data]
        return _u2i(_pigpio_command_ext(
            self.sl, _PI_CMD_WVAS, user_gpio, baud, length(data)+12, extents))
    else
        return 0
    end
end

"""
Creates a waveform from the data provided by the prior calls
to the [*wave_add_**] functions.

Returns a wave id (>=0) if OK,  otherwise PI_EMPTY_WAVEFORM,
PI_TOO_MANY_CBS, PI_TOO_MANY_OOL, or PI_NO_WAVEFORM_ID.

The data provided by the [*wave_add_**] functions is consumed by
this function.

As many waveforms may be created as there is space available.
The wave id is passed to [*wave_send_**] to specify the waveform
to transmit.

Normal usage would be

Step 1. [*wave_clear*] to clear all waveforms and added data.

Step 2. [*wave_add_**] calls to supply the waveform data.

Step 3. [*wave_create*] to create the waveform and get a unique id

Repeat steps 2 and 3 as needed.

Step 4. [*wave_send_**] with the id of the waveform to transmit.

A waveform comprises one or more pulses.

A pulse specifies

1) the GPIO to be switched on at the start of the pulse.
2) the GPIO to be switched off at the start of the pulse.
3) the delay in microseconds before the next pulse.

Any or all the fields can be zero.  It doesn't make any sense
to set all the fields to zero (the pulse will be ignored).

When a waveform is started each pulse is executed in order with
the specified delay between the pulse and the next.

...
wid = wave_create(pi, )
...
"""
function wave_create(self::Pi)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVCRE, 0, 0))
end

"""
This function deletes the waveform with id wave_id.

wave_id:= >=0 (as returned by a prior call to [*wave_create*]).

Wave ids are allocated in order, 0, 1, 2, etc.

...
wave_delete(pi, 6) # delete waveform with id 6

wave_delete(pi, 0) # delete waveform with id 0
...
"""
function wave_delete(self::Pi, wave_id)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVDEL, wave_id, 0))
end

"""
This function is deprecated and has been removed.

Use [*wave_create*]/[*wave_send_**] instead.
"""
function wave_tx_start(self::Pi) # DEPRECATED
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVGO, 0, 0))
end

"""
This function is deprecated and has beeen removed.

Use [*wave_create*]/[*wave_send_**] instead.
"""
function wave_tx_repeat(self::Pi) # DEPRECATED
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVGOR, 0, 0))
end

"""
Transmits the waveform with id wave_id.  The waveform is sent
once.

NOTE: Any hardware PWM started by [*hardware_PWM*] will
be cancelled.

wave_id:= >=0 (as returned by a prior call to [*wave_create*]).

Returns the number of DMA control blocks used in the waveform.

...
cbs = wave_send_once(pi, wid)
...
"""
function wave_send_once(self::Pi, wave_id)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVTX, wave_id, 0))
end

"""
Transmits the waveform with id wave_id.  The waveform repeats
until wave_tx_stop is called or another call to [*wave_send_**]
is made.

NOTE: Any hardware PWM started by [*hardware_PWM*] will
be cancelled.

wave_id:= >=0 (as returned by a prior call to [*wave_create*]).

Returns the number of DMA control blocks used in the waveform.

...
cbs = wave_send_repeat(pi, wid)
...
"""
function wave_send_repeat(self::Pi, wave_id)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVTXR, wave_id, 0))
end

"""
Transmits the waveform with id wave_id using mode mode.

wave_id:= >=0 (as returned by a prior call to [*wave_create*]).
mode:= WAVE_MODE_ONE_SHOT, WAVE_MODE_REPEAT,
    WAVE_MODE_ONE_SHOT_SYNC, or WAVE_MODE_REPEAT_SYNC.

WAVE_MODE_ONE_SHOT: same as [*wave_send_once*].

WAVE_MODE_REPEAT same as [*wave_send_repeat*].

WAVE_MODE_ONE_SHOT_SYNC same as [*wave_send_once*] but tries
to sync with the previous waveform.

WAVE_MODE_REPEAT_SYNC same as [*wave_send_repeat*] but tries
to sync with the previous waveform.

WARNING: bad things may happen if you delete the previous
waveform before it has been synced to the new waveform.

NOTE: Any hardware PWM started by [*hardware_PWM*] will
be cancelled.

wave_id:= >=0 (as returned by a prior call to [*wave_create*]).

Returns the number of DMA control blocks used in the waveform.

...
cbs = wave_send_using_mode(pi, wid, WAVE_MODE_REPEAT_SYNC)
...
"""
function wave_send_using_mode(self::Pi, wave_id, mode)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVTXM, wave_id, mode))
end

"""
Returns the id of the waveform currently being
transmitted.

Returns the waveform id or one of the following special
values

WAVE_NOT_FOUND (9998) - transmitted wave not found.
NO_TX_WAVE (9999) - no wave being transmitted.

...
wid = wave_tx_at(pi, )
...
"""
function wave_tx_at(self::Pi)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVTAT, 0, 0))
end

"""
Returns 1 if a waveform is currently being transmitted,
otherwise 0.

...
wave_send_once(pi, 0) # send first waveform

while wave_tx_busy(pi, ): # wait for waveform to be sent
time.sleep(0.1)

wave_send_once(pi, 1) # send next waveform
...
"""
function wave_tx_busy(self::Pi)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVBSY, 0, 0))
end

"""
Stops the transmission of the current waveform.

This function is intended to stop a waveform started with
wave_send_repeat.

...
wave_send_repeat(pi, 3)

time.sleep(5)

wave_tx_stop(pi, )
...
"""
function wave_tx_stop(self::Pi)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVHLT, 0, 0))
end

"""
This function transmits a chain of waveforms.

NOTE: Any hardware PWM started by [*hardware_PWM*]
will be cancelled.

The waves to be transmitted are specified by the contents
of data which contains an ordered list of [*wave_id*]s
and optional command codes and related data.

Returns 0 if OK, otherwise PI_CHAIN_NESTING,
PI_CHAIN_LOOP_CNT, PI_BAD_CHAIN_LOOP, PI_BAD_CHAIN_CMD,
PI_CHAIN_COUNTER, PI_BAD_CHAIN_DELAY, PI_CHAIN_TOO_BIG,
or PI_BAD_WAVE_ID.

Each wave is transmitted in the order specified.  A wave
may occur multiple times per chain.

A blocks of waves may be transmitted multiple times by
using the loop commands. The block is bracketed by loop
start and end commands.  Loops may be nested.

Delays between waves may be added with the delay command.

The following command codes are supported

Name         @ Cmd & Data @ Meaning
Loop Start   @ 255 0      @ Identify start of a wave block
Loop Repeat  @ 255 1 x y  @ loop x + y*256 times
Delay        @ 255 2 x y  @ delay x + y*256 microseconds
Loop Forever @ 255 3      @ loop forever

If present Loop Forever must be the last entry in the chain.

The code is currently dimensioned to support a chain with
roughly 600 entries and 20 loop counters.

...
#!/usr/bin/env python

import time
import pigpio

WAVES=5
GPIO=4

wid=[0]*WAVES

pi = pigpio.pi() # Connect to local Pi.

set_mode(pi, GPIO, pigpio.OUTPUT);

for i in range(WAVES)
pi.wave_add_generic([
pigpio.pulse(1<<GPIO, 0, 20),
pigpio.pulse(0, 1<<GPIO, (i+1)*200)]);

wid[i] = wave_create(pi, );

pi.wave_chain([
wid[4], wid[3], wid[2],       # transmit waves 4+3+2
255, 0,                       # loop start
wid[0], wid[0], wid[0],    # transmit waves 0+0+0
255, 0,                    # loop start
   wid[0], wid[1],         # transmit waves 0+1
   255, 2, 0x88, 0x13,     # delay 5000us
255, 1, 30, 0,             # loop end (repeat 30 times)
255, 0,                    # loop start
   wid[2], wid[3], wid[0], # transmit waves 2+3+0
   wid[3], wid[1], wid[2], # transmit waves 3+1+2
255, 1, 10, 0,             # loop end (repeat 10 times)
255, 1, 5, 0,                 # loop end (repeat 5 times)
wid[4], wid[4], wid[4],       # transmit waves 4+4+4
255, 2, 0x20, 0x4E,           # delay 20000us
wid[0], wid[0], wid[0],       # transmit waves 0+0+0
])

while wave_tx_busy(pi, )
time.sleep(0.1);

for i in range(WAVES)
wave_delete(pi, wid[i])

stop(pi, )
...
"""
function wave_chain(self::Pi, data)
# I p1 0
# I p2 0
# I p3 len
## extension ##
# s len data bytes
    return _u2i(_pigpio_command_ext(
        self.sl, _PI_CMD_WVCHA, 0, 0, length(data), [data]))
end

"""
Returns the length in microseconds of the current waveform.

...
micros = wave_get_micros(pi, )
...
"""
function wave_get_micros(self::Pi)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVSM, 0, 0))
end

"""
Returns the maximum possible size of a waveform in microseconds.

...
micros = wave_get_max_micros(pi, )
...
"""
function wave_get_max_micros(self::Pi)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVSM, 2, 0))
end

"""
Returns the length in pulses of the current waveform.

...
pulses = wave_get_pulses(pi, )
...
"""
function wave_get_pulses(self::Pi)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVSP, 0, 0))
end

"""
Returns the maximum possible size of a waveform in pulses.

...
pulses = wave_get_max_pulses(pi, )
...
"""
function wave_get_max_pulses(self::Pi)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVSP, 2, 0))
end

"""
Returns the length in DMA control blocks of the current
waveform.

...
cbs = wave_get_cbs(pi, )
...
"""
function wave_get_cbs(self::Pi)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVSC, 0, 0))
end

"""
Returns the maximum possible size of a waveform in DMA
control blocks.

...
cbs = wave_get_max_cbs(pi, )
...
"""
function wave_get_max_cbs(self::Pi)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVSC, 2, 0))
end
