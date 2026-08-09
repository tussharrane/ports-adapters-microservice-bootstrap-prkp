mod adapters;
mod core;
// generated/ deliberately lives at the template root (sibling of src/), matching
// packages/contracts/buf.gen.yaml's `out:` path — do not move it into src/.
#[path = "../generated/mod.rs"]
mod generated;
mod ports;

use std::sync::atomic::AtomicBool;
use std::sync::Arc;

use r2d2_postgres::postgres::NoTls;
use r2d2_postgres::PostgresConnectionManager;

use crate::adapters::adapter_in::health_listener::HealthListener;
use crate::adapters::adapter_in::kafka_consumer::KafkaConsumer;
use crate::adapters::out::kafka_producer::KafkaProducer;
use crate::adapters::out::postgres_example_repository::PostgresExampleRepository;
use crate::core::services::health_check_service::HealthCheckService;
use crate::core::services::process_example_service::ProcessExampleService;

fn main() {
    let database_url = std::env::var("DATABASE_URL").expect("DATABASE_URL must be set");
    let manager = PostgresConnectionManager::new(
        database_url.parse().expect("invalid DATABASE_URL"),
        NoTls,
    );
    let pool = r2d2::Pool::builder()
        .max_size(5)
        .build(manager)
        .expect("failed to build Postgres pool");

    let adapter_out_kafka_producer = Box::new(KafkaProducer::new());
    let adapter_out_postgres_repository = Box::new(PostgresExampleRepository::new(pool));
    let example_service = Box::new(ProcessExampleService::new(
        adapter_out_kafka_producer,
        adapter_out_postgres_repository,
    ));
    let adapter_in_kafka_consumer = KafkaConsumer::new(example_service);

    let stop_flag = Arc::new(AtomicBool::new(false));

    let health_check_service = Box::new(HealthCheckService::new());
    let adapter_in_health_listener = HealthListener::new(health_check_service, stop_flag.clone());
    std::thread::spawn(move || adapter_in_health_listener.start());

    if let Err(e) = adapter_in_kafka_consumer.start(stop_flag) {
        eprintln!("__SERVICE_NAME__: {e}");
        std::process::exit(1);
    }
}
