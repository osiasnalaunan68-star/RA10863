import os
from pathlib import Path

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass


class Settings:
    BASE_DIR: Path = Path(__file__).resolve().parent.parent.parent
    DATABASE_PATH: str = os.getenv("DATABASE_PATH", str(BASE_DIR / "customs_law.db"))
    EDIT_ACCESS_KEY: str = os.getenv("EDIT_ACCESS_KEY", "").strip()
    CORS_ORIGINS: str = os.getenv("CORS_ORIGINS", "*")


settings = Settings()
