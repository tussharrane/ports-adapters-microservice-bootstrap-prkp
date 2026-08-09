use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use prost::Message;
use rdkafka::config::ClientConfig;
use rdkafka::consumer::{BaseConsumer, Consumer};
use rdkafka::message::Message as KafkaMessage;

use crate::core::models::example::Example;
use crate::generated::Example as GeneratedExample;
use crate::ports::port_in::process_example_usecase_port_in::ProcessExampleUseCasePortIn;

pub struct KafkaConsumer {
    consumer: BaseConsumer,
    usecase: Box<dyn ProcessExampleUseCasePortIn>,
}

impl KafkaConsumer {
    pub fn new(usecase: Box<dyn ProcessExampleUseCasePortIn>) -> Self {
        let brokers = std::env::var("KAFKA_BROKERS").unwrap_or_else(|_| "localhost:9092".to_string());
        let topic = std::env::var("KAFKA_CONSUME_TOPIC")
            .unwrap_or_else(|_| "example.v1.in".to_string());
        let group_id = std::env::var("KAFKA_GROUP_ID").unwrap_or_else(|_| "__service_name__".to_string());

        let consumer: BaseConsumer = ClientConfig::new()
            .set("bootstrap.servers", &brokers)
            .set("group.id", &group_id)
            .set("auto.offset.reset", "earliest")
            .create()
            .expect("failed to create Kafka consumer");
        consumer
            .subscribe(&[topic.as_str()])
            .expect("failed to subscribe to Kafka topic");

        Self { consumer, usecase }
    }

    pub fn start(&self, stop_flag: Arc<AtomicBool>) -> Result<(), String> {
        while !stop_flag.load(Ordering::SeqCst) {
            if let Some(result) = self.consumer.poll(Duration::from_secs(1)) {
                match result {
                    Ok(msg) => {
                        if let Some(payload) = msg.payload() {
                            let generated =
                                GeneratedExample::decode(payload).map_err(|e| e.to_string())?;
                            let example = Example {
                                id: generated.id,
                                payload: generated.payload,
                            };
                            self.usecase.process(example)?;
                        }
                    }
                    Err(e) => eprintln!("__SERVICE_NAME__: consume error: {e}"),
                }
            }
        }
        eprintln!("__SERVICE_NAME__: consumer loop exited cleanly");
        Ok(())
    }
}
