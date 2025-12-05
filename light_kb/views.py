from django.shortcuts import render

# Create your views here.
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.shortcuts import render
import json, uuid
from pathlib import Path
from .openrouter import get_embedding, hyde_generate, rag_answer, rerank_documents
from .utils import extract_text, semantic_chunks, get_cached_vector, set_cached_vector
from .chromadb_client import collection

UPLOAD_DIR = Path(__file__).parent.parent.parent / "data" / "uploads"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

@csrf_exempt
def upload_file(request):
    if request.method != "POST":
        return JsonResponse({"error": "POST only"})
    file = request.FILES["file"]
    save_path = UPLOAD_DIR / f"{uuid.uuid4()}_{file.name}"
    with open(save_path, "wb") as f:
        for c in file.chunks(): f.write(c)
    
    text = extract_text(str(save_path))
    chunks = semantic_chunks(text)
    
    embeddings, ids = [], []
    for i, c in enumerate(chunks):
        if vec := get_cached_vector(c):
            embeddings.append(vec)
        else:
            vec = get_embedding(c)
            set_cached_vector(c, vec)
            embeddings.append(vec)
        ids.append(f"{save_path.name}_{i}")
    
    collection.add(
        embeddings=embeddings,
        documents=chunks,
        ids=ids,
        metadatas=[{"source": file.name} for _ in chunks]
    )
    return JsonResponse({"status": "ok", "chunks": len(chunks)})

@csrf_exempt
def ask(request):
    if request.method != "POST":
        return JsonResponse({"error": "POST only"})
    data = json.loads(request.body)
    query = data.get("question", "").strip()
    if not query: return JsonResponse({"error": "empty question"})
    
    hyde_text = query + "\n" + hyde_generate(query)
    q_emb = get_embedding(hyde_text)
    
    results = collection.query(
        query_embeddings=[q_emb],
        n_results=15,
        include=["documents"]
    )
    
    candidates = results["documents"][0]
    top_docs = rerank_documents(query, candidates, top_k=6)
    
    answer = rag_answer(query, "\n\n".join(top_docs))
    
    return JsonResponse({"answer": answer, "sources": top_docs})

def index(request):
    return render(request, "light_kb/index.html")