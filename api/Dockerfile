FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git curl ca-certificates docker.io exiftool tesseract-ocr \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
