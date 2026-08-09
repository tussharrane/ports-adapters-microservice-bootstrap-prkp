use crate::core::models::example::Example;

pub trait ExampleRepositoryPortOut {
    fn save(&self, example: &Example) -> Result<(), String>;
    fn find_by_id(&self, id: &str) -> Result<Option<Example>, String>;
}
