from minio import Minio
from api.settings import settings

client = Minio(
    settings.MINIO_ENDPOINT,
    access_key=settings.MINIO_ROOT_USER,
    secret_key=settings.MINIO_ROOT_PASSWORD,
    secure=False,
)

def ensure_bucket():
    if not client.bucket_exists(settings.MINIO_BUCKET):
        client.make_bucket(settings.MINIO_BUCKET)

def put_object(key: str, path: str):
    ensure_bucket()
    client.fput_object(settings.MINIO_BUCKET, key, path)

def get_object_url(key: str) -> str:
    return f"http://{settings.MINIO_ENDPOINT}/{settings.MINIO_BUCKET}/{key}"
