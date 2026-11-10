import numpy as np
import serial

ser = serial.Serial(port="COM3", baudrate=115200, timeout=1) #confirm baudrate with shahzaib
#ser = serial.serial_for_url("loop://", baudrate=115200, timeout=1)

#setting n * k and k * m matricies hard coded for now
n = 3
k = 3
m = 3

#integers 31 to 0 cuz shahzaibs
rng = np.random.default_rng()

a = rng.integers(low=0, high=31, size=(n, k))
b = rng.integers(low=0, high=31, size=(k, m))

def uart_transmission(input_array): #sends array over uart
    rows, cols = input_array.shape

    # rng.integers returns int64 by default; values 0-30 fit in one byte
    payload = np.ascontiguousarray(input_array, dtype=np.uint8).tobytes()  # row-major

    header = bytes([rows, cols])

    ser.write(header + payload) #this will send over the row and column size before the array data then with that info we can reconstruct on fpga side
    ser.flush()  # block until everything is out of the OS buffer

def comparison(a,b,fpga_output): #check if the output did it right
    real_answer = a @ b
    return np.array_equal(real_answer, fpga_output)

def uart_receiver():
    # UART payload format:
    #   byte 0: row count
    #   byte 1: column count
    #   then top to bottom left to right
    # Wait indefinitely until the FPGA sends a packet.
    while True:
        header = ser.read(2)
        if len(header) == 2:
            rows, cols = header
            break

    payload_size = rows * cols
    payload = bytearray()

    while len(payload) < payload_size: #waits forever
        chunk = ser.read(payload_size - len(payload))
        if chunk:
            payload.extend(chunk)

    return np.frombuffer(payload, dtype=np.uint8).reshape((rows, cols)) #cool reshape function to turn 1D array to 2D


uart_transmission(a)
uart_transmission(b)

out = uart_receiver()

print(f"Comparison status {comparison(a,b,out)}. Output array is {out}")