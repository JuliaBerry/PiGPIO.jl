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
h = i2c_open(pi, 1, 0x53) # open device at address 0x53 on bus 1
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
i2c_close(pi, h)
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
i2c_write_quick(pi, 0, 1) # send 1 to device 0
i2c_write_quick(pi, 3, 0) # send 0 to device 3
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
i2c_write_byte(pi, 1, 17)   # send byte   17 to device 1
i2c_write_byte(pi, 2, 0x23) # send byte 0x23 to device 2
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
b = i2c_read_byte(pi, 2) # read a byte from device 2
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
i2c_write_byte_data(pi, 1, 2, 0xC5)

# send byte 9 to reg 4 of device 2
i2c_write_byte_data(pi, 2, 4, 9)
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
i2c_write_word_data(pi, 4, 5, 0xA0C5)

# send word 2 to reg 2 of device 5
i2c_write_word_data(pi, 5, 2, 23)
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
b = i2c_read_byte_data(pi, 2, 17)

# read byte from reg  1 of device 0
b = i2c_read_byte_data(pi, 0, 1)
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
w = i2c_read_word_data(pi, 3, 2)

# read word from reg 7 of device 2
w = i2c_read_word_data(pi, 2, 7)
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
r = i2c_process_call(pi, h, 4, 0x1231)
r = i2c_process_call(pi, h, 6, 0)
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
i2c_write_block_data(pi, 4, 5, b'hello')

i2c_write_block_data(pi, 4, 5, "data bytes")

i2c_write_block_data(pi, 5, 0, b'\\x00\\x01\\x22')

i2c_write_block_data(pi, 6, 2, [0, 1, 0x22])
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
(b, d) = i2c_read_block_data(pi, h, 10)
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
(b, d) = i2c_block_process_call(pi, h, 10, b'\\x02\\x05\\x00')

(b, d) = i2c_block_process_call(pi, h, 10, b'abcdr')

(b, d) = i2c_block_process_call(pi, h, 10, "abracad")

(b, d) = i2c_block_process_call(pi, h, 10, [2, 5, 16])
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
i2c_write_i2c_block_data(pi, 4, 5, 'hello')

i2c_write_i2c_block_data(pi, 4, 5, b'hello')

i2c_write_i2c_block_data(pi, 5, 0, b'\\x00\\x01\\x22')

i2c_write_i2c_block_data(pi, 6, 2, [0, 1, 0x22])
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
(b, d) = i2c_read_i2c_block_data(pi, h, 4, 32)
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
(count, data) = i2c_read_device(pi, h, 12)
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
i2c_write_device(pi, h, b"\\x12\\x34\\xA8")

i2c_write_device(pi, h, b"help")

i2c_write_device(pi, h, 'help')

i2c_write_device(pi, h, [23, 56, 231])
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
(count, data) = i2c_zip(pi, h, [4, 0x53, 7, 1, 0x32, 6, 6, 0])
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
h = bb_i2c_open(pi, 4, 5, 50000) # bit bang on GPIO 4/5 at 50kbps
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
bb_i2c_close(pi, SDA)
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
