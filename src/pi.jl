export set_mode, get_mode, set_pull_up_down



exceptions = true
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
    dummy::Array{UInt8,1} # a bits type
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
    Base.write(sl.s, UInt32.([cmd, p1, p2, 0]))
    out = IOBuffer(Base.read(sl.s, 16))
    msg = reinterpret(Cuint, take!(out))[4]
    if rl
        unlock(sl.l)
    end
   return msg
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
    Base.write(ext, Array(reinterpret(UInt8, [cmd, p1, p2, p3])))
    for x in extents
       write(ext, string(x))
    end
    lock(sl.l)
    write(sl.s, ext)
    msg = reinterpret(Cuint, sl.s)[4]
    if rl
         unlock(sl.l)
    end
    return res
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
        Base.write(self.sl.s, _PI_CMD_NC, self.handle, 0, 0)
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


struct CallbMsg
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
            msg = reinterpret(CallbMsg, buf)
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

function Callback(notify, user_gpio::Int, edge::Int=RISING_EDGE, func=nothing)
    self = Callback(notify, 0, false, nothing)
    if func == nothing
        func = _tally
    end
    self.callb = Callback_ADT(user_gpio, edge, func)
    push!(self.notify, self.callb)
end

"""Cancels a callback by removing it from the notification thread."""
function cancel(self)
    filter(x->x!=self.callb, self.notify)
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
    callb::Function
    trigger
    start
end

"""Initialises a wait_for_edge."""
function WaitForEdge( notify, gpio::Int, edge, timeout)
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
set_mode(pi,  4, pigpio.INPUT)  # GPIO  4 as input
set_mode(pi, 17, pigpio.OUTPUT) # GPIO 17 as output
set_mode(pi, 24, pigpio.ALT2)   # GPIO 24 as ALT2
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
print(get_mode(pi, 0))
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
set_pull_up_down(pi, 17, pigpio.PUD_OFF)
set_pull_up_down(pi, 23, pigpio.PUD_UP)
set_pull_up_down(pi, 24, pigpio.PUD_DOWN)
...
"""
function set_pull_up_down(self::Pi, gpio, pud)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_PUD, gpio, pud))
end


"""
Returns the GPIO level.

gpio:= 0-53.

...
set_mode(pi, 23, pigpio.INPUT)

set_pull_up_down(pi, 23, pigpio.PUD_DOWN)
print(read(pi, 23))
0

set_pull_up_down(pi, 23, pigpio.PUD_UP)
print(read(pi, 23))
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
set_mode(pi, 17, pigpio.OUTPUT)

write(pi, 17,0)
print(read(pi, 17))
0

write(pi, 17,1)
print(read(pi, 17))
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
set_PWM_dutycycle(pi, 4,   0) # PWM off
set_PWM_dutycycle(pi, 4,  64) # PWM 1/4 on
set_PWM_dutycycle(pi, 4, 128) # PWM 1/2 on
set_PWM_dutycycle(pi, 4, 192) # PWM 3/4 on
set_PWM_dutycycle(pi, 4, 255) # PWM full on
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
set_PWM_dutycycle(pi, 4, 25)
print(get_PWM_dutycycle(pi, 4))
25

set_PWM_dutycycle(pi, 4, 203)
print(get_PWM_dutycycle(pi, 4))
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
set_PWM_range(pi, 9, 100)  # now  25 1/4,   50 1/2,   75 3/4 on
set_PWM_range(pi, 9, 500)  # now 125 1/4,  250 1/2,  375 3/4 on
set_PWM_range(pi, 9, 3000) # now 750 1/4, 1500 1/2, 2250 3/4 on
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
set_PWM_range(pi, 9, 500)
print(get_PWM_range(pi, 9))
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
set_PWM_frequency(pi, 4, 800)
print(get_PWM_real_range(pi, 4))
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
set_PWM_frequency(pi, 4,0)
print(get_PWM_frequency(pi, 4))
10

set_PWM_frequency(pi, 4,100000)
print(get_PWM_frequency(pi, 4))
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
set_PWM_frequency(pi, 4,0)
print(get_PWM_frequency(pi, 4))
10

set_PWM_frequency(pi, 4, 800)
print(get_PWM_frequency(pi, 4))
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
set_servo_pulsewidth(pi, 17, 0)    # off
set_servo_pulsewidth(pi, 17, 1000) # safe anti-clockwise
set_servo_pulsewidth(pi, 17, 1500) # centre
set_servo_pulsewidth(pi, 17, 2000) # safe clockwise
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
set_servo_pulsewidth(pi, 4, 525)
print(get_servo_pulsewidth(pi, 4))
525

