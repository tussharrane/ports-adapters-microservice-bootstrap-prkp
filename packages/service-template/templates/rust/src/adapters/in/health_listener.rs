use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use crate::ports::port_in::health_check_usecase_port_in::HealthCheckUseCasePortIn;

pub struct HealthListener {
    listener: TcpListener,
    usecase: Box<dyn HealthCheckUseCasePortIn>,
    stop_flag: Arc<AtomicBool>,
}

impl HealthListener {
    pub fn new(usecase: Box<dyn HealthCheckUseCasePortIn>, stop_flag: Arc<AtomicBool>) -> Self {
        signal_hook::flag::register(signal_hook::consts::SIGTERM, stop_flag.clone())
            .expect("failed to register SIGTERM handler");
        signal_hook::flag::register(signal_hook::consts::SIGINT, stop_flag.clone())
            .expect("failed to register SIGINT handler");
        let host = std::env::var("HEALTH_HOST").unwrap_or_else(|_| "0.0.0.0".to_string());
        let port: u16 = std::env::var("HEALTH_PORT")
            .unwrap_or_else(|_| "8080".to_string())
            .parse()
            .expect("HEALTH_PORT must be a valid port number");
        let listener = TcpListener::bind((host.as_str(), port)).expect("failed to bind health port");
        listener
            .set_nonblocking(true)
            .expect("failed to set health listener nonblocking");
        Self { listener, usecase, stop_flag }
    }

    /// Liveness probe only — does not parse the request or route by path.
    pub fn start(&self) {
        while !self.stop_flag.load(Ordering::SeqCst) {
            match self.listener.accept() {
                Ok((mut stream, _)) => {
                    // The accepted connection inherits the listener's non-blocking
                    // flag — must be reset before writing, or write_all can return
                    // WouldBlock mid-response and truncate it.
                    if let Err(e) = stream.set_nonblocking(false) {
                        eprintln!("__SERVICE_NAME__: health listener set_nonblocking(false) failed: {e}");
                        continue;
                    }
                    // Drain (a bounded slice of) the client's request before responding.
                    // Dropping the stream while its request bytes are still unread makes
                    // the OS send RST instead of a clean FIN on close, and that RST can
                    // discard the response we already wrote before the client's kernel
                    // reads it out of its own receive buffer — truncating the body.
                    let _ = stream.set_read_timeout(Some(std::time::Duration::from_millis(500)));
                    let mut drain_buf = [0u8; 1024];
                    let _ = stream.read(&mut drain_buf);
                    let body = serde_json::to_string(&self.usecase.check())
                        .expect("failed to serialize health status");
                    let response = format!(
                        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                        body.len()
                    );
                    // A slow or dead client (e.g. one that connects but never reads)
                    // could otherwise block write_all forever, hanging this thread
                    // and every future health check with it.
                    let _ = stream.set_write_timeout(Some(std::time::Duration::from_secs(2)));
                    if let Err(e) = stream.write_all(response.as_bytes()) {
                        eprintln!("__SERVICE_NAME__: health listener header write failed: {e}");
                        continue;
                    }
                    if let Err(e) = stream.write_all(body.as_bytes()) {
                        eprintln!("__SERVICE_NAME__: health listener body write failed: {e}");
                    }
                }
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    std::thread::sleep(std::time::Duration::from_millis(200));
                }
                Err(e) => eprintln!("__SERVICE_NAME__: health listener accept failed: {e}"),
            }
        }
    }
}

