import json
import os
import signal
import socket
import sys
import threading
from dataclasses import asdict

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "ports", "in")))

from health_check_usecase_port_in import HealthCheckUseCasePortIn


class HealthListener:
    """Liveness probe only — does not parse the request or route by path."""

    def __init__(self, usecase: HealthCheckUseCasePortIn, stop_event: threading.Event) -> None:
        self._usecase = usecase
        self._stop_event = stop_event
        signal.signal(signal.SIGTERM, self._handle_signal)
        signal.signal(signal.SIGINT, self._handle_signal)
        host = os.environ.get("HEALTH_HOST", "0.0.0.0")
        port = int(os.environ.get("HEALTH_PORT", "8080"))
        self._server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._server.bind((host, port))
        self._server.listen(5)
        self._server.settimeout(1.0)

    def _handle_signal(self, signum: int, frame: object) -> None:
        self._stop_event.set()

    def start(self) -> None:
        try:
            while not self._stop_event.is_set():
                try:
                    conn, _ = self._server.accept()
                except OSError:
                    continue
                with conn:
                    conn.settimeout(2.0)
                    try:
                        conn.recv(1024)
                        body = json.dumps(asdict(self._usecase.check())).encode()
                        response = (
                            b"HTTP/1.1 200 OK\r\n"
                            b"Content-Type: application/json\r\n"
                            b"Content-Length: " + str(len(body)).encode() + b"\r\n"
                            b"Connection: close\r\n\r\n" + body
                        )
                        conn.sendall(response)
                    except OSError:
                        pass
        finally:
            self._server.close()