set_servo_pulsewidth(pi, 4, 2130)
print(get_servo_pulsewidth(pi, 4))
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
h = notify_open(pi, )
if h >= 0
    notify_begin(pi, h, 1234)
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
h = notify_open(pi, )
if h >= 0
    notify_begin(pi, h, 1234)
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
h = notify_open(pi, )
if h >= 0
    notify_begin(pi, h, 1234)
    ...
    notify_pause(pi, h)
    ...
    notify_begin(pi, h, 1234)
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
h = notify_open(pi, )
if h >= 0
    notify_begin(pi, h, 1234)
    ...
    notify_close(pi, h)
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
set_watchdog(pi, 23, 1000) # 1000 ms watchdog on GPIO 23
set_watchdog(pi, 23, 0)    # cancel watchdog on GPIO 23
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
print(bin(read_bank_1(pi, )))
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
print(bin(read_bank_2(pi, )))
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
clear_bank_1(int(pi, "111110010000",2))
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
clear_bank_2(pi, 0x1010)
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
set_bank_1(int(pi, "111110010000",2))
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
set_bank_2(pi, 0x303)
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
hardware_clock(pi, 4, 5000) # 5 KHz clock on GPIO 4

hardware_clock(pi, 4, 40000000) # 40 MHz clock on GPIO 4
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
hardware_PWM(pi, 18, 800, 250000) # 800Hz 25% dutycycle

hardware_PWM(pi, 18, 2000, 750000) # 2000Hz 75% dutycycle
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
t1 = get_current_tick(pi, )
time.sleep(1)
t2 = get_current_tick(pi, )
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
print(get_hardware_revision(pi, ))
2
...
"""
function get_hardware_revision(self::Pi)
    return _pigpio_command(self.sl, _PI_CMD_HWVER, 0, 0)
end

"""
Returns the pigpio software version.

...
v = get_pigpio_version(pi, )
...
"""
function get_pigpio_version(self::Pi)
    return _pigpio_command(self.sl, _PI_CMD_PIGPV, 0, 0)
end

"""
Calls a pigpio function customised by the user.

arg1:= >=0, default 0.
arg2:= >=0, default 0.
argx:= extra arguments (each 0-255), default empty.

The returned value is an integer which by convention
should be >=0 for OK and <0 for error.

...
value = custom_1(pi, )

value = custom_1(pi, 23)

value = custom_1(pi, 0, 55)

value = custom_1(pi, 23, 56, [1, 5, 7])

value = custom_1(pi, 23, 56, b"hello")

value = custom_1(pi, 23, 56, "hello")
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
(count, data) = custom_2(pi, )

(count, data) = custom_2(pi, 23)

(count, data) = custom_2(pi, 23, [1, 5, 7])

(count, data) = custom_2(pi, 23, b"hello")

(count, data) = custom_2(pi, 23, "hello", 128)
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

cb1 = callback(pi, 22, pigpio.EITHER_EDGE, cbf)

cb2 = callback(pi, 4, pigpio.EITHER_EDGE)

cb3 = callback(pi, 17)

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
if wait_for_edge(pi, 23)
print("Rising edge detected")
else
print("wait for edge timed out")

if wait_for_edge(pi, 23, pigpio.FALLING_EDGE, 5.0)
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
pi = pigpio.pi()              # use defaults
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

    try
        sock = connect(host, port)
        ccall(:uv_tcp_nodelay, Cint, (Ptr{Cvoid}, Cuint), sock, 1) # Disable Nagle's Algorithm
        sl = SockLock(sock, ReentrantLock())
        notify = CallbackThread(sl, host, port)
        self = Pi(host, port, true, sl, notify)
        @info "Successfully connected!"
        return self
        #atexit.register(self.stop) #TODO
    catch error
        println("%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%")
        println("Can't connect to pigpio at $host:$port")
        println("Did you start the pigpio daemon? E.g. sudo pigpiod\n")
        println("Did you specify the correct Pi host/port in the environment")
        println("variables PIGPIO_ADDR/PIGPIO_PORT?")
        println("E.g. export PIGPIO_ADDR=soft, export PIGPIO_PORT=8888\n")
        println("Did you specify the correct Pi host/port in the")
        println("Pi() function? E.g. Pi('soft', 8888))")
        println("%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%")
        throw(error)
    end
end


"""Release pigpio resources.
...
stop(pi)
...
"""
function stop(self::Pi)
    self.connected = false
    stop(self.notify)
    close(self.sl.s)
end
