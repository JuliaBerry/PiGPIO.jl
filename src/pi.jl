exceptions = true
# import sys
# import socket
# import struct
# import time
# import threading
# import os
# import atexit


# class _socklock
#
#    def __init__(self)
#       self.s = None
#       self.l = threading.Lock()
"""
A class to store socket and lock.
"""
mutable struct SockLock
    s::TCPSocket
    l::ReentrantLock
end

"""
A class to store pulse information.

gpio_on: the GPIO to switch on at the start of the pulse.
gpio_off: the GPIO to switch off at the start of the pulse.
delay: the delay in microseconds before the next pulse.
"""
mutable struct Pulse
    gpio_on::Int
    gpio_off::Int
    delay::Int
end

# class pulse
#
#
#    def __init__(self, gpio_on, gpio_off, delay)
#       """
#       Initialises a pulse.
#
#
#       """
#       self.gpio_on = gpio_on
#       self.gpio_off = gpio_off
#       self.delay = delay


"""
Returns a text description of a pigpio error.

errnum:= <0, the error number

...
print(pigpio.error_text(-5))
level not 0-1
...
"""
function error_text(errnum)
    for e in _errors
        if e[0] == errnum
           return e[1]
       end
    end
    return "unknown error ($ernum)"
end

"""
Returns the microsecond difference between two ticks.

t1:= the earlier tick
t2:= the later tick

...
print(pigpio.tickDiff(4294967272, 12))
36
...
"""
function tickDiff(t1, t2)
   tDiff = t2 - t1
   if tDiff < 0
      tDiff += (1 << 32)
   end
   return tDiff
end


"""
Converts a 32 bit unsigned number to signed.  If the number
is negative it indicates an error.  On error a pigpio
exception will be raised if exceptions is true.
"""
function _u2i(x::UInt32)
   v = convert(Int32, x)
   if v < 0
      if exceptions
          error(error_text(v))
     end
   end
   return v
end


struct InMsg
    cmd::Cuint # a bits type
    p1::Cuint # an array of bits types
    p2::Cuint # a string with a fixed number of bytes
    d::Cuint
end

struct OutMsg
    dummy::Array{UInt8,1}(12) # a bits type
    res::Cuint # an array of bits types
end

   """
   Runs a pigpio socket command.

    sl:= command socket and lock.
   cmd:= the command to be executed.
    p1:= command parameter 1 (if applicable).
     p2:=  command parameter 2 (if applicable).
   """
function _pigpio_command(sl::SockLock, cmd::Integer, p1::Integer, p2::Integer, rl=true)
    lock(sl.l)
    pack(sl.s, InMsg(cmd, p1, p2, 0))
    #sl.s.send(struct.pack('IIII', cmd, p1, p2, 0))
    out = IOBuffer(Base.read(sl.s, 16))
    msg = unpack(out, OutMsg )
    #dummy, res = struct.unpack('12sI', sl.s.recv(16))
    if rl
        unlock(sl.l)
    end
   return msg.res
end

"""
Runs an extended pigpio socket command.

    sl:= command socket and lock.
   cmd:= the command to be executed.
    p1:= command parameter 1 (if applicable).
    p2:= command parameter 2 (if applicable).
    p3:= total size in bytes of following extents
extents:= additional data blocks
"""
function _pigpio_command_ext(sl, cmd, p1, p2, p3, extents, rl=true)
    ext = IOBuffer()
    pack(ext, InMsg(cmd, p1, p2, p3))
    for x in extents
       write(ext, string(x))
    end
    lock(sl.l)
    write(sl.s, ext)
    msg = unpack(sl.s, OutMsg )
    if rl
         unlock(sl.l)
    end
    return msg.res
end

"""An ADT class to hold callback information

   gpio:= Broadcom GPIO number.
   edge:= EITHER_EDGE, RISING_EDGE, or FALLING_EDGE.
   func:= a user function taking three arguments (GPIO, level, tick).
"""
mutable struct Callback_ADT
    gpio::Int
    edge::Int
    func::Function
    bit::Int

    Callback_ADT(gpio, edge, func) = new(gpio, edge, func, 1<<gpio)
end

"""A class to encapsulate pigpio notification callbacks."""
mutable struct CallbackThread #(threading.Thread)
    control::SockLock
    sl::SockLock
    go::Bool
    daemon::Bool
    monitor::Int
    handle::Cuint
    callbacks::Array{Any, 1}
end

"""Initialises notifications."""
function CallbackThread(control, host, port)
    socket = connect(host, port)
    sl = SockLock(socket, ReentrantLock())
    self = CallbackThread(control, sl, false, true, 0, 0, Any[])
    self.handle = _pigpio_command(sl, _PI_CMD_NOIB, 0, 0)
    self.go = true
    return self
    #self.start()  #TODO
end

"""Stops notifications."""
function stop(self::CallbackThread)
    if self.go
        self.go = false
        write(self.sl.s, pack(InMsg(_PI_CMD_NC, self.handle, 0, 0)))
    end
end

"""Adds a callback to the notification thread."""
function append(self::CallbackThread, callb)
    push!(self.callbacks, callb)
    self.monitor = self.monitor | callb.bit
    _pigpio_command(self.control, _PI_CMD_NB, self.handle, self.monitor)
end

"""Removes a callback from the notification thread."""
function remove(self::CallbackThread, callb)
    if callb in self.callbacks
        self.callbacks.remove(callb)
        newMonitor = 0
        for c in self.callbacks
            newMonitor |= c.bit
        end

        if newMonitor != self.monitor
            self.monitor = newMonitor
            _pigpio_command(
                self.control, _PI_CMD_NB, self.handle, self.monitor)
        end
    end
end


struct CallbMSg
    seq::Cushort
    flags::Cushort
    tick::Cuint
    level::Cuint
end


"""Runs the notification thread."""
function run(self::CallbackThread)
    lastLevel = _pigpio_command(self.control,  _PI_CMD_BR1, 0, 0)

    MSG_SIZ = 12

    while self.go

        buf = readbytes(self.sl.s, MSG_SIZ, all=true)

        if self.go
            msg = unpack(buf, CallbMsg)
            seq = msg.seq
            seq, flags, tick, level = (msg.seq, msg.flags, msg.tick, msg.level)

            if flags == 0
                changed = level ^ lastLevel
                lastLevel = level
                for  cb in self.callbacks
                    if cb.bit && changed
                        newLevel = 0
                    elseif cb.bit & level
                        newLevel = 1
                    end

                    if (cb.edge ^ newLevel)
                        cb.func(cb.gpio, newLevel, tick)
                    end

                end
            else
                if flags & NTFY_FLAGS_WDOG
                    gpio = flags & NTFY_FLAGS_GPIO
                    for cb in self.callbacks
                        if cb.gpio == gpio
                            cb.func(cb.gpio, TIMEOUT, tick)
                        end
                    end
                end
            end
        end
    end
    close(self.sl.s)
end

"""A class to provide GPIO level change callbacks."""
mutable struct Callback
    notify::Array{Callback_ADT, 1}
    count::Int
    reset::Bool
    callb::Callback_ADT
end

function Callback(notify, user_gpio, edge=RISING_EDGE, func=nothing)
    self = Callback(notify, 0, false, nothing)
    if func == nothing
        func = _tally
    end
    self.callb = Callback_ADT(user_gpio, edge, func)
    push!(self.notify, self.callb)
end

"""Cancels a callback by removing it from the notification thread."""
function cancel(self)
    filter(x->x!=self.callb, self.notify )
end


"""Increment the callback called count."""
function _tally(self::Callback, user_gpio, level, tick)
    if self.reset
        self.reset = false
        self.count = 0
    end
    self.count += 1
end

"""
Provides a count of how many times the default tally
callback has triggered.

The count will be zero if the user has supplied their own
callback function.
"""
function tally(self::Callback)
    return self.count
end

"""
Resets the tally count to zero.
"""
function reset_tally(self::Callback)
    self._reset = true
    self.count = 0
end

"""Encapsulates waiting for GPIO edges."""
mutable struct WaitForEdge
    notify
    callb
    trigger
    start
end

"""Initialises a wait_for_edge."""
function WaitForEdge( notify, gpio, edge, timeout)
    callb = _callback_ADT(gpio, edge, self.func)
    self = WaitForEdge(notify, callb, false, time())
    push!(self.notify, self.callb)
    while (self.trigger == false) && ((time()-self.start) < timeout)
      time.sleep(0.05)
    end
    self._notify.remove(self.callb)
end

"""Sets wait_for_edge triggered."""
function func(self::WaitForEdge, gpio, level, tick)
    self.trigger = true
end

mutable struct Pi
    host::String
    port::Int
    connected::Bool
    sl::SockLock
    notify::CallbackThread
end

"""Returns count bytes from the command socket."""
function rxbuf(self::Pi, count)
    ext = readbytes(self.sl.s, count, all)
    return ext
end

"""
Sets the GPIO mode.

gpio:= 0-53.
mode:= INPUT, OUTPUT, ALT0, ALT1, ALT2, ALT3, ALT4, ALT5.

...
pi.set_mode( 4, pigpio.INPUT)  # GPIO  4 as input
pi.set_mode(17, pigpio.OUTPUT) # GPIO 17 as output
pi.set_mode(24, pigpio.ALT2)   # GPIO 24 as ALT2
...
"""
function set_mode(self::Pi, gpio, mode)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_MODES, gpio, mode))
end


"""
Returns the GPIO mode.

gpio:= 0-53.

Returns a value as follows

. .
0 = INPUT
1 = OUTPUT
2 = ALT5
3 = ALT4
4 = ALT0
5 = ALT1
6 = ALT2
7 = ALT3
. .

...
print(pi.get_mode(0))
4
...
"""
function get_mode(self::Pi, gpio)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_MODEG, gpio, 0))
end


"""
Sets or clears the internal GPIO pull-up/down resistor.

gpio:= 0-53.
pud:= PUD_UP, PUD_DOWN, PUD_OFF.

...
pi.set_pull_up_down(17, pigpio.PUD_OFF)
pi.set_pull_up_down(23, pigpio.PUD_UP)
pi.set_pull_up_down(24, pigpio.PUD_DOWN)
...
"""
function set_pull_up_down(self::Pi, gpio, pud)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_PUD, gpio, pud))
end


"""
Returns the GPIO level.

gpio:= 0-53.

...
pi.set_mode(23, pigpio.INPUT)

pi.set_pull_up_down(23, pigpio.PUD_DOWN)
print(pi.read(23))
0

pi.set_pull_up_down(23, pigpio.PUD_UP)
print(pi.read(23))
1
...
"""
function read(self::Pi, gpio)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_READ, gpio, 0))
end

"""
Sets the GPIO level.

GPIO:= 0-53.
level:= 0, 1.

If PWM or servo pulses are active on the GPIO they are
switched off.

...
pi.set_mode(17, pigpio.OUTPUT)

pi.write(17,0)
print(pi.read(17))
0

pi.write(17,1)
print(pi.read(17))
1
...
"""
function write(self::Pi, gpio, level)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WRITE, gpio, level))
end


