import os
import sys
from typing import Any

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

from psycopg_pool import ConnectionPool

from core.models.example import Example
from ports.out.example_repository_port_out import ExampleRepositoryPortOut


class PostgresExampleRepository(ExampleRepositoryPortOut):
    def __init__(self, pool: ConnectionPool[Any]) -> None:
        self._pool = pool

    def save(self, example: Example) -> None:
        with self._pool.connection() as conn:
            conn.execute(
                "INSERT INTO example (id, payload) VALUES (%s, %s) ON CONFLICT (id) DO NOTHING",
                (example.id, example.payload),
            )
            conn.commit()

    def find_by_id(self, id: str) -> Example | None:
        with self._pool.connection() as conn:
            row = conn.execute(
                "SELECT id, payload FROM example WHERE id = %s", (id,)
            ).fetchone()
        if row is None:
            return None
        return Example(id=row[0], payload=row[1])
