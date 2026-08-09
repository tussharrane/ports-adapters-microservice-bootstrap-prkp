/// Synchronous outbound HTTP client for calling external vendor/broker APIs.
/// `reqwest`'s `blocking` feature keeps an async runtime as an internal
/// implementation detail — no tokio setup needed by callers of this type,
/// same treatment already given to the `postgres` crate in this template.
// Intentionally uncalled until a real service defines its own vendor/broker
// port and wires this in as the transport.
#[allow(dead_code)]
pub struct HttpClient {
    client: reqwest::blocking::Client,
}

#[allow(dead_code)]
impl HttpClient {
    pub fn new() -> Self {
        let client = reqwest::blocking::Client::builder()
            .timeout(std::time::Duration::from_secs(10))
            .connect_timeout(std::time::Duration::from_secs(5))
            .build()
            .expect("failed to build HTTP client");
        Self { client }
    }

    pub fn get_json(&self, url: &str) -> Result<serde_json::Value, String> {
        self.client
            .get(url)
            .send()
            .map_err(|e| e.to_string())?
            .json::<serde_json::Value>()
            .map_err(|e| e.to_string())
    }
}

impl Default for HttpClient {
    fn default() -> Self {
        Self::new()
    }
}