"""
Starts (non-zero dutycycle) or stops (0) PWM pulses on the GPIO.

user_gpio:= 0-31.
dutycycle:= 0-range (range defaults to 255).

The [*set_PWM_range*] function can change the default range of 255.

...
pi.set_PWM_dutycycle(4,   0) # PWM off
pi.set_PWM_dutycycle(4,  64) # PWM 1/4 on
pi.set_PWM_dutycycle(4, 128) # PWM 1/2 on
pi.set_PWM_dutycycle(4, 192) # PWM 3/4 on
pi.set_PWM_dutycycle(4, 255) # PWM full on
...
"""
function set_PWM_dutycycle(self::Pi, user_gpio, dutycycle)
    return _u2i(_pigpio_command(
        self.sl, _PI_CMD_PWM, user_gpio, Int(dutycycle)))
end

"""
Returns the PWM dutycycle being used on the GPIO.

user_gpio:= 0-31.

Returns the PWM dutycycle.


For normal PWM the dutycycle will be out of the defined range
for the GPIO (see [*get_PWM_range*]).

If a hardware clock is active on the GPIO the reported
dutycycle will be 500000 (500k) out of 1000000 (1M).

If hardware PWM is active on the GPIO the reported dutycycle
will be out of a 1000000 (1M).

...
pi.set_PWM_dutycycle(4, 25)
print(pi.get_PWM_dutycycle(4))
25

pi.set_PWM_dutycycle(4, 203)
print(pi.get_PWM_dutycycle(4))
203
...
"""
function get_PWM_dutycycle(self::Pi, user_gpio)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_GDC, user_gpio, 0))
end

"""
Sets the range of PWM values to be used on the GPIO.

user_gpio:= 0-31.
 range_:= 25-40000.

...
pi.set_PWM_range(9, 100)  # now  25 1/4,   50 1/2,   75 3/4 on
pi.set_PWM_range(9, 500)  # now 125 1/4,  250 1/2,  375 3/4 on
pi.set_PWM_range(9, 3000) # now 750 1/4, 1500 1/2, 2250 3/4 on
...
"""
function set_PWM_range(self::Pi, user_gpio, range_)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_PRS, user_gpio, range_))
end

"""
Returns the range of PWM values being used on the GPIO.

user_gpio:= 0-31.

If a hardware clock or hardware PWM is active on the GPIO
the reported range will be 1000000 (1M).

...
pi.set_PWM_range(9, 500)
print(pi.get_PWM_range(9))
500
...
"""
function get_PWM_range(self::Pi, user_gpio)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_PRG, user_gpio, 0))
end

"""
Returns the real (underlying) range of PWM values being
used on the GPIO.

user_gpio:= 0-31.

If a hardware clock is active on the GPIO the reported
real range will be 1000000 (1M).

If hardware PWM is active on the GPIO the reported real range
will be approximately 250M divided by the set PWM frequency.

...
pi.set_PWM_frequency(4, 800)
print(pi.get_PWM_real_range(4))
250
...
"""
function get_PWM_real_range(self::Pi, user_gpio)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_PRRG, user_gpio, 0))
end

"""
Sets the frequency (in Hz) of the PWM to be used on the GPIO.

user_gpio:= 0-31.
frequency:= >=0 Hz

Returns the numerically closest frequency if OK, otherwise
PI_BAD_USER_GPIO or PI_NOT_PERMITTED.

If PWM is currently active on the GPIO it will be switched
off and then back on at the new frequency.

Each GPIO can be independently set to one of 18 different
PWM frequencies.

The selectable frequencies depend upon the sample rate which
may be 1, 2, 4, 5, 8, or 10 microseconds (default 5).  The
sample rate is set when the pigpio daemon is started.

The frequencies for each sample rate are

. .
                     Hertz

     1: 40000 20000 10000 8000 5000 4000 2500 2000 1600
         1250  1000   800  500  400  250  200  100   50

     2: 20000 10000  5000 4000 2500 2000 1250 1000  800
          625   500   400  250  200  125  100   50   25

     4: 10000  5000  2500 2000 1250 1000  625  500  400
          313   250   200  125  100   63   50   25   13
sample
rate
(us)  5:  8000  4000  2000 1600 1000  800  500  400  320
          250   200   160  100   80   50   40   20   10

     8:  5000  2500  1250 1000  625  500  313  250  200
          156   125   100   63   50   31   25   13    6

    10:  4000  2000  1000  800  500  400  250  200  160
          125   100    80   50   40   25   20   10    5
. .

...
pi.set_PWM_frequency(4,0)
print(pi.get_PWM_frequency(4))
10

pi.set_PWM_frequency(4,100000)
print(pi.get_PWM_frequency(4))
8000
...
"""
function set_PWM_frequency(self::Pi, user_gpio, frequency)
    return _u2i(
        _pigpio_command(self.sl, _PI_CMD_PFS, user_gpio, frequency))
end

"""
Returns the frequency of PWM being used on the GPIO.

user_gpio:= 0-31.

Returns the frequency (in Hz) used for the GPIO.

For normal PWM the frequency will be that defined for the GPIO
by [*set_PWM_frequency*].

If a hardware clock is active on the GPIO the reported frequency
will be that set by [*hardware_clock*].

If hardware PWM is active on the GPIO the reported frequency
will be that set by [*hardware_PWM*].

...
pi.set_PWM_frequency(4,0)
print(pi.get_PWM_frequency(4))
10

pi.set_PWM_frequency(4, 800)
print(pi.get_PWM_frequency(4))
800
...
"""
function get_PWM_frequency(self::Pi, user_gpio)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_PFG, user_gpio, 0))
end

"""
Starts (500-2500) or stops (0) servo pulses on the GPIO.

user_gpio:= 0-31.
pulsewidth:= 0 (off),
           500 (most anti-clockwise) - 2500 (most clockwise).

The selected pulsewidth will continue to be transmitted until
changed by a subsequent call to set_servo_pulsewidth.

The pulsewidths supported by servos varies and should probably
be determined by experiment. A value of 1500 should always be
safe and represents the mid-point of rotation.

You can DAMAGE a servo if you command it to move beyond its
limits.

...
pi.set_servo_pulsewidth(17, 0)    # off
pi.set_servo_pulsewidth(17, 1000) # safe anti-clockwise
pi.set_servo_pulsewidth(17, 1500) # centre
pi.set_servo_pulsewidth(17, 2000) # safe clockwise
...
"""
function set_servo_pulsewidth(self::Pi, user_gpio, pulsewidth)
    return _u2i(_pigpio_command(
        self.sl, _PI_CMD_SERVO, user_gpio, int(pulsewidth)))
end

"""
Returns the servo pulsewidth being used on the GPIO.

user_gpio:= 0-31.

Returns the servo pulsewidth.

...
pi.set_servo_pulsewidth(4, 525)
print(pi.get_servo_pulsewidth(4))
525

pi.set_servo_pulsewidth(4, 2130)
print(pi.get_servo_pulsewidth(4))
2130
...
"""
function get_servo_pulsewidth(self::Pi, user_gpio)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_GPW, user_gpio, 0))
end

"""
Returns a notification handle (>=0).

A notification is a method for being notified of GPIO state
changes via a pipe.

Pipes are only accessible from the local machine so this
function serves no purpose if you are using Python from a
remote machine.  The in-built (socket) notifications
provided by [*callback*] should be used instead.

Notifications for handle x will be available at the pipe
named /dev/pigpiox (where x is the handle number).

E.g. if the function returns 15 then the notifications must be
read from /dev/pigpio15.

Notifications have the following structure.

. .
I seqno
I flags
I tick
I level
. .

seqno: starts at 0 each time the handle is opened and then
increments by one for each report.

flags: two flags are defined, PI_NTFY_FLAGS_WDOG and
PI_NTFY_FLAGS_ALIVE.  If bit 5 is set (PI_NTFY_FLAGS_WDOG)
then bits 0-4 of the flags indicate a GPIO which has had a
watchdog timeout; if bit 6 is set (PI_NTFY_FLAGS_ALIVE) this
indicates a keep alive signal on the pipe/socket and is sent
once a minute in the absence of other notification activity.

tick: the number of microseconds since system boot.  It wraps
around after 1h12m.

level: indicates the level of each GPIO.  If bit 1<<x is set
then GPIO x is high.

...
h = pi.notify_open()
if h >= 0
    pi.notify_begin(h, 1234)
...
"""
function notify_open(self::Pi)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_NO, 0, 0))
end

"""
Starts notifications on a handle.

handle:= >=0 (as returned by a prior call to [*notify_open*])
bits:= a 32 bit mask indicating the GPIO to be notified.

The notification sends state changes for each GPIO whose
corresponding bit in bits is set.

The following code starts notifications for GPIO 1, 4,
6, 7, and 10 (1234 = 0x04D2 = 0b0000010011010010).

...
h = pi.notify_open()
if h >= 0
    pi.notify_begin(h, 1234)
...
"""
function notify_begin(self::Pi, handle, bits)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_NB, handle, bits))
end

"""
Pauses notifications on a handle.

handle:= >=0 (as returned by a prior call to [*notify_open*])

Notifications for the handle are suspended until
[*notify_begin*] is called again.

...
h = pi.notify_open()
if h >= 0
    pi.notify_begin(h, 1234)
    ...
    pi.notify_pause(h)
    ...
    pi.notify_begin(h, 1234)
    ...
...
"""
function notify_pause(self::Pi, handle)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_NB, handle, 0))
end

"""
Stops notifications on a handle and releases the handle for reuse.

handle:= >=0 (as returned by a prior call to [*notify_open*])

...
h = pi.notify_open()
if h >= 0
    pi.notify_begin(h, 1234)
    ...
    pi.notify_close(h)
    ...
...
"""
function notify_close(self::Pi, handle)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_NC, handle, 0))
end

"""
Sets a watchdog timeout for a GPIO.

 user_gpio:= 0-31.
wdog_timeout:= 0-60000.

The watchdog is nominally in milliseconds.

Only one watchdog may be registered per GPIO.

The watchdog may be cancelled by setting timeout to 0.

If no level change has been detected for the GPIO for timeout
milliseconds any notification for the GPIO has a report written
to the fifo with the flags set to indicate a watchdog timeout.

The callback class interprets the flags and will
call registered callbacks for the GPIO with level TIMEOUT.

...
pi.set_watchdog(23, 1000) # 1000 ms watchdog on GPIO 23
pi.set_watchdog(23, 0)    # cancel watchdog on GPIO 23
...
"""
function set_watchdog(self::Pi, user_gpio, wdog_timeout)
    return _u2i(_pigpio_command(
        self.sl, _PI_CMD_WDOG, user_gpio, Int(wdog_timeout)))
end

"""
Returns the levels of the bank 1 GPIO (GPIO 0-31).

The returned 32 bit integer has a bit set if the corresponding
GPIO is high.  GPIO n has bit value (1<<n).

...
print(bin(pi.read_bank_1()))
0b10010100000011100100001001111
...
"""
function read_bank_1(self::Pi)
	return _pigpio_command(self.sl, _PI_CMD_BR1, 0, 0)
end

"""
Returns the levels of the bank 2 GPIO (GPIO 32-53).

The returned 32 bit integer has a bit set if the corresponding
GPIO is high.  GPIO n has bit value (1<<(n-32)).

...
print(bin(pi.read_bank_2()))
0b1111110000000000000000
...
"""
function read_bank_2(self::Pi)
    return _pigpio_command(self.sl, _PI_CMD_BR2, 0, 0)
end

