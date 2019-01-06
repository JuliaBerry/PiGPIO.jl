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

h = spi_open(pi, 1, 50000, 3)
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
spi_close(pi, h)
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
(b, d) = spi_read(pi, h, 60) # read 60 bytes from device h
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
spi_write(pi, 0, b'\\x02\\xc0\\x80') # write 3 bytes to device 0

spi_write(pi, 0, b'defgh')        # write 5 bytes to device 0

spi_write(pi, 0, "def")           # write 3 bytes to device 0

spi_write(pi, 1, [2, 192, 128])   # write 3 bytes to device 1
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
(count, rx_data) = spi_xfer(pi, h, b'\\x01\\x80\\x00')

(count, rx_data) = spi_xfer(pi, h, [1, 128, 0])

(count, rx_data) = spi_xfer(pi, h, b"hello")

(count, rx_data) = spi_xfer(pi, h, "hello")
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
h1 = serial_open(pi, "/dev/ttyAMA0", 300)

h2 = serial_open(pi, "/dev/ttyUSB1", 19200, 0)
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
serial_close(pi, h1)
...
"""
function serial_close(self::Pi, handle)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_SERC, handle, 0))
end

"""
Returns a single byte from the device associated with handle.

handle:= >=0 (as returned by a prior call to [*serial_open*]).

...
b = serial_read_byte(pi, h1)
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
serial_write_byte(pi, h1, 23)

serial_write_byte(h1, ord(pi, 'Z'))
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
(b, d) = serial_read(pi, h2, 100)
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
serial_write(pi, h1, b'\\x02\\x03\\x04')

serial_write(pi, h2, b'help')

serial_write(pi, h2, "hello")

serial_write(pi, h1, [2, 3, 4])
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
rdy = serial_data_available(pi, h1)

if rdy > 0
(b, d) = serial_read(pi, h1, rdy)
...
"""
function serial_data_available(self::Pi, handle)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_SERDA, handle, 0))
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
status = bb_serial_read_open(pi, 4, 19200)
status = bb_serial_read_open(pi, 17, 9600)
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
(count, data) = bb_serial_read(pi, 4)
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
status = bb_serial_read_close(pi, 17)
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
status = bb_serial_invert(pi, 17, 1)
...
"""
function bb_serial_invert(self, user_gpio, invert)
    return _u2i(_pigpio_command(self.sl, _PI_CMD_SLRI, user_gpio, invert))
end
