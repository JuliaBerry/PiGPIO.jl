# """
# pigpio is a Julia package for the Raspberry which talks to
# the pigpio daemon to allow control of the general purpose
# input outputs (GPIO).
#
# [http://abyz.co.uk/rpi/pigpio/python.html]
#
# *Features*
#
# o the pigpio Python module can run on Windows, Macs, or Linux
#
# o controls one or more Pi's
#
# o independent PWM on any of GPIO 0-31 simultaneously
#
# o independent servo pulses on any of GPIO 0-31 simultaneously
#
# o callbacks when any of GPIO 0-31 change state
#
# o creating and transmitting precisely timed waveforms
#
# o reading/writing GPIO and setting their modes
#
# o wrappers for I2C, SPI, and serial links
#
# o creating and running scripts on the pigpio daemon
#
# *GPIO*
#
# ALL GPIO are identified by their Broadcom number.
#
# *Notes*
#
# Transmitted waveforms are accurate to a microsecond.
#
# Callback level changes are time-stamped and will be
# accurate to within a few microseconds.
#
# *Settings*
#
# A number of settings are determined when the pigpio daemon is started.
#
# o the sample rate (1, 2, 4, 5, 8, or 10 us, default 5 us).
#
# o the set of GPIO which may be updated (generally written to).  The
#   end
#
#   functionault set is those available on the Pi board revision.
#
# o the available PWM frequencies (see [*set_PWM_frequency*]).
#
# *Exceptions*
#
# By default a fatal exception is raised if you pass an invalid
# argument to a pigpio function.
#
# If you wish to handle the returned status yourself you should set
# pigpio.exceptions to false.
#
# You may prefer to check the returned status in only a few parts
# of your code.  In that case do the following.
#
# ...
# pigpio.exceptions = false
#
# # Code where you want to test the error status.
#
# pigpio.exceptions = true
# ...
#
# *Usage*
#
# This module uses the services of the C pigpio library.  pigpio
# must be running on the Pi(s) whose GPIO are to be manipulated.
#
# The normal way to start pigpio is as a daemon (during system
# start).
#
# sudo pigpiod
#
# Your Python program must import pigpio and create one or more
# instances of the pigpio.pi class.  This class gives access to
# a specified Pi's GPIO.
#
# ...
# pi1 = pigpio.pi()       # pi1 accesses the local Pi's GPIO
# pi2 = pigpio.pi('tom')  # pi2 accesses tom's GPIO
# pi3 = pigpio.pi('dick') # pi3 accesses dick's GPIO
#
# pi1.write(4, 0) # set local Pi's GPIO 4 low
# pi2.write(4, 1) # set tom's GPIO 4 to high
# pi3.read(4)     # get level of dick's GPIO 4
# ...
#
# The later example code snippets assume that pi is an instance of
# the pigpio.pi class.
#
# OVERVIEW
#
# Essential
#
# pigpio.pi                 Initialise Pi connection
# stop                      Stop a Pi connection
#
# Beginner
#
# set_mode                  Set a GPIO mode
# get_mode                  Get a GPIO mode
# set_pull_up_down          Set/clear GPIO pull up/down resistor
#
# read                      Read a GPIO
# write                     Write a GPIO
#
# set_PWM_dutycycle         Start/stop PWM pulses on a GPIO
# get_PWM_dutycycle         Get PWM dutycycle set on a GPIO
#
# set_servo_pulsewidth      Start/Stop servo pulses on a GPIO
# get_servo_pulsewidth      Get servo pulsewidth set on a GPIO
#
# callback                  Create GPIO level change callback
# wait_for_edge             Wait for GPIO level change
#
# Intermediate
#
# gpio_trigger              Send a trigger pulse to a GPIO
#
# set_watchdog              Set a watchdog on a GPIO
#
# set_PWM_range             Configure PWM range of a GPIO
# get_PWM_range             Get configured PWM range of a GPIO
#
# set_PWM_frequency         Set PWM frequency of a GPIO
# get_PWM_frequency         Get PWM frequency of a GPIO
#
# read_bank_1               Read all bank 1 GPIO
# read_bank_2               Read all bank 2 GPIO
#
# clear_bank_1              Clear selected GPIO in bank 1
# clear_bank_2              Clear selected GPIO in bank 2
#
# set_bank_1                Set selected GPIO in bank 1
# set_bank_2                Set selected GPIO in bank 2
#
# Advanced
#
# get_PWM_real_range        Get underlying PWM range for a GPIO
#
# notify_open               Request a notification handle
# notify_begin              Start notifications for selected GPIO
# notify_pause              Pause notifications
# notify_close              Close a notification
#
# bb_serial_read_open       Open a GPIO for bit bang serial reads
# bb_serial_read            Read bit bang serial data from  a GPIO
# bb_serial_read_close      Close a GPIO for bit bang serial reads
# bb_serial_invert          Invert serial logic (1 invert, 0 normal)
#
# hardware_clock            Start hardware clock on supported GPIO
# hardware_PWM              Start hardware PWM on supported GPIO
#
# set_glitch_filter         Set a glitch filter on a GPIO
# set_noise_filter          Set a noise filter on a GPIO
#
# Scripts
#
# store_script              Store a script
# run_script                Run a stored script
# script_status             Get script status and parameters
# stop_script               Stop a running script
# delete_script             Delete a stored script
#
# Waves
#
# wave_clear                Deletes all waveforms
#
# wave_add_new              Starts a new waveform
# wave_add_generic          Adds a series of pulses to the waveform
# wave_add_serial           Adds serial data to the waveform
#
# wave_create               Creates a waveform from added data
# wave_delete               Deletes a waveform
#
# wave_send_once            Transmits a waveform once
# wave_send_repeat          Transmits a waveform repeatedly
# wave_send_using_mode      Transmits a waveform in the chosen mode
#
# wave_chain                Transmits a chain of waveforms
#
# wave_tx_at                Returns the current transmitting waveform
# wave_tx_busy              Checks to see if a waveform has ended
# wave_tx_stop              Aborts the current waveform
#
# wave_get_micros           Length in microseconds of the current waveform
# wave_get_max_micros       Absolute maximum allowed micros
# wave_get_pulses           Length in pulses of the current waveform
# wave_get_max_pulses       Absolute maximum allowed pulses
# wave_get_cbs              Length in cbs of the current waveform
# wave_get_max_cbs          Absolute maximum allowed cbs
#
# I2C
#
# i2c_open                  Opens an I2C device
# i2c_close                 Closes an I2C device
#
# i2c_write_quick           SMBus write quick
# i2c_write_byte            SMBus write byte
# i2c_read_byte             SMBus read byte
# i2c_write_byte_data       SMBus write byte data
# i2c_write_word_data       SMBus write word data
# i2c_read_byte_data        SMBus read byte data
# i2c_read_word_data        SMBus read word data
# i2c_process_call          SMBus process call
# i2c_write_block_data      SMBus write block data
# i2c_read_block_data       SMBus read block data
# i2c_block_process_call    SMBus block process call
#
# i2c_read_i2c_block_data   SMBus read I2C block data
# i2c_write_i2c_block_data  SMBus write I2C block data
#
# i2c_read_device           Reads the raw I2C device
# i2c_write_device          Writes the raw I2C device
#
# i2c_zip                   Performs multiple I2C transactions
#
# bb_i2c_open               Opens GPIO for bit banging I2C
# bb_i2c_close              Closes GPIO for bit banging I2C
# bb_i2c_zip                Performs multiple bit banged I2C transactions
#
# SPI
#
# spi_open                  Opens a SPI device
# spi_close                 Closes a SPI device
#
# spi_read                  Reads bytes from a SPI device
# spi_write                 Writes bytes to a SPI device
# spi_xfer                  Transfers bytes with a SPI device
#
# Serial
#
# serial_open               Opens a serial device (/dev/tty*)
# serial_close              Closes a serial device
#
# serial_read               Reads bytes from a serial device
# serial_read_byte          Reads a byte from a serial device
#
# serial_write              Writes bytes to a serial device
# serial_write_byte         Writes a byte to a serial device
#
# serial_data_available     Returns number of bytes ready to be read
#
# CUSTOM
#
# custom_1                  User custom function 1
# custom_2                  User custom function 2
#
# Utility
#
# get_current_tick          Get current tick (microseconds)
#
# get_hardware_revision     Get hardware revision
# get_pigpio_version        Get the pigpio version
#
# pigpio.error_text         Gets error text from error number
# pigpio.tickDiff           Returns difference between two ticks
# """
module PiGPIO