"""
Clears GPIO 0-31 if the corresponding bit in bits is set.

bits:= a 32 bit mask with 1 set if the corresponding GPIO is
 to be cleared.

A returned status of PI_SOME_PERMITTED indicates that the user
is not allowed to write to one or more of the GPIO.

...
pi.clear_bank_1(int("111110010000",2))
...
"""
function clear_bank_1(self::Pi, bits)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_BC1, bits, 0))
end

"""
Clears GPIO 32-53 if the corresponding bit (0-21) in bits is set.

bits:= a 32 bit mask with 1 set if the corresponding GPIO is
to be cleared.

A returned status of PI_SOME_PERMITTED indicates that the user
is not allowed to write to one or more of the GPIO.

...
pi.clear_bank_2(0x1010)
...
"""
function clear_bank_2(self::Pi, bits)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_BC2, bits, 0))
end

"""
Sets GPIO 0-31 if the corresponding bit in bits is set.

bits:= a 32 bit mask with 1 set if the corresponding GPIO is
 to be set.

A returned status of PI_SOME_PERMITTED indicates that the user
is not allowed to write to one or more of the GPIO.

...
pi.set_bank_1(int("111110010000",2))
...
"""
function set_bank_1(self::Pi, bits)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_BS1, bits, 0))
end

"""
Sets GPIO 32-53 if the corresponding bit (0-21) in bits is set.

bits:= a 32 bit mask with 1 set if the corresponding GPIO is
 to be set.

A returned status of PI_SOME_PERMITTED indicates that the user
is not allowed to write to one or more of the GPIO.

...
pi.set_bank_2(0x303)
...
"""
function set_bank_2(self::Pi, bits)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_BS2, bits, 0))
end

"""
Starts a hardware clock on a GPIO at the specified frequency.
Frequencies above 30MHz are unlikely to work.

gpio:= see description
clkfreq:= 0 (off) or 4689-250000000 (250M)


Returns 0 if OK, otherwise PI_NOT_PERMITTED, PI_BAD_GPIO,
PI_NOT_HCLK_GPIO, PI_BAD_HCLK_FREQ,or PI_BAD_HCLK_PASS.

The same clock is available on multiple GPIO.  The latest
frequency setting will be used by all GPIO which share a clock.

The GPIO must be one of the following.

. .
4   clock 0  All models
5   clock 1  All models but A and B (reserved for system use)
6   clock 2  All models but A and B
20  clock 0  All models but A and B
21  clock 1  All models but A and Rev.2 B (reserved for system use)

32  clock 0  Compute module only
34  clock 0  Compute module only
42  clock 1  Compute module only (reserved for system use)
43  clock 2  Compute module only
44  clock 1  Compute module only (reserved for system use)
. .

Access to clock 1 is protected by a password as its use will
likely crash the Pi.  The password is given by or'ing 0x5A000000
with the GPIO number.

...
pi.hardware_clock(4, 5000) # 5 KHz clock on GPIO 4

pi.hardware_clock(4, 40000000) # 40 MHz clock on GPIO 4
...
"""
function hardware_clock(self::Pi, gpio, clkfreq)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_HC, gpio, clkfreq))
end

"""
Starts hardware PWM on a GPIO at the specified frequency
and dutycycle. Frequencies above 30MHz are unlikely to work.

NOTE: Any waveform started by [*wave_send_once*],
[*wave_send_repeat*], or [*wave_chain*] will be cancelled.

This function is only valid if the pigpio main clock is PCM.
The main clock defaults to PCM but may be overridden when the
pigpio daemon is started (option -t).

gpio:= see descripton
PWMfreq:= 0 (off) or 1-125000000 (125M).
PWMduty:= 0 (off) to 1000000 (1M)(fully on).

Returns 0 if OK, otherwise PI_NOT_PERMITTED, PI_BAD_GPIO,
PI_NOT_HPWM_GPIO, PI_BAD_HPWM_DUTY, PI_BAD_HPWM_FREQ.

The same PWM channel is available on multiple GPIO.
The latest frequency and dutycycle setting will be used
by all GPIO which share a PWM channel.

The GPIO must be one of the following.

. .
12  PWM channel 0  All models but A and B
13  PWM channel 1  All models but A and B
18  PWM channel 0  All models
19  PWM channel 1  All models but A and B

40  PWM channel 0  Compute module only
41  PWM channel 1  Compute module only
45  PWM channel 1  Compute module only
52  PWM channel 0  Compute module only
53  PWM channel 1  Compute module only
. .

The actual number of steps beween off and fully on is the
integral part of 250 million divided by PWMfreq.

The actual frequency set is 250 million / steps.

There will only be a million steps for a PWMfreq of 250.
Lower frequencies will have more steps and higher
frequencies will have fewer steps.  PWMduty is
automatically scaled to take this into account.

...
pi.hardware_PWM(18, 800, 250000) # 800Hz 25% dutycycle

pi.hardware_PWM(18, 2000, 750000) # 2000Hz 75% dutycycle
...
"""

function hardware_PWM(self::Pi, gpio, PWMfreq, PWMduty)
# pigpio message format

# I p1 gpio
# I p2 PWMfreq
# I p3 4
## extension ##
# I PWMdutycycle
    extents = IOBuffer()
    extents =write(extents, 10)
    return _u2i(_pigpio_command_ext(
        self.sl, _PI_CMD_HP, gpio, PWMfreq, 4, extents))
end

"""
Returns the current system tick.

Tick is the number of microseconds since system boot.  As an
unsigned 32 bit quantity tick wraps around approximately
every 71.6 minutes.

...
t1 = pi.get_current_tick()
time.sleep(1)
t2 = pi.get_current_tick()
...
"""
function get_current_tick(self::Pi)
    return _pigpio_command(self.sl, _PI_CMD_TICK, 0, 0)
end

"""
Returns the Pi's hardware revision number.

The hardware revision is the last few characters on the
Revision line of /proc/cpuinfo.

The revision number can be used to determine the assignment
of GPIO to pins (see [*gpio*]).

There are at least three types of board.

Type 1 boards have hardware revision numbers of 2 and 3.

Type 2 boards have hardware revision numbers of 4, 5, 6, and 15.

Type 3 boards have hardware revision numbers of 16 or greater.

If the hardware revision can not be found or is not a valid
hexadecimal number the function returns 0.

...
print(pi.get_hardware_revision())
2
...
"""
function get_hardware_revision(self::Pi)
    return _pigpio_command(self.sl, _PI_CMD_HWVER, 0, 0)
end

"""
Returns the pigpio software version.

...
v = pi.get_pigpio_version()
...
"""
function get_pigpio_version(self::Pi)
    return _pigpio_command(self.sl, _PI_CMD_PIGPV, 0, 0)
end

"""
Clears all waveforms and any data added by calls to the
[*wave_add_**] functions.

...
pi.wave_clear()
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
pi.wave_add_new()
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

pi.set_mode(G1, pigpio.OUTPUT)
pi.set_mode(G2, pigpio.OUTPUT)

flash_500=[] # flash every 500 ms
flash_100=[] # flash every 100 ms

#                              ON     OFF  DELAY

flash_500.append(pigpio.pulse(1<<G1, 1<<G2, 500000))
flash_500.append(pigpio.pulse(1<<G2, 1<<G1, 500000))

flash_100.append(pigpio.pulse(1<<G1, 1<<G2, 100000))
flash_100.append(pigpio.pulse(1<<G2, 1<<G1, 100000))

pi.wave_clear() # clear any existing waveforms

pi.wave_add_generic(flash_500) # 500 ms flashes
f500 = pi.wave_create() # create and save id

pi.wave_add_generic(flash_100) # 100 ms flashes
f100 = pi.wave_create() # create and save id

pi.wave_send_repeat(f500)

time.sleep(4)

pi.wave_send_repeat(f100)

time.sleep(4)

pi.wave_send_repeat(f500)

time.sleep(4)

pi.wave_tx_stop() # stop waveform

pi.wave_clear() # clear all waveforms
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
pi.wave_add_serial(4, 300, 'Hello world')

pi.wave_add_serial(4, 300, b"Hello world")

pi.wave_add_serial(4, 300, b'\\x23\\x01\\x00\\x45')

pi.wave_add_serial(17, 38400, [23, 128, 234], 5000)
...
"""
function wave_add_serial(
    self::Pi, user_gpio, baud, data, offset=0, bb_bits=8, bb_stop=2)

    # pigpio message format

    # I p1 gpio
    # I p2 baud
    # I p3 len+12
    ## extension ##
    # I bb_bits
    # I bb_stop
    # I offset
    # s len data bytes
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
wid = pi.wave_create()
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
pi.wave_delete(6) # delete waveform with id 6

pi.wave_delete(0) # delete waveform with id 0
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
cbs = pi.wave_send_once(wid)
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
cbs = pi.wave_send_repeat(wid)
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
cbs = pi.wave_send_using_mode(wid, WAVE_MODE_REPEAT_SYNC)
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
wid = pi.wave_tx_at()
...
"""
function wave_tx_at(self::Pi)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVTAT, 0, 0))
end

"""
Returns 1 if a waveform is currently being transmitted,
otherwise 0.

...
pi.wave_send_once(0) # send first waveform

while pi.wave_tx_busy(): # wait for waveform to be sent
time.sleep(0.1)

pi.wave_send_once(1) # send next waveform
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
pi.wave_send_repeat(3)

time.sleep(5)

pi.wave_tx_stop()
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

pi.set_mode(GPIO, pigpio.OUTPUT);

for i in range(WAVES)
pi.wave_add_generic([
pigpio.pulse(1<<GPIO, 0, 20),
pigpio.pulse(0, 1<<GPIO, (i+1)*200)]);

wid[i] = pi.wave_create();

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

while pi.wave_tx_busy()
time.sleep(0.1);

for i in range(WAVES)
pi.wave_delete(wid[i])

pi.stop()
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
micros = pi.wave_get_micros()
...
"""
function wave_get_micros(self::Pi)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVSM, 0, 0))
end

"""
Returns the maximum possible size of a waveform in microseconds.

...
micros = pi.wave_get_max_micros()
...
"""
function wave_get_max_micros(self::Pi)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVSM, 2, 0))
end

"""
Returns the length in pulses of the current waveform.

...
pulses = pi.wave_get_pulses()
...
"""
function wave_get_pulses(self::Pi)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVSP, 0, 0))
end

"""
Returns the maximum possible size of a waveform in pulses.

...
pulses = pi.wave_get_max_pulses()
...
"""
function wave_get_max_pulses(self::Pi)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVSP, 2, 0))
end

"""
Returns the length in DMA control blocks of the current
waveform.

...
cbs = pi.wave_get_cbs()
...
"""
function wave_get_cbs(self::Pi)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVSC, 0, 0))
end

"""
Returns the maximum possible size of a waveform in DMA
control blocks.

...
cbs = pi.wave_get_max_cbs()
...
"""
function wave_get_max_cbs(self::Pi)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_WVSC, 2, 0))
end

"""
Returns a handle (>=0) for the device at the I2C bus address.

i2c_bus:= >=0.
i2c_address:= 0-0x7F.
i2c_flags:= 0, no flags are currently defined.

Normally you would only use the [*i2c_**] functions if
you are or will be connecting to the Pi over a network.  If
you will always run on the local Pi use the standard SMBus
module instead.

