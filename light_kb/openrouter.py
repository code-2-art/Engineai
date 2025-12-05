import os
import openai
import numpy as np
from django.conf import settings
from .utils import encoder

# Ensure API key is set
api_key = getattr(settings, 'OPENROUTER_API_KEY', None)
if not api_key:
    api_key = os.environ.get("OPENROUTER_API_KEY")
if not api_key:
    raise ValueError("OPENROUTER_API_KEY not found in settings or environment")

client = openai.OpenAI(
    api_key=api_key,
    base_url="https://openrouter.ai/api/v1",
)

def get_embedding(text: str) -> list[float]:
    """获取文本嵌入向量"""
    response = client.embeddings.create(
        input=text,
        model="qwen/qwen3-embedding-8b",
    )
    return response.data[0].embedding

def hyde_generate(query: str) -> str:
    """生成HyDE假设文档"""
    prompt = f"""基于以下查询，生成一个详细的假设文档，包含查询的所有关键概念、细节和相关信息。
文档应像真实的相关内容一样详细。

查询：{query}

假设文档："""
    response = client.chat.completions.create(
        model="qwen/qwen3-embedding-8b",
        messages=[{"role": "user", "content": prompt}],
        max_tokens=512,
        temperature=0.7,
    )
    return response.choices[0].message.content.strip()

def rag_answer(query: str, context: str) -> str:
    """基于上下文生成RAG回答"""
    prompt = f"""基于以下上下文准确回答问题。只使用上下文中的信息，不要编造。
如果上下文不足以回答，请诚实地说“根据提供的信息，我无法回答这个问题”。

上下文：
{context}

问题：{query}

回答："""
    response = client.chat.completions.create(
        model="qwen/qwen3-embedding-8b",
        messages=[{"role": "user", "content": prompt}],
        temperature=0.1,
        max_tokens=1024,
    )
    return response.choices[0].message.content.strip()

def rerank_documents(query: str, candidates: list[str], top_k: int = 6) -> list[str]:
    """使用嵌入相似度重排序文档"""
    if not candidates:
        return []
    q_emb = encoder.encode([query])[0]
    doc_embs = encoder.encode(candidates)
    sims = [
        np.dot(q_emb, d_emb) / (np.linalg.norm(q_emb) * np.linalg.norm(d_emb))
        for d_emb in doc_embs
    ]
    top_indices = np.argsort(sims)[-top_k:]
    return [candidates[i] for i in top_indices]