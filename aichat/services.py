import litellm
from .models import LLMModel


def get_llm_response(messages, model_id):
    """
    使用LiteLLM调用指定模型生成响应
    """
    model_obj = LLMModel.objects.get(id=model_id)
    kwargs = {
        "model": model_obj.model_name,
        "messages": messages,
        "temperature": 0.7,
    }
    if model_obj.api_key:
        kwargs["api_key"] = model_obj.api_key
    if model_obj.provider == "openrouter":
        kwargs["model"] = f"openrouter/{model_obj.model_name}"
        kwargs["api_base"] = "https://openrouter.ai/api/v1"
        kwargs["extra_headers"] = {
            "HTTP-Referer": "https://engineai.local",
            "X-Title": "EngineAI Chat",
        }
    response = litellm.completion(**kwargs)
    return response.choices[0].message.content