Physically buses 0 and 1 are available on the Pi.  Higher
numbered buses will be available if a kernel supported bus
multiplexor is being used.

For the SMBus commands the low level transactions are shown
at the end of the function description.  The following
abbreviations are used.

. .
S     (1 bit) : Start bit
P     (1 bit) : Stop bit
Rd/Wr (1 bit) : Read/Write bit. Rd equals 1, Wr equals 0.
A, NA (1 bit) : Accept and not accept bit.
Addr  (7 bits): I2C 7 bit address.
reg   (8 bits): Command byte, which often selects a register.
Data  (8 bits): A data byte.
Count (8 bits): A byte defining the length of a block operation.

[..]: Data sent by the device.
. .

...
h = pi.i2c_open(1, 0x53) # open device at address 0x53 on bus 1
...
"""
function i2c_open(self::Pi, i2c_bus, i2c_address, i2c_flags=0)
    # I p1 i2c_bus
    # I p2 i2c_addr
    # I p3 4
    ## extension ##
    # I i2c_flags
    extents = [pack("I", i2c_flags)]
    return _u2i(_pigpio_command_ext(
        self.sl, _PI_CMD_I2CO, i2c_bus, i2c_address, 4, extents))
end

"""
Closes the I2C device associated with handle.

handle:= >=0 (as returned by a prior call to [*i2c_open*]).

...
pi.i2c_close(h)
...
"""
function i2c_close(self::Pi, handle)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_I2CC, handle, 0))
end

"""
Sends a single bit to the device associated with handle.

handle:= >=0 (as returned by a prior call to [*i2c_open*]).
bit:= 0 or 1, the value to write.

SMBus 2.0 5.5.1 - Quick command.
. .
S Addr bit [A] P
. .

...
pi.i2c_write_quick(0, 1) # send 1 to device 0
pi.i2c_write_quick(3, 0) # send 0 to device 3
...
"""
function i2c_write_quick(self::Pi, handle, bit)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_I2CWQ, handle, bit))
end

"""
Sends a single byte to the device associated with handle.

handle:= >=0 (as returned by a prior call to [*i2c_open*]).
byte_val:= 0-255, the value to write.

SMBus 2.0 5.5.2 - Send byte.
. .
S Addr Wr [A] byte_val [A] P
. .

...
pi.i2c_write_byte(1, 17)   # send byte   17 to device 1
pi.i2c_write_byte(2, 0x23) # send byte 0x23 to device 2
...
"""
function i2c_write_byte(self::Pi, handle, byte_val)
    return _u2i(
        _pigpio_command(self.sl, _PI_CMD_I2CWS, handle, byte_val))
end

"""
Reads a single byte from the device associated with handle.

handle:= >=0 (as returned by a prior call to [*i2c_open*]).

SMBus 2.0 5.5.3 - Receive byte.
. .
S Addr Rd [A] [Data] NA P
. .

...
b = pi.i2c_read_byte(2) # read a byte from device 2
...
"""
function i2c_read_byte(self::Pi, handle)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_I2CRS, handle, 0))
end

"""
Writes a single byte to the specified register of the device
associated with handle.

handle:= >=0 (as returned by a prior call to [*i2c_open*]).
reg:= >=0, the device register.
byte_val:= 0-255, the value to write.

SMBus 2.0 5.5.4 - Write byte.
. .
S Addr Wr [A] reg [A] byte_val [A] P
. .

...
# send byte 0xC5 to reg 2 of device 1
pi.i2c_write_byte_data(1, 2, 0xC5)

# send byte 9 to reg 4 of device 2
pi.i2c_write_byte_data(2, 4, 9)
...
"""
function i2c_write_byte_data(self::Pi, handle, reg, byte_val)
    # I p1 handle
    # I p2 reg
    # I p3 4
    ## extension ##
    # I byte_val
    extents = IOBuffer
    write(extents, byte_val)
    return _u2i(_pigpio_command_ext(
        self.sl, _PI_CMD_I2CWB, handle, reg, 4, extents))
end

"""
Writes a single 16 bit word to the specified register of the
device associated with handle.

handle:= >=0 (as returned by a prior call to [*i2c_open*]).
reg:= >=0, the device register.
word_val:= 0-65535, the value to write.

SMBus 2.0 5.5.4 - Write word.
. .
S Addr Wr [A] reg [A] word_val_Low [A] word_val_High [A] P
. .

...
# send word 0xA0C5 to reg 5 of device 4
pi.i2c_write_word_data(4, 5, 0xA0C5)

# send word 2 to reg 2 of device 5
pi.i2c_write_word_data(5, 2, 23)
...
"""
function i2c_write_word_data(self::Pi, handle, reg, word_val)
    # I p1 handle
    # I p2 reg
    # I p3 4
    ## extension ##
    # I word_val
    extents = IOBuffer
    write(extents, word_val)
    return _u2i(_pigpio_command_ext(
        self.sl, _PI_CMD_I2CWW, handle, reg, 4, extents))
end

"""
Reads a single byte from the specified register of the device
associated with handle.

handle:= >=0 (as returned by a prior call to [*i2c_open*]).
reg:= >=0, the device register.

SMBus 2.0 5.5.5 - Read byte.
. .
S Addr Wr [A] reg [A] S Addr Rd [A] [Data] NA P
. .

...
# read byte from reg 17 of device 2
b = pi.i2c_read_byte_data(2, 17)

# read byte from reg  1 of device 0
b = pi.i2c_read_byte_data(0, 1)
...
"""
function i2c_read_byte_data(self, handle, reg)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_I2CRB, handle, reg))
end

"""
Reads a single 16 bit word from the specified register of the
device associated with handle.

handle:= >=0 (as returned by a prior call to [*i2c_open*]).
reg:= >=0, the device register.

SMBus 2.0 5.5.5 - Read word.
. .
S Addr Wr [A] reg [A] S Addr Rd [A] [DataLow] A [DataHigh] NA P
. .

...
# read word from reg 2 of device 3
w = pi.i2c_read_word_data(3, 2)

# read word from reg 7 of device 2
w = pi.i2c_read_word_data(2, 7)
...
"""
function i2c_read_word_data(self, handle, reg)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_I2CRW, handle, reg))
end

"""
Writes 16 bits of data to the specified register of the device
associated with handle and reads 16 bits of data in return.

handle:= >=0 (as returned by a prior call to [*i2c_open*]).
reg:= >=0, the device register.
word_val:= 0-65535, the value to write.

SMBus 2.0 5.5.6 - Process call.
. .
S Addr Wr [A] reg [A] word_val_Low [A] word_val_High [A]
S Addr Rd [A] [DataLow] A [DataHigh] NA P
. .

...
r = pi.i2c_process_call(h, 4, 0x1231)
r = pi.i2c_process_call(h, 6, 0)
...
"""
function i2c_process_call(self, handle, reg, word_val)
    # I p1 handle
    # I p2 reg
    # I p3 4
    ## extension ##
    # I word_val
    extents = IOBuffer
    write(extents, word_val)
    return _u2i(_pigpio_command_ext(
        self.sl, _PI_CMD_I2CPC, handle, reg, 4, extents))
end

"""
Writes up to 32 bytes to the specified register of the device
associated with handle.

handle:= >=0 (as returned by a prior call to [*i2c_open*]).
reg:= >=0, the device register.
data:= the bytes to write.

SMBus 2.0 5.5.7 - Block write.
. .
S Addr Wr [A] reg [A] length(data) [A] data0 [A] data1 [A] ... [A]
datan [A] P
. .

...
pi.i2c_write_block_data(4, 5, b'hello')

pi.i2c_write_block_data(4, 5, "data bytes")

pi.i2c_write_block_data(5, 0, b'\\x00\\x01\\x22')

pi.i2c_write_block_data(6, 2, [0, 1, 0x22])
...
"""
function i2c_write_block_data(self, handle, reg, data)
# I p1 handle
# I p2 reg
# I p3 len
## extension ##
# s len data bytes
    if length(data)
        return _u2i(_pigpio_command_ext(
            self.sl, _PI_CMD_I2CWK, handle, reg, length(data), data))
    else
        return 0
    end
end

"""
Reads a block of up to 32 bytes from the specified register of
the device associated with handle.

handle:= >=0 (as returned by a prior call to [*i2c_open*]).
reg:= >=0, the device register.

SMBus 2.0 5.5.7 - Block read.
. .
S Addr Wr [A] reg [A]
S Addr Rd [A] [Count] A [Data] A [Data] A ... A [Data] NA P
. .

The amount of returned data is set by the device.

The returned value is a tuple of the number of bytes read and a
bytearray containing the bytes.  If there was an error the
number of bytes read will be less than zero (and will contain
the error code).

...
(b, d) = pi.i2c_read_block_data(h, 10)
if b >= 0
# process data
else
# process read failure
...
"""
function i2c_read_block_data(self::Pi, handle, reg)
    # Don't raise exception.  Must release lock.
    bytes = u2i(_pigpio_command(self.sl, _PI_CMD_I2CRK, handle, reg, false))
    if bytes > 0
        data = rxbuf(bytes)
    else
        data = ""
    end

    unlock(self.sl.l)
    return bytes, data
end

"""
Writes data bytes to the specified register of the device
associated with handle and reads a device specified number
of bytes of data in return.

handle:= >=0 (as returned by a prior call to [*i2c_open*]).
reg:= >=0, the device register.
data:= the bytes to write.

The SMBus 2.0 documentation states that a minimum of 1 byte may
be sent and a minimum of 1 byte may be received.  The total
number of bytes sent/received must be 32 or less.

SMBus 2.0 5.5.8 - Block write-block read.
. .
S Addr Wr [A] reg [A] length(data) [A] data0 [A] ... datan [A]
S Addr Rd [A] [Count] A [Data] ... A P
. .

The returned value is a tuple of the number of bytes read and a
bytearray containing the bytes.  If there was an error the
number of bytes read will be less than zero (and will contain
the error code).

...
(b, d) = pi.i2c_block_process_call(h, 10, b'\\x02\\x05\\x00')

(b, d) = pi.i2c_block_process_call(h, 10, b'abcdr')

(b, d) = pi.i2c_block_process_call(h, 10, "abracad")

(b, d) = pi.i2c_block_process_call(h, 10, [2, 5, 16])
...
"""
function i2c_block_process_call(self::Pi, handle, reg, data)
    # I p1 handle
    # I p2 reg
    # I p3 len
    ## extension ##
    # s len data bytes

    # Don't raise exception.  Must release lock.
    bytes = u2i(_pigpio_command_ext(
    self.sl, _PI_CMD_I2CPK, handle, reg, length(data), data, false))
    if bytes > 0
        data = rxbuf(self, bytes)
    else
        data = ""
    end
    unlock(self.sl.l)
    return bytes, data
end

"""
Writes data bytes to the specified register of the device
associated with handle .  1-32 bytes may be written.

handle:= >=0 (as returned by a prior call to [*i2c_open*]).
reg:= >=0, the device register.
data:= the bytes to write.

. .
S Addr Wr [A] reg [A] data0 [A] data1 [A] ... [A] datan [NA] P
. .

...
pi.i2c_write_i2c_block_data(4, 5, 'hello')

pi.i2c_write_i2c_block_data(4, 5, b'hello')

pi.i2c_write_i2c_block_data(5, 0, b'\\x00\\x01\\x22')

