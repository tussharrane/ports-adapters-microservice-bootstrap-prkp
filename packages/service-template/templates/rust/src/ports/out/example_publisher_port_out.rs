use crate::core::models::example::Example;

pub trait ExamplePublisherPortOut {
    fn publish(&self, example: &Example) -> Result<(), String>;
}
