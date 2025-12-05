import chromadb
from chromadb.config import Settings
from pathlib import Path

BASE_DIR = Path(__file__).parent.parent.parent
client = chromadb.PersistentClient(
    path=str(BASE_DIR / "data" / "chroma"),
    settings=Settings(anonymized_telemetry=False)
)
collection = client.get_or_create_collection(
    name="light_kb_docs",
    metadata={"hnsw:space": "cosine"}
)