pi.i2c_write_i2c_block_data(6, 2, [0, 1, 0x22])
...
"""
function i2c_write_i2c_block_data(self::Pi, handle, reg, data)
    # I p1 handle
    # I p2 reg
    # I p3 len
    ## extension ##
    # s len data bytes
    if length(data) > 0
        return _u2i(_pigpio_command_ext(
            self.sl, _PI_CMD_I2CWI, handle, reg, length(data), [data]))
    else
        return 0
    end
end

"""
Reads count bytes from the specified register of the device
associated with handle .  The count may be 1-32.

handle:= >=0 (as returned by a prior call to [*i2c_open*]).
reg:= >=0, the device register.
count:= >0, the number of bytes to read.

. .
S Addr Wr [A] reg [A]
S Addr Rd [A] [Data] A [Data] A ... A [Data] NA P
. .

The returned value is a tuple of the number of bytes read and a
bytearray containing the bytes.  If there was an error the
number of bytes read will be less than zero (and will contain
the error code).

...
(b, d) = pi.i2c_read_i2c_block_data(h, 4, 32)
if b >= 0
# process data
else
# process read failure
...
"""
function i2c_read_i2c_block_data(self::Pi, handle, reg, count)
    # I p1 handle
    # I p2 reg
    # I p3 4
    ## extension ##
    # I count
    extents = IOBuffer()
    write(extents, count)
    # Don't raise exception.  Must release lock.
    bytes = u2i(_pigpio_command_ext(
    self.sl, _PI_CMD_I2CRI, handle, reg, 4, extents, false))
    if bytes > 0
        data = rxbuf(self, bytes)
    else
        data = ""
    end

    unlock(self.sl.l)
    return bytes, data
end

"""
Returns count bytes read from the raw device associated
with handle.

handle:= >=0 (as returned by a prior call to [*i2c_open*]).
count:= >0, the number of bytes to read.

. .
S Addr Rd [A] [Data] A [Data] A ... A [Data] NA P
. .

The returned value is a tuple of the number of bytes read and a
bytearray containing the bytes.  If there was an error the
number of bytes read will be less than zero (and will contain
the error code).

...
(count, data) = pi.i2c_read_device(h, 12)
...
"""
function i2c_read_device(self::Pi, handle, count)
    # Don't raise exception.  Must release lock.
    bytes = u2i(
    _pigpio_command(self.sl, _PI_CMD_I2CRD, handle, count, false))
    if bytes > 0
        data = rxbuf(self, bytes)
    else
        data = ""
    end
    unlock(self.sl.l)
    return bytes, data
end

"""
Writes the data bytes to the raw device associated with handle.

handle:= >=0 (as returned by a prior call to [*i2c_open*]).
data:= the bytes to write.

. .
S Addr Wr [A] data0 [A] data1 [A] ... [A] datan [A] P
. .

...
pi.i2c_write_device(h, b"\\x12\\x34\\xA8")

pi.i2c_write_device(h, b"help")

pi.i2c_write_device(h, 'help')

pi.i2c_write_device(h, [23, 56, 231])
...
"""
function i2c_write_device(self::Pi, handle, data)
    # I p1 handle
    # I p2 0
    # I p3 len
    ## extension ##
    # s len data bytes
    if length(data)
        return _u2i(_pigpio_command_ext(
            self.sl, _PI_CMD_I2CWD, handle, 0, length(data), data))
    else
        return 0
    end
end

"""
This function executes a sequence of I2C operations.  The
operations to be performed are specified by the contents of data
which contains the concatenated command codes and associated data.

handle:= >=0 (as returned by a prior call to [*i2c_open*]).
data:= the concatenated I2C commands, see below

The returned value is a tuple of the number of bytes read and a
bytearray containing the bytes.  If there was an error the
number of bytes read will be less than zero (and will contain
the error code).

...
(count, data) = pi.i2c_zip(h, [4, 0x53, 7, 1, 0x32, 6, 6, 0])
...

The following command codes are supported

Name    @ Cmd & Data @ Meaning
End     @ 0          @ No more commands
Escape  @ 1          @ Next P is two bytes
On      @ 2          @ Switch combined flag on
Off     @ 3          @ Switch combined flag off
Address @ 4 P        @ Set I2C address to P
Flags   @ 5 lsb msb  @ Set I2C flags to lsb + (msb << 8)
Read    @ 6 P        @ Read P bytes of data
Write   @ 7 P ...    @ Write P bytes of data

The address, read, and write commands take a parameter P.
Normally P is one byte (0-255).  If the command is preceded by
the Escape command then P is two bytes (0-65535, least significant
byte first).

The address defaults to that associated with the handle.
The flags default to 0.  The address and flags maintain their
previous value until updated.

Any read I2C data is concatenated in the returned bytearray.

...
Set address 0x53, write 0x32, read 6 bytes
Set address 0x1E, write 0x03, read 6 bytes
Set address 0x68, write 0x1B, read 8 bytes
End

0x04 0x53   0x07 0x01 0x32   0x06 0x06
0x04 0x1E   0x07 0x01 0x03   0x06 0x06
0x04 0x68   0x07 0x01 0x1B   0x06 0x08
0x00
...
"""
function i2c_zip(self::Pi, handle, data)
    # I p1 handle
    # I p2 0
    # I p3 len
    ## extension ##
    # s len data bytes

    # Don't raise exception.  Must release lock.
    bytes = u2i(_pigpio_command_ext(
    self.sl, _PI_CMD_I2CZ, handle, 0, length(data), data, false))
    if bytes > 0
        data = self._rxbuf(bytes)
    else
        data = ""
    end
    unlock(self.sl.l)
    return bytes, data
end

"""
This function selects a pair of GPIO for bit banging I2C at a
specified baud rate.

Bit banging I2C allows for certain operations which are not possible
with the standard I2C driver.

o baud rates as low as 50
o repeated starts
o clock stretching
o I2C on any pair of spare GPIO

SDA:= 0-31
SCL:= 0-31
baud:= 50-500000

Returns 0 if OK, otherwise PI_BAD_USER_GPIO, PI_BAD_I2C_BAUD, or
PI_GPIO_IN_USE.

NOTE

The GPIO used for SDA and SCL must have pull-ups to 3V3 connected.
As a guide the hardware pull-ups on pins 3 and 5 are 1k8 in value.

...
h = pi.bb_i2c_open(4, 5, 50000) # bit bang on GPIO 4/5 at 50kbps
...
"""
function bb_i2c_open(self::Pi, SDA, SCL, baud=100000)
    # I p1 SDA
    # I p2 SCL
    # I p3 4
    ## extension ##
    # I baud
    extents = IOBuffer()
    write(extents, baud)
    return _u2i(_pigpio_command_ext(
        self.sl, _PI_CMD_BI2CO, SDA, SCL, 4, extents))
end

"""
This function stops bit banging I2C on a pair of GPIO
previously opened with [*bb_i2c_open*].

SDA:= 0-31, the SDA GPIO used in a prior call to [*bb_i2c_open*]

Returns 0 if OK, otherwise PI_BAD_USER_GPIO, or PI_NOT_I2C_GPIO.

...
pi.bb_i2c_close(SDA)
...
"""
function bb_i2c_close(self::Pi, SDA)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_BI2CC, SDA, 0))
end

"""
This function executes a sequence of bit banged I2C operations.
The operations to be performed are specified by the contents
of data which contains the concatenated command codes and
associated data.

SDA:= 0-31 (as used in a prior call to [*bb_i2c_open*])
data:= the concatenated I2C commands, see below

The returned value is a tuple of the number of bytes read and a
bytearray containing the bytes.  If there was an error the
number of bytes read will be less than zero (and will contain
the error code).

...
(count, data) = pi.bb_i2c_zip(
             h, [4, 0x53, 2, 7, 1, 0x32, 2, 6, 6, 3, 0])
...

The following command codes are supported

Name    @ Cmd & Data   @ Meaning
End     @ 0            @ No more commands
Escape  @ 1            @ Next P is two bytes
Start   @ 2            @ Start condition
Stop    @ 3            @ Stop condition
Address @ 4 P          @ Set I2C address to P
Flags   @ 5 lsb msb    @ Set I2C flags to lsb + (msb << 8)
Read    @ 6 P          @ Read P bytes of data
Write   @ 7 P ...      @ Write P bytes of data

The address, read, and write commands take a parameter P.
Normally P is one byte (0-255).  If the command is preceded by
the Escape command then P is two bytes (0-65535, least significant
byte first).

The address and flags default to 0.  The address and flags maintain
their previous value until updated.

No flags are currently defined.

Any read I2C data is concatenated in the returned bytearray.

...
Set address 0x53
start, write 0x32, (re)start, read 6 bytes, stop
Set address 0x1E
start, write 0x03, (re)start, read 6 bytes, stop
Set address 0x68
start, write 0x1B, (re)start, read 8 bytes, stop
End

0x04 0x53
0x02 0x07 0x01 0x32   0x02 0x06 0x06 0x03

0x04 0x1E
0x02 0x07 0x01 0x03   0x02 0x06 0x06 0x03

0x04 0x68
0x02 0x07 0x01 0x1B   0x02 0x06 0x08 0x03

0x00
...
"""
function bb_i2c_zip(self::Pi, SDA, data)
    # I p1 SDA
    # I p2 0
    # I p3 len
    ## extension ##
    # s len data bytes

    # Don't raise exception.  Must release lock.
    bytes = u2i(_pigpio_command_ext(
    self.sl, _PI_CMD_BI2CZ, SDA, 0, length(data), [data], false))
    if bytes > 0
        data = self._rxbuf(bytes)
    else
        data = ""
    end
    unlock(self.sl.l)
    return bytes, data
end

"""
Returns a handle for the SPI device on channel.  Data will be
transferred at baud bits per second.  The flags may be used to
modify the default behaviour of 4-wire operation, mode 0,
active low chip select.

An auxiliary SPI device is available on all models but the
A and B and may be selected by setting the A bit in the
flags. The auxiliary device has 3 chip selects and a
selectable word size in bits.

spi_channel:= 0-1 (0-2 for the auxiliary SPI device).
 baud:= 32K-125M (values above 30M are unlikely to work).
spi_flags:= see below.

Normally you would only use the [*spi_**] functions if
you are or will be connecting to the Pi over a network.  If
you will always run on the local Pi use the standard SPI
module instead.

spi_flags consists of the least significant 22 bits.

. .
21 20 19 18 17 16 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
b  b  b  b  b  b  R  T  n  n  n  n  W  A u2 u1 u0 p2 p1 p0  m  m
. .

mm defines the SPI mode.

WARNING: modes 1 and 3 do not appear to work on
the auxiliary device.

. .
Mode POL PHA
0    0   0
1    0   1
2    1   0
3    1   1
. .

px is 0 if CEx is active low (default) and 1 for active high.

ux is 0 if the CEx GPIO is reserved for SPI (default)
and 1 otherwise.

A is 0 for the standard SPI device, 1 for the auxiliary SPI.

W is 0 if the device is not 3-wire, 1 if the device is 3-wire.
Standard SPI device only.

nnnn defines the number of bytes (0-15) to write before
switching the MOSI line to MISO to read data.  This field
is ignored if W is not set.  Standard SPI device only.

