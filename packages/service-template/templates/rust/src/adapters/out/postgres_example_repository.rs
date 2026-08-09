use r2d2::Pool;
use r2d2_postgres::postgres::NoTls;
use r2d2_postgres::PostgresConnectionManager;

use crate::core::models::example::Example;
use crate::ports::out::example_repository_port_out::ExampleRepositoryPortOut;

pub struct PostgresExampleRepository {
    pool: Pool<PostgresConnectionManager<NoTls>>,
}

impl PostgresExampleRepository {
    pub fn new(pool: Pool<PostgresConnectionManager<NoTls>>) -> Self {
        Self { pool }
    }
}

impl ExampleRepositoryPortOut for PostgresExampleRepository {
    fn save(&self, example: &Example) -> Result<(), String> {
        let mut conn = self.pool.get().map_err(|e| e.to_string())?;
        conn.execute(
            "INSERT INTO example (id, payload) VALUES ($1, $2) ON CONFLICT (id) DO NOTHING",
            &[&example.id, &example.payload],
        )
        .map_err(|e| e.to_string())?;
        Ok(())
    }

    fn find_by_id(&self, id: &str) -> Result<Option<Example>, String> {
        let mut conn = self.pool.get().map_err(|e| e.to_string())?;
        let row = conn
            .query_opt("SELECT id, payload FROM example WHERE id = $1", &[&id])
            .map_err(|e| e.to_string())?;
        Ok(row.map(|r| Example {
            id: r.get(0),
            payload: r.get(1),
        }))
    }
}
