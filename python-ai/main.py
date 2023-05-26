# Paths
from pathlib import Path

# Camera
from picamera2 import Picamera2
from picamera2.encoders import JpegEncoder
from picamera2.outputs import FileOutput
import io

# Time
import datetime

# JSON
import json

# GPS Daemon
from gps3 import gps3
import threading

latitude = "n/a"
longitude = "n/a"
altitude = "n/a"

# Sockets
import socketserver
from http import server
from threading import Condition

# TFLite
from PIL import Image                                   # resize images
from pycoral.adapters import common, classify           # used by Coral Edge TPU
from pycoral.utils.edgetpu import make_interpreter
from pycoral.utils.dataset import read_label_file
from tflite_runtime import interpreter


script_dir = Path(__file__).parent.resolve()
model_file = script_dir/'plants.tflite'
label_file = script_dir/'probability-labels-en.txt'

interpreter = make_interpreter(f"{model_file}")
interpreter.allocate_tensors()

size = common.input_size(interpreter)


class StreamingOutput(io.BufferedIOBase):
    def __init__(self):
        self.frame = None
        self.condition = Condition()

    def write(self, buf):
        with self.condition:
            self.frame = buf
            self.condition.notify_all()

picam2 = Picamera2()
output = StreamingOutput()
picam2.configure(picam2.create_preview_configuration(main={"format": 'XRGB8888', "size": (1920, 1080)}))
picam2.start_recording(JpegEncoder(), FileOutput(output))


PAGE = """\
<html>
<head>
<title>RV-AI MJPEG streaming</title>
</head>
<style>
* { margin: 0; } /* just some reset */
.header { height: 100vh; width: 100vw; overflow: hidden; }
img { width: 100%; height: 100%; object-fit: cover; }
</style>
<body>
<div class="header">
  <img src="stream.mjpg" width="1920" height="1080" />
</div>

</body>
</html>
"""

def analyseAndSave():
    im = picam2.capture_array()
    img = Image.fromarray(im).convert('RGB').resize(size, Image.LANCZOS) 

    common.set_input(interpreter, img)
    interpreter.invoke()
    classes = classify.get_classes(interpreter, top_k=1)

    labels = read_label_file(label_file)
    
    with open("/home/pi/rv-py-ai/airecords.csv", 'a') as file:
        file.write(f'{datetime.datetime.now()}, {labels.get(classes[0].id, classes[0].id)}, {classes[0].score:.5f}\n')
    
    return f'{{"label": "{labels.get(classes[0].id, classes[0].id)}", "score": {classes[0].score:.5f}}}'

def gpsThread():
    global altitude
    global latitude
    global longitude

    gps_socket = gps3.GPSDSocket()
    data_stream = gps3.DataStream()
    gps_socket.connect()
    gps_socket.watch()

    for new_data in gps_socket:
        if new_data:
            data_stream.unpack(new_data)
            if data_stream.TPV['alt'] != altitude or data_stream.TPV['lat'] != latitude or data_stream.TPV['lon'] != longitude:
                altitude = data_stream.TPV['alt']
                latitude = data_stream.TPV['lat']
                longitude = data_stream.TPV['lon']
                with open("/home/pi/rv-py-ai/gpsrecords.csv", 'a') as file:
                    file.write(f'{datetime.datetime.now()}, {altitude}, {latitude}, {longitude}\n')
    
    print("GPS Thread Finished")


class StreamingHandler(server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.send_header('Age', 0)
            self.send_header('Cache-Control', 'no-cache, private')
            self.send_header('Pragma', 'no-cache')
            self.send_header('Content-Type', 'multipart/x-mixed-replace; boundary=FRAME')
            self.end_headers()
            try:
                while True:
                    with output.condition:
                        output.condition.wait()
                        frame = output.frame
                    self.wfile.write(b'--FRAME\r\n')
                    self.send_header('Content-Type', 'image/jpeg')
                    self.send_header('Content-Length', len(frame))
                    self.end_headers()
                    self.wfile.write(frame)
                    self.wfile.write(b'\r\n')
            except Exception as e:
                pass
        elif self.path == '/ai':
            result = bytes(analyseAndSave(), 'ascii')
            print(result)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(result)
            self.wfile.write(b'\r\n')
        elif self.path == '/gps':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(bytes(json.dumps({'altitude': f'{altitude}', 'latitude': f'{latitude}', 'longitude': f'{longitude}'}), 'ascii'))
            self.wfile.write(b'\r\n')
        else:
            self.send_error(404)
            self.end_headers()


class StreamingServer(socketserver.ThreadingMixIn, server.HTTPServer):
    allow_reuse_address = True
    daemon_threads = True


threading.Thread(target=gpsThread).start()


try:
    address = ('0.0.0.0', 2222)
    server = StreamingServer(address, StreamingHandler)
    server.serve_forever()
finally:
    picam2.stop_recording()