T is 1 if the least significant bit is transmitted on MOSI
first, the default (0) shifts the most significant bit out
first.  Auxiliary SPI device only.

R is 1 if the least significant bit is received on MISO
first, the default (0) receives the most significant bit
first.  Auxiliary SPI device only.

bbbbbb defines the word size in bits (0-32).  The default (0)
sets 8 bits per word.  Auxiliary SPI device only.

The [*spi_read*], [*spi_write*], and [*spi_xfer*] functions
transfer data packed into 1, 2, or 4 bytes according to
the word size in bits.

For bits 1-8 there will be one byte per character.
For bits 9-16 there will be two bytes per character.
For bits 17-32 there will be four bytes per character.

E.g. 32 12-bit words will be transferred in 64 bytes.

The other bits in flags should be set to zero.

...
# open SPI device on channel 1 in mode 3 at 50000 bits per second

h = pi.spi_open(1, 50000, 3)
...
"""
function spi_open(self::Pi, spi_channel, baud, spi_flags=0)
    # I p1 spi_channel
    # I p2 baud
    # I p3 4
    ## extension ##
    # I spi_flags
    extents=IOBuffer()
    write(extents, spi_flags::Cint)
    return _u2i(_pigpio_command_ext(
        self.sl, _PI_CMD_SPIO, spi_channel, baud, 4, extents))
end

"""
Closes the SPI device associated with handle.

handle:= >=0 (as returned by a prior call to [*spi_open*]).

...
pi.spi_close(h)
...
"""
function spi_close(self, handle)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_SPIC, handle, 0))
end

"""
Reads count bytes from the SPI device associated with handle.

handle:= >=0 (as returned by a prior call to [*spi_open*]).
count:= >0, the number of bytes to read.

The returned value is a tuple of the number of bytes read and a
bytearray containing the bytes.  If there was an error the
number of bytes read will be less than zero (and will contain
the error code).

...
(b, d) = pi.spi_read(h, 60) # read 60 bytes from device h
if b == 60
# process read data
else
# error path
...
"""
function spi_read(self::Pi, handle, count)
    # Don't raise exception.  Must release lock.
    bytes = u2i(_pigpio_command(
    self.sl, _PI_CMD_SPIR, handle, count, false))
    if bytes > 0
        data = rxbuf(bytes)
    else
        data = ""
    end
    unlock(self.sl.l)
    return bytes, data
end

"""
Writes the data bytes to the SPI device associated with handle.

handle:= >=0 (as returned by a prior call to [*spi_open*]).
data:= the bytes to write.

...
pi.spi_write(0, b'\\x02\\xc0\\x80') # write 3 bytes to device 0

pi.spi_write(0, b'defgh')        # write 5 bytes to device 0

pi.spi_write(0, "def")           # write 3 bytes to device 0

pi.spi_write(1, [2, 192, 128])   # write 3 bytes to device 1
...
"""
function spi_write(self::Pi, handle, data)
    # I p1 handle
    # I p2 0
    # I p3 len
    ## extension ##
    # s len data bytes
    return _u2i(_pigpio_command_ext(
        self.sl, _PI_CMD_SPIW, handle, 0, length(data), data))
end

"""
Writes the data bytes to the SPI device associated with handle,
returning the data bytes read from the device.

handle:= >=0 (as returned by a prior call to [*spi_open*]).
data:= the bytes to write.

The returned value is a tuple of the number of bytes read and a
bytearray containing the bytes.  If there was an error the
number of bytes read will be less than zero (and will contain
the error code).

...
(count, rx_data) = pi.spi_xfer(h, b'\\x01\\x80\\x00')

(count, rx_data) = pi.spi_xfer(h, [1, 128, 0])

(count, rx_data) = pi.spi_xfer(h, b"hello")

(count, rx_data) = pi.spi_xfer(h, "hello")
...
"""
function spi_xfer(self::Pi, handle, data)
    # I p1 handle
    # I p2 0
    # I p3 len
    ## extension ##
    # s len data bytes

    # Don't raise exception.  Must release lock.
    bytes = u2i(_pigpio_command_ext(
    self.sl, _PI_CMD_SPIX, handle, 0, length(data), data, false))
    if bytes > 0
        data = rxbuf(bytes)
    else
        data = ""
    end
    unlock(self.sl.l)
    return bytes, data
end

"""
Returns a handle for the serial tty device opened
at baud bits per second.

tty:= the serial device to open.
baud:= baud rate in bits per second, see below.
ser_flags:= 0, no flags are currently defined.

Normally you would only use the [*serial_**] functions if
you are or will be connecting to the Pi over a network.  If
you will always run on the local Pi use the standard serial
module instead.

The baud rate must be one of 50, 75, 110, 134, 150,
200, 300, 600, 1200, 1800, 2400, 4800, 9600, 19200,
38400, 57600, 115200, or 230400.

...
h1 = pi.serial_open("/dev/ttyAMA0", 300)

h2 = pi.serial_open("/dev/ttyUSB1", 19200, 0)
...
"""
function serial_open(self::Pi, tty, baud, ser_flags=0)
    # I p1 baud
    # I p2 ser_flags
    # I p3 len
    ## extension ##
    # s len data bytes
    return _u2i(_pigpio_command_ext(
        self.sl, _PI_CMD_SERO, baud, ser_flags, length(tty), [tty]))
end

"""
Closes the serial device associated with handle.

handle:= >=0 (as returned by a prior call to [*serial_open*]).

...
pi.serial_close(h1)
...
"""
function serial_close(self::Pi, handle)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_SERC, handle, 0))
end

"""
Returns a single byte from the device associated with handle.

handle:= >=0 (as returned by a prior call to [*serial_open*]).

...
b = pi.serial_read_byte(h1)
...
"""
function serial_read_byte(self::Pi, handle)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_SERRB, handle, 0))
end

"""
Writes a single byte to the device associated with handle.

handle:= >=0 (as returned by a prior call to [*serial_open*]).
byte_val:= 0-255, the value to write.

...
pi.serial_write_byte(h1, 23)

pi.serial_write_byte(h1, ord('Z'))
...
"""
function serial_write_byte(self::Pi, handle, byte_val)
    return _u2i(
        _pigpio_command(self.sl, _PI_CMD_SERWB, handle, byte_val))
end

"""
Reads up to count bytes from the device associated with handle.

handle:= >=0 (as returned by a prior call to [*serial_open*]).
count:= >0, the number of bytes to read.

The returned value is a tuple of the number of bytes read and a
bytearray containing the bytes.  If there was an error the
number of bytes read will be less than zero (and will contain
the error code).

...
(b, d) = pi.serial_read(h2, 100)
if b > 0
# process read data
...
"""
function serial_read(self::Pi, handle, count)
    # Don't raise exception.  Must release lock.
    bytes = u2i(
    _pigpio_command(self.sl, _PI_CMD_SERR, handle, count, false))
    if bytes > 0
        data = rxbuf(bytes)
    else
        data = ""
    end
    unlock(self.sl.l)
    return bytes, data
end

"""
Writes the data bytes to the device associated with handle.

handle:= >=0 (as returned by a prior call to [*serial_open*]).
data:= the bytes to write.

...
pi.serial_write(h1, b'\\x02\\x03\\x04')

pi.serial_write(h2, b'help')

pi.serial_write(h2, "hello")

pi.serial_write(h1, [2, 3, 4])
...
"""
function serial_write(self::Pi, handle, data)
    # I p1 handle
    # I p2 0
    # I p3 len
    ## extension ##
    # s len data bytes

    return _u2i(_pigpio_command_ext(
        self.sl, _PI_CMD_SERW, handle, 0, length(data), [data]))
end

"""
Returns the number of bytes available to be read from the
device associated with handle.

handle:= >=0 (as returned by a prior call to [*serial_open*]).

...
rdy = pi.serial_data_available(h1)

if rdy > 0
(b, d) = pi.serial_read(h1, rdy)
...
"""
function serial_data_available(self::Pi, handle)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_SERDA, handle, 0))
end

"""
Send a trigger pulse to a GPIO.  The GPIO is set to
level for pulse_len microseconds and then reset to not level.

user_gpio:= 0-31
pulse_len:= 1-100
level:= 0-1

...
pi.gpio_trigger(23, 10, 1)
...
"""
function gpio_trigger(self::Pi, user_gpio, pulse_len=10, level=1)
    # pigpio message format

    # I p1 user_gpio
    # I p2 pulse_len
    # I p3 4
    ## extension ##
    # I level
    extents = IOBuffer()
    write(extents, level::Cint)
    return _u2i(_pigpio_command_ext(
        self.sl, _PI_CMD_TRIG, user_gpio, pulse_len, 4, extents))
end

"""
Sets a glitch filter on a GPIO.

Level changes on the GPIO are not reported unless the level
has been stable for at least [*steady*] microseconds.  The
level is then reported.  Level changes of less than [*steady*]
microseconds are ignored.

user_gpio:= 0-31
steady:= 0-300000

Returns 0 if OK, otherwise PI_BAD_USER_GPIO, or PI_BAD_FILTER.

Note, each (stable) edge will be timestamped [*steady*]
microseconds after it was first detected.

...
pi.set_glitch_filter(23, 100)
...
"""
function set_glitch_filter(self, user_gpio, steady)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_FG, user_gpio, steady))
end

"""
Sets a noise filter on a GPIO.

Level changes on the GPIO are ignored until a level which has
been stable for [*steady*] microseconds is detected.  Level
changes on the GPIO are then reported for [*active*]
microseconds after which the process repeats.

user_gpio:= 0-31
steady:= 0-300000
active:= 0-1000000

Returns 0 if OK, otherwise PI_BAD_USER_GPIO, or PI_BAD_FILTER.

Note, level changes before and after the active period may
be reported.  Your software must be designed to cope with
such reports.

...
pi.set_noise_filter(23, 1000, 5000)
...
"""
function set_noise_filter(self, user_gpio, steady, active)
    # pigpio message format

    # I p1 user_gpio
    # I p2 steady
    # I p3 4
    ## extension ##
    # I active
    extents = IOBuffer()
    write(extents, active::Cint)
    return _u2i(_pigpio_command_ext(
        self.sl, _PI_CMD_FN, user_gpio, steady, 4, extents))
end

"""
Store a script for later execution.

See [[http://abyz.co.uk/rpi/pigpio/pigs.html#Scripts]] for
details.

script:= the script text as a series of bytes.

Returns a >=0 script id if OK.

...
sid = pi.store_script(
b'tag 0 w 22 1 mils 100 w 22 0 mils 100 dcr p0 jp 0')
...
"""
function store_script(self::Pi, script)
    # I p1 0
    # I p2 0
    # I p3 len
    ## extension ##
    # s len data bytes
    if length(script)
        return _u2i(_pigpio_command_ext(
            self.sl, _PI_CMD_PROC, 0, 0, length(script), [script]))
    else
        return 0
    end
end

"""
Runs a stored script.

script_id:= id of stored script.
params:= up to 10 parameters required by the script.

...
s = pi.run_script(sid, [par1, par2])

s = pi.run_script(sid)

s = pi.run_script(sid, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
...
"""
function run_script(self::Pi, script_id, params=nothing)
    # I p1 script id
    # I p2 0
    # I p3 params * 4 (0-10 params)
    ## (optional) extension ##
    # I[] params

    if params != nothing
        ext=IOBuffer()
        for p in params
            write(ext, p::Cint)
        end
        nump = length(params)
        extents = [ext]
    else
        nump = 0
        extents = []
    end
    return _u2i(_pigpio_command_ext(
        self.sl, _PI_CMD_PROCR, script_id, 0, nump*4, extents))
end

"""
Returns the run status of a stored script as well as the
current values of parameters 0 to 9.

script_id:= id of stored script.

The run status may be

. .
PI_SCRIPT_INITING
PI_SCRIPT_HALTED
PI_SCRIPT_RUNNING
PI_SCRIPT_WAITING
PI_SCRIPT_FAILED
. .

The return value is a tuple of run status and a list of
the 10 parameters.  On error the run status will be negative
and the parameter list will be empty.

...
(s, pars) = pi.script_status(sid)
...
"""
function script_status(self::Pi, script_id)
    #TODO
    # Don't raise exception.  Must release lock.
    #   bytes = u2i(
    #      _pigpio_command(self.sl, _PI_CMD_PROCP, script_id, 0, false))
    #   if bytes > 0
    #      data = rxbuf(bytes)
    #      pars = struct.unpack('11i', _str(data))
    #      status = pars[0]
    #      params = pars[1:]
    #   else
    #      status = bytes
    #      params = ()
    #   self.sl.l.release()
    #   return status, params
end

"""
Stops a running script.

script_id:= id of stored script.

...
status = pi.stop_script(sid)
...
"""
function stop_script(self::Pi, script_id)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_PROCS, script_id, 0))
end

"""
Deletes a stored script.

script_id:= id of stored script.

...
status = pi.delete_script(sid)
...
"""
function delete_script(self::Pi, script_id)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_PROCD, script_id, 0))
end

"""
Opens a GPIO for bit bang reading of serial data.

user_gpio:= 0-31, the GPIO to use.
baud:= 50-250000, the baud rate.
bb_bits:= 1-32, the number of bits per word, default 8.

The serial data is held in a cyclic buffer and is read using
[*bb_serial_read*].

It is the caller's responsibility to read data from the cyclic
buffer in a timely fashion.

...
status = pi.bb_serial_read_open(4, 19200)
status = pi.bb_serial_read_open(17, 9600)
...
"""
function bb_serial_read_open(self, user_gpio, baud, bb_bits=8)
    # pigpio message format

    # I p1 user_gpio
    # I p2 baud
    # I p3 4
    ## extension ##
    # I bb_bits
    extents = IOBuffer()
    write(extents, bb_bits::Cuint)
    return _u2i(_pigpio_command_ext(
        self.sl, _PI_CMD_SLRO, user_gpio, baud, 4, extents))
end

"""
Returns data from the bit bang serial cyclic buffer.

user_gpio:= 0-31 (opened in a prior call to [*bb_serial_read_open*])

The returned value is a tuple of the number of bytes read and a
bytearray containing the bytes.  If there was an error the
number of bytes read will be less than zero (and will contain
the error code).

The bytes returned for each character depend upon the number of
data bits [*bb_bits*] specified in the [*bb_serial_read_open*]
command.

For [*bb_bits*] 1-8 there will be one byte per character.
For [*bb_bits*] 9-16 there will be two bytes per character.
For [*bb_bits*] 17-32 there will be four bytes per character.

...
(count, data) = pi.bb_serial_read(4)
...
"""
function bb_serial_read(self, user_gpio)
    # Don't raise exception.  Must release lock.
    bytes = u2i(
        _pigpio_command(self.sl, _PI_CMD_SLR, user_gpio, 10000, false))
    if bytes > 0
        data = self._rxbuf(bytes)
    else
        data = ""
    end
    unlock(self.sl.l)
    return bytes, data
end

"""
Closes a GPIO for bit bang reading of serial data.

user_gpio:= 0-31 (opened in a prior call to [*bb_serial_read_open*])

...
status = pi.bb_serial_read_close(17)
...
"""
function bb_serial_read_close(self, user_gpio)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_SLRC, user_gpio, 0))
end

"""
Invert serial logic.

user_gpio:= 0-31 (opened in a prior call to [*bb_serial_read_open*])
invert:= 0-1 (1 invert, 0 normal)

...
status = pi.bb_serial_invert(17, 1)
...
"""
function bb_serial_invert(self, user_gpio, invert)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_SLRI, user_gpio, invert))
end

"""
Calls a pigpio function customised by the user.

arg1:= >=0, default 0.
arg2:= >=0, default 0.
argx:= extra arguments (each 0-255), default empty.

The returned value is an integer which by convention
should be >=0 for OK and <0 for error.

...
value = pi.custom_1()

value = pi.custom_1(23)

value = pi.custom_1(0, 55)

value = pi.custom_1(23, 56, [1, 5, 7])

value = pi.custom_1(23, 56, b"hello")

value = pi.custom_1(23, 56, "hello")
...
"""
function custom_1(self, arg1=0, arg2=0, argx=[])
    # I p1 arg1
    # I p2 arg2
    # I p3 len
    ## extension ##
    # s len argx bytes

    return u2i(_pigpio_command_ext(
        self.sl, _PI_CMD_CF1, arg1, arg2, length(argx), [argx]))
end

"""
Calls a pigpio function customised by the user.

arg1:= >=0, default 0.
argx:= extra arguments (each 0-255), default empty.
retMax:= >=0, maximum number of bytes to return, default 8192.

The returned value is a tuple of the number of bytes
returned and a bytearray containing the bytes.  If
there was an error the number of bytes read will be
less than zero (and will contain the error code).

...
(count, data) = pi.custom_2()

(count, data) = pi.custom_2(23)

(count, data) = pi.custom_2(23, [1, 5, 7])

(count, data) = pi.custom_2(23, b"hello")

(count, data) = pi.custom_2(23, "hello", 128)
...
"""
function custom_2(self, arg1=0, argx=[], retMax=8192)
    # I p1 arg1
    # I p2 retMax
    # I p3 len
    ## extension ##
    # s len argx bytes

    # Don't raise exception.  Must release lock.
    bytes = u2i(_pigpio_command_ext(
    self.sl, _PI_CMD_CF2, arg1, retMax, length(argx), [argx], false))
    if bytes > 0
        data = rxbuf(bytes)
    else
        data = ""
    end
    unlock(self.sl.l)
    return bytes, data
end

"""
Calls a user supplied function (a callback) whenever the
specified GPIO edge is detected.

user_gpio:= 0-31.
edge:= EITHER_EDGE, RISING_EDGE (default), or FALLING_EDGE.
func:= user supplied callback function.

The user supplied callback receives three parameters, the GPIO,
the level, and the tick.

If a user callback is not specified a default tally callback is
provided which simply counts edges.  The count may be retrieved
by calling the tally function.  The count may be reset to zero
by calling the reset_tally function.

The callback may be cancelled by calling the cancel function.

A GPIO may have multiple callbacks (although I can't think of
a reason to do so).

...
end

function cbf(gpio, level, tick)
print(gpio, level, tick)

cb1 = pi.callback(22, pigpio.EITHER_EDGE, cbf)

cb2 = pi.callback(4, pigpio.EITHER_EDGE)

cb3 = pi.callback(17)

print(cb3.tally())

cb3.reset_tally()

cb1.cancel() # To cancel callback cb1.
...
"""
function callback(self::Pi, user_gpio, edge=RISING_EDGE, func=nothing)
    return _callback(self._notify, user_gpio, edge, func)
end

"""
Wait for an edge event on a GPIO.

user_gpio:= 0-31.
  edge:= EITHER_EDGE, RISING_EDGE (default), or
         FALLING_EDGE.
wait_timeout:= >=0.0 (default 60.0).

The function returns when the edge is detected or after
the number of seconds specified by timeout has expired.

Do not use this function for precise timing purposes,
the edge is only checked 20 times a second. Whenever
you need to know the accurate time of GPIO events use
a [*callback*] function.

The function returns true if the edge is detected,
otherwise false.

...
if pi.wait_for_edge(23)
print("Rising edge detected")
else
print("wait for edge timed out")

if pi.wait_for_edge(23, pigpio.FALLING_EDGE, 5.0)
print("Falling edge detected")
else
print("wait for falling edge timed out")
...
"""
function wait_for_edge(self::Pi, user_gpio, edge=RISING_EDGE, wait_timeout=60.0)
    a = _wait_for_edge(self.notify, user_gpio, edge, wait_timeout)
    return a.trigger
end

"""
Grants access to a Pi's GPIO.

host:= the host name of the Pi on which the pigpio daemon is
 running.  The default is localhost unless overridden by
 the PIGPIO_ADDR environment variable.

port:= the port number on which the pigpio daemon is listening.
 The default is 8888 unless overridden by the PIGPIO_PORT
 environment variable.  The pigpio daemon must have been
 started with the same port number.

This connects to the pigpio daemon and reserves resources
to be used for sending commands and receiving notifications.

An instance attribute [*connected*] may be used to check the
success of the connection.  If the connection is established
successfully [*connected*] will be true, otherwise false.

...
pi = pigio.pi()              # use defaults
pi = pigpio.pi('mypi')       # specify host, default port
pi = pigpio.pi('mypi', 7777) # specify host and port

pi = pigpio.pi()             # exit script if no connection
if not pi.connected
exit()
...
"""
function Pi(; host = get(ENV, "PIGPIO_ADDR", ""), port = get(ENV, "PIGPIO_PORT", 8888))
    port = Int(port)
    if host == "" || host == nothing
        host = "localhost"
    end

    #self.sl.s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    #self.sl.s.settimeout(None)

    # Disable the Nagle algorithm.
    #self.sl.s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)

    sock = connect(host, port)
    sl = SockLock(sock, ReentrantLock())
    notify = CallbackThread(sl, host, port)
    self = Pi(host, port, true, sl, notify)

    try
        sock = connect(host, port)
        sl = SockLock(sock, ReentrantLock())
        notify = CallbackThread(sl, host, port)
        self = Pi(host, port, true, sl, notify)
        #atexit.register(self.stop) #TODO

    catch error
        #self = Pi(host, port, false, SockLock(nothing, ReentrantLock()), nothing)

        s = "Can't connect to pigpio at $host:$port)"

        println("%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%")
        println(s)
        println("")
        println("Did you start the pigpio daemon? E.g. sudo pigpiod")
        println("")
        println("Did you specify the correct Pi host/port in the environment")
        println("variables PIGPIO_ADDR/PIGPIO_PORT?")
        println("E.g. export PIGPIO_ADDR=soft, export PIGPIO_PORT=8888")
        println("")
        println("Did you specify the correct Pi host/port in the")
        println("pigpio.pi() function? E.g. Pi('soft', 8888))")
        println("%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%")
        throw(error)
    end
end

function stop(self::Pi)
    """Release pigpio resources.

    ...
    pi.stop()
    ...
    """

    self.connected = false

    if self.notify != nothing
        stop(self.notify)
        self.notify = nothing
    end

    if self.sl.s != nothing
        close(self.sl.s)
        self.sl.s = nothing
    end
end



"""
active: 0-1000000
The number of microseconds level changes are reported for once
a noise filter has been triggered (by [*steady*] microseconds of
a stable level).


arg1
An unsigned argument passed to a user customised function.  Its
meaning is defined by the customiser.

arg2
An unsigned argument passed to a user customised function.  Its
meaning is defined by the customiser.

argx
An array of bytes passed to a user customised function.
Its meaning and content is defined by the customiser.

baud
The speed of serial communication (I2C, SPI, serial link, waves)
in bits per second.

bb_bits: 1-32
The number of data bits to be used when adding serial data to a
waveform.

bb_stop: 2-8
The number of (half) stop bits to be used when adding serial data
to a waveform.

bit: 0-1
A value of 0 or 1.

bits: 32 bit number
A mask used to select GPIO to be operated on.  If bit n is set
then GPIO n is selected.  A convenient way of setting bit n is to
bit or in the value (1<<n).

To select GPIO 1, 7, 23

bits = (1<<1) | (1<<7) | (1<<23)

byte_val: 0-255
A whole number.

clkfreq: 4689-250M
The hardware clock frequency.

connected
true if a connection was established, false otherwise.

count
The number of bytes of data to be transferred.

data
Data to be transmitted, a series of bytes.

delay: >=1
The length of a pulse in microseconds.

dutycycle: 0-range_
A number between 0 and range_.

The dutycycle sets the proportion of time on versus time off during each
PWM cycle.

Dutycycle     @ On time
0             @ Off
range_ * 0.25 @ 25% On
range_ * 0.50 @ 50% On
range_ * 0.75 @ 75% On
range_        @ Fully On

edge: 0-2
EITHER_EDGE = 2
FALLING_EDGE = 1
RISING_EDGE = 0

errnum: <0

. .
PI_BAD_USER_GPIO = -2
PI_BAD_GPIO = -3
PI_BAD_MODE = -4
PI_BAD_LEVEL = -5
PI_BAD_PUD = -6
PI_BAD_PULSEWIDTH = -7
PI_BAD_DUTYCYCLE = -8
PI_BAD_WDOG_TIMEOUT = -15
PI_BAD_DUTYRANGE = -21
PI_NO_HANDLE = -24
PI_BAD_HANDLE = -25
PI_BAD_WAVE_BAUD = -35
PI_TOO_MANY_PULSES = -36
PI_TOO_MANY_CHARS = -37
PI_NOT_SERIAL_GPIO = -38
PI_NOT_PERMITTED = -41
PI_SOME_PERMITTED = -42
PI_BAD_WVSC_COMMND = -43
PI_BAD_WVSM_COMMND = -44
PI_BAD_WVSP_COMMND = -45
PI_BAD_PULSELEN = -46
PI_BAD_SCRIPT = -47
PI_BAD_SCRIPT_ID = -48
PI_BAD_SER_OFFSET = -49
PI_GPIO_IN_USE = -50
PI_BAD_SERIAL_COUNT = -51
PI_BAD_PARAM_NUM = -52
PI_DUP_TAG = -53
PI_TOO_MANY_TAGS = -54
PI_BAD_SCRIPT_CMD = -55
PI_BAD_VAR_NUM = -56
PI_NO_SCRIPT_ROOM = -57
PI_NO_MEMORY = -58
PI_SOCK_READ_FAILED = -59
PI_SOCK_WRIT_FAILED = -60
PI_TOO_MANY_PARAM = -61
PI_SCRIPT_NOT_READY = -62
PI_BAD_TAG = -63
PI_BAD_MICS_DELAY = -64
PI_BAD_MILS_DELAY = -65
PI_BAD_WAVE_ID = -66
PI_TOO_MANY_CBS = -67
PI_TOO_MANY_OOL = -68
PI_EMPTY_WAVEFORM = -69
PI_NO_WAVEFORM_ID = -70
PI_I2C_OPEN_FAILED = -71
PI_SER_OPEN_FAILED = -72
PI_SPI_OPEN_FAILED = -73
PI_BAD_I2C_BUS = -74
PI_BAD_I2C_ADDR = -75
PI_BAD_SPI_CHANNEL = -76
PI_BAD_FLAGS = -77
PI_BAD_SPI_SPEED = -78
PI_BAD_SER_DEVICE = -79
PI_BAD_SER_SPEED = -80
PI_BAD_PARAM = -81
PI_I2C_WRITE_FAILED = -82
PI_I2C_READ_FAILED = -83
PI_BAD_SPI_COUNT = -84
PI_SER_WRITE_FAILED = -85
PI_SER_READ_FAILED = -86
PI_SER_READ_NO_DATA = -87
PI_UNKNOWN_COMMAND = -88
PI_SPI_XFER_FAILED = -89
PI_NO_AUX_SPI = -91
PI_NOT_PWM_GPIO = -92
PI_NOT_SERVO_GPIO = -93
PI_NOT_HCLK_GPIO = -94
PI_NOT_HPWM_GPIO = -95
PI_BAD_HPWM_FREQ = -96
PI_BAD_HPWM_DUTY = -97
PI_BAD_HCLK_FREQ = -98
PI_BAD_HCLK_PASS = -99
PI_HPWM_ILLEGAL = -100
PI_BAD_DATABITS = -101
PI_BAD_STOPBITS = -102
PI_MSG_TOOBIG = -103
PI_BAD_MALLOC_MODE = -104
PI_BAD_SMBUS_CMD = -107
PI_NOT_I2C_GPIO = -108
PI_BAD_I2C_WLEN = -109
PI_BAD_I2C_RLEN = -110
PI_BAD_I2C_CMD = -111
PI_BAD_I2C_BAUD = -112
PI_CHAIN_LOOP_CNT = -113
PI_BAD_CHAIN_LOOP = -114
PI_CHAIN_COUNTER = -115
PI_BAD_CHAIN_CMD = -116
PI_BAD_CHAIN_DELAY = -117
PI_CHAIN_NESTING = -118
PI_CHAIN_TOO_BIG = -119
PI_DEPRECATED = -120
PI_BAD_SER_INVERT = -121
PI_BAD_FOREVER = -124
PI_BAD_FILTER = -125
. .

frequency: 0-40000
end

functionines the frequency to be used for PWM on a GPIO.
The closest permitted frequency will be used.

func
A user supplied callback function.

gpio: 0-53
A Broadcom numbered GPIO.  All the user GPIO are in the range 0-31.

There  are 54 General Purpose Input Outputs (GPIO) named GPIO0
through GPIO53.

They are split into two  banks.   Bank  1  consists  of  GPIO0
through GPIO31.  Bank 2 consists of GPIO32 through GPIO53.

All the GPIO which are safe for the user to read and write are in
bank 1.  Not all GPIO in bank 1 are safe though.  Type 1 boards
have 17  safe GPIO.  Type 2 boards have 21.  Type 3 boards have 26.

See [*get_hardware_revision*].

The user GPIO are marked with an X in the following table.

. .
 0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15
Type 1    X  X  -  -  X  -  -  X  X  X  X  X  -  -  X  X
Type 2    -  -  X  X  X  -  -  X  X  X  X  X  -  -  X  X
Type 3          X  X  X  X  X  X  X  X  X  X  X  X  X  X

16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31
Type 1    -  X  X  -  -  X  X  X  X  X  -  -  -  -  -  -
Type 2    -  X  X  -  -  -  X  X  X  X  -  X  X  X  X  X
Type 3    X  X  X  X  X  X  X  X  X  X  X  X  -  -  -  -
. .

gpio_off
A mask used to select GPIO to be operated on.  See [*bits*].

This mask selects the GPIO to be switched off at the start
of a pulse.

gpio_on
A mask used to select GPIO to be operated on.  See [*bits*].

This mask selects the GPIO to be switched on at the start
of a pulse.

handle: >=0
A number referencing an object opened by one of [*i2c_open*],
[*notify_open*], [*serial_open*], [*spi_open*].

host
The name or IP address of the Pi running the pigpio daemon.

i2c_*
One of the i2c_ functions.

i2c_address: 0-0x7F
The address of a device on the I2C bus.

i2c_bus: >=0
An I2C bus number.

i2c_flags: 0
No I2C flags are currently defined.

invert: 0-1
A flag used to set normal or inverted bit bang serial data
level logic.

level: 0-1 (2)
CLEAR = 0
HIGH = 1
LOW = 0
OFF = 0
ON = 1
SET = 1
TIMEOUT = 2 # only returned for a watchdog timeout

mode

1.The operational mode of a GPIO, normally INPUT or OUTPUT.

ALT0 = 4
ALT1 = 5
ALT2 = 6
ALT3 = 7
ALT4 = 3
ALT5 = 2
INPUT = 0
OUTPUT = 1

2. The mode of waveform transmission.

WAVE_MODE_ONE_SHOT = 0
WAVE_MODE_REPEAT = 1
WAVE_MODE_ONE_SHOT_SYNC = 2
WAVE_MODE_REPEAT_SYNC = 3

offset: >=0
The offset wave data starts from the beginning of the waveform
being currently defined.

params: 32 bit number
When scripts are started they can receive up to 10 parameters
to define their operation.

port
The port used by the pigpio daemon, defaults to 8888.

pud: 0-2
PUD_DOWN = 1
PUD_OFF = 0
PUD_UP = 2

pulse_len: 1-100
The length of the trigger pulse in microseconds.

pulses
A list of class pulse objects defining the characteristics of a
waveform.

pulsewidth
The servo pulsewidth in microseconds.  0 switches pulses off.

PWMduty: 0-1000000 (1M)
The hardware PWM dutycycle.

PWMfreq: 1-125000000 (125M)
The hardware PWM frequency.

range_: 25-40000
end

functionines the limits for the [*dutycycle*] parameter.
range_ defaults to 255.

reg: 0-255
An I2C device register.  The usable registers depend on the
actual device.

retMax: >=0
The maximum number of bytes a user customised function
should return, default 8192.

SCL
The user GPIO to use for the clock when bit banging I2C.

script
The text of a script to store on the pigpio daemon.

script_id: >=0
A number referencing a script created by [*store_script*].

SDA
The user GPIO to use for data when bit banging I2C.

ser_flags: 32 bit
No serial flags are currently defined.

serial_*
One of the serial_ functions.

spi_*
One of the spi_ functions.

spi_channel: 0-2
A SPI channel.

spi_flags: 32 bit
See [*spi_open*].

steady: 0-300000

The number of microseconds level changes must be stable for
before reporting the level changed ([*set_glitch_filter*])
or triggering the active part of a noise filter
([*set_noise_filter*]).

t1
A tick (earlier).

t2
A tick (later).

tty
A Pi serial tty device, e.g. /dev/ttyAMA0, /dev/ttyUSB0

uint32
An unsigned 32 bit number.

user_gpio: 0-31
A Broadcom numbered GPIO.

All the user GPIO are in the range 0-31.

Not all the GPIO within this range are usable, some are reserved
for system use.

See [*gpio*].

wait_timeout: 0.0 -
The number of seconds to wait in [*wait_for_edge*] before timing out.

wave_add_*
One of [*wave_add_new*] , [*wave_add_generic*], [*wave_add_serial*].

wave_id: >=0
A number referencing a wave created by [*wave_create*].

wave_send_*
One of [*wave_send_once*], [*wave_send_repeat*].

wdog_timeout: 0-60000
end

functionines a GPIO watchdog timeout in milliseconds.  If no level
change is detected on the GPIO for timeout millisecond a watchdog
timeout report is issued (with level TIMEOUT).

word_val: 0-65535
A whole number.
"""
function xref()
end
