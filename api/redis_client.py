import redis
from api.settings import settings
r = redis.from_url(settings.REDIS_URL, decode_responses=True)
