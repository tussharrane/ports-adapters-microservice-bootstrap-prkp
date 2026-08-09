FROM python:3.13-slim

WORKDIR /app

COPY pyproject.toml ./
RUN python3 -c "\
import tomllib; \
data = tomllib.load(open('pyproject.toml', 'rb')); \
print('\n'.join(data['project']['dependencies']))" > /tmp/requirements.txt \
    && pip install --no-cache-dir -r /tmp/requirements.txt \
    && useradd --create-home --shell /bin/bash appuser

COPY generated ./generated
COPY src ./src
COPY main.py ./main.py

USER appuser

CMD ["python3", "main.py"]
