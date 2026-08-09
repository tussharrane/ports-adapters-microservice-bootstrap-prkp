use std::time::Duration;

use prost::Message;
use rdkafka::client::ClientContext;
use rdkafka::config::ClientConfig;
use rdkafka::message::DeliveryResult;
use rdkafka::producer::{BaseProducer, BaseRecord, Producer, ProducerContext};

use crate::core::models::example::Example;
use crate::generated::Example as GeneratedExample;
use crate::ports::out::example_publisher_port_out::ExamplePublisherPortOut;

struct DeliveryLogger;

impl ClientContext for DeliveryLogger {}

impl ProducerContext for DeliveryLogger {
    type DeliveryOpaque = ();

    fn delivery(&self, result: &DeliveryResult<'_>, _delivery_opaque: Self::DeliveryOpaque) {
        if let Err((e, _msg)) = result {
            eprintln!("__SERVICE_NAME__: Kafka delivery failed: {e}");
        }
    }
}

pub struct KafkaProducer {
    producer: BaseProducer<DeliveryLogger>,
    topic: String,
}

impl KafkaProducer {
    pub fn new() -> Self {
        let brokers = std::env::var("KAFKA_BROKERS").unwrap_or_else(|_| "localhost:9092".to_string());
        let topic = std::env::var("KAFKA_PRODUCE_TOPIC")
            .unwrap_or_else(|_| "example.v1.out".to_string());
        let producer: BaseProducer<DeliveryLogger> = ClientConfig::new()
            .set("bootstrap.servers", &brokers)
            .create_with_context(DeliveryLogger)
            .expect("failed to create Kafka producer");
        Self { producer, topic }
    }
}

impl ExamplePublisherPortOut for KafkaProducer {
    fn publish(&self, example: &Example) -> Result<(), String> {
        let generated = GeneratedExample {
            id: example.id.clone(),
            payload: example.payload.clone(),
        };
        let mut buf = Vec::new();
        generated.encode(&mut buf).map_err(|e| e.to_string())?;

        self.producer
            .send(BaseRecord::to(&self.topic).payload(&buf).key(example.id.as_str()))
            .map_err(|(e, _)| e.to_string())?;
        self.producer
            .flush(Duration::from_secs(5))
            .map_err(|e| e.to_string())?;

        println!(
            "[__SERVICE_NAME__] published {} bytes to {}",
            buf.len(),
            self.topic
        );
        Ok(())
    }
}
