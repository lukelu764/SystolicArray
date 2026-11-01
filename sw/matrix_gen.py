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

uart_transmission(a)

uart_transmission(b)