use crate::core::models::example::Example;

pub trait ProcessExampleUseCasePortIn {
    fn process(&self, example: Example) -> Result<(), String>;
}
