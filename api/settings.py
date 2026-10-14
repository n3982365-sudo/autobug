from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    POSTGRES_USER: str = "autobug"
    POSTGRES_PASSWORD: str = "autobug"
    POSTGRES_DB: str = "autobug"
    POSTGRES_HOST: str = "postgres"
    POSTGRES_PORT: int = 5432
    REDIS_URL: str = "redis://redis:6379/0"
    MINIO_ROOT_USER: str = "autobug"
    MINIO_ROOT_PASSWORD: str = "autobug"
    MINIO_ENDPOINT: str = "minio:9000"
    MINIO_BUCKET: str = "autobug"
    SECRET_KEY: str = "change_me"
    DATA_DIR: str = "/app/data"
    TELEGRAM_BOT_TOKEN: str = ""
    TELEGRAM_ALLOWED_CHATS: str = ""
    HIBP_KEY: str = ""
    DEHASHED_KEY: str = ""
    HUNTER_KEY: str = ""
    SHODAN_KEY: str = ""
    CENSYS_ID: str = ""
    CENSYS_SECRET: str = ""
    SECURITYTRAILS_KEY: str = ""
    INTELX_KEY: str = ""

    class Config:
        env_file = ".env"

    @property
    def chats(self) -> list[int]:
        v = self.TELEGRAM_ALLOWED_CHATS
        if not v:
            return []
        return [int(x) for x in str(v).split(",") if x.strip()]

settings = Settings()