export
    # structs
    SockLock,
    Pulse,
    InMsg,
    OutMsg,
    Callback_ADT,
    CallbackThread #(threading.Thread),
    # CallbMSg, # Can't find use
    Callback,
    WaitForEdge,
    Pi
    # functions
    error_text,
    tickDiff,
    CallbackThread,
    stop,
    append,
    remove,
    run,
    Callback,
    cancel,
    tally,
    reset_tally,
    WaitForEdge,
    func,
    rxbuf,
    set_mode,
    get_mode,
    set_pull_up_down,
    read,
    write,
    set_PWM_dutycycle,
    get_PWM_dutycycle,
    set_PWM_range,
    get_PWM_range,
    get_PWM_real_range,
    set_PWM_frequency,
    get_PWM_frequency,
    set_servo_pulsewidth,
    get_servo_pulsewidth,
    notify_open,
    notify_begin,
    notify_pause,
    notify_close,
    set_watchdog,
    read_bank_1,
    read_bank_2,
    clear_bank_1,
    clear_bank_2,
    set_bank_1,
    set_bank_2,
    hardware_clock,
    hardware_PWM,
    get_current_tick,
    get_hardware_revision,
    get_pigpio_version,
    wave_clear,
    wave_add_new,
    wave_add_generic,
    wave_add_serial,
    wave_create,
    wave_delete,
    wave_tx_start,
    wave_tx_repeat,
    wave_send_once,
    wave_send_repeat,
    wave_send_using_mode,
    wave_tx_at,
    wave_tx_busy,
    wave_tx_stop,
    wave_chain,
    wave_get_micros,
    wave_get_max_micros,
    wave_get_pulses,
    wave_get_max_pulses,
    wave_get_cbs,
    wave_get_max_cbs,
    i2c_open,
    i2c_close,
    i2c_write_quick,
    i2c_write_byte,
    i2c_read_byte,
    i2c_write_byte_data,
    i2c_write_word_data,
    i2c_read_byte_data,
    i2c_read_word_data,
    i2c_process_call,
    i2c_write_block_data,
    i2c_read_block_data,
    i2c_block_process_call,
    i2c_write_i2c_block_data,
    i2c_read_i2c_block_data,
    i2c_read_device,
    i2c_write_device,
    i2c_zip,
    bb_i2c_open,
    bb_i2c_close,
    bb_i2c_zip,
    spi_open,
    spi_close,
    spi_read,
    spi_write,
    spi_xfer,
    serial_open,
    serial_close,
    serial_read_byte,
    serial_write_byte,
    serial_read,
    serial_write,
    serial_data_available,
    gpio_trigger,
    set_glitch_filter,
    set_noise_filter,
    store_script,
    run_script,
    script_status,
    stop_script,
    delete_script,
    bb_serial_read_open,
    bb_serial_read,
    bb_serial_read_close,
    bb_serial_invert,
    custom_1,
    custom_2,
    cbf,
    callback,
    wait_for_edge,
    Pi,
    stop,
    xref

using StrPack

include("constants.jl")
include("pi.jl")


end # module PiGPIO
