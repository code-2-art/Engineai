import hashlib, pickle, sqlite3, os
from pathlib import Path
from sentence_transformers import SentenceTransformer
from semantic_chunkers import StatisticalChunker

BASE_DIR = Path(__file__).parent.parent.parent
DATA_DIR = BASE_DIR / "data"
DATA_DIR.mkdir(exist_ok=True)
CACHE_DB = DATA_DIR / "embed_cache.db"

conn = sqlite3.connect(CACHE_DB, check_same_thread=False)
conn.execute("""CREATE TABLE IF NOT EXISTS embed_cache (
    hash BLOB PRIMARY KEY, vector BLOB)""")
conn.commit()

def get_cached_vector(text: str):
    h = hashlib.sha256(text.encode("utf-8")).digest()
    row = conn.execute("SELECT vector FROM embed_cache WHERE hash=?", (h,)).fetchone()
    return pickle.loads(row[0]) if row else None

def set_cached_vector(text: str, vector):
    h = hashlib.sha256(text.encode("utf-8")).digest()
    conn.execute("INSERT OR REPLACE INTO embed_cache VALUES (?, ?)",
                 (h, pickle.dumps(vector)))
    conn.commit()

# 语义分块
from semantic_chunkers.encoders import DenseEncoder
encoder = DenseEncoder("BAAI/bge-small-zh-v1.5", device="cpu")
chunker = StatisticalChunker(encoder=encoder)

def semantic_chunks(text: str):
    chunks = chunker(docs=[{"text": text}])[0]
    return [c["text"].strip() for c in chunks if len(c["text"]) > 60]

def extract_text(filepath: str) -> str:
    ext = Path(filepath).suffix.lower()
    if ext == ".pdf":
        import fitz
        doc = fitz.open(filepath)
        return "\n".join(p.get_text() for p in doc)
    elif ext in [".docx", ".doc"]:
        from docx import Document
        return "\n".join(p.text for p in Document(filepath).paragraphs)
    else:
        return Path(filepath).read_text(encoding="utf-8", errors="ignore")