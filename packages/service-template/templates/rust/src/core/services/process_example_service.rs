use crate::core::models::example::Example;
use crate::ports::out::example_publisher_port_out::ExamplePublisherPortOut;
use crate::ports::out::example_repository_port_out::ExampleRepositoryPortOut;
use crate::ports::port_in::process_example_usecase_port_in::ProcessExampleUseCasePortIn;

pub struct ProcessExampleService {
    publisher: Box<dyn ExamplePublisherPortOut>,
    repository: Box<dyn ExampleRepositoryPortOut>,
}

impl ProcessExampleService {
    pub fn new(
        publisher: Box<dyn ExamplePublisherPortOut>,
        repository: Box<dyn ExampleRepositoryPortOut>,
    ) -> Self {
        Self { publisher, repository }
    }
}

impl ProcessExampleUseCasePortIn for ProcessExampleService {
    fn process(&self, example: Example) -> Result<(), String> {
        self.repository.save(&example)?;
        self.publisher.publish(&example)
    }
}
