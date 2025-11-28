from django_ai_assistant import AIAssistant

class AIChatAssistant(AIAssistant):
    id = "aichat_assistant"
    name = "AI Chat Assistant"
    instructions = """
You are a helpful AI assistant embedded in a Django application.
Respond to user queries in a friendly and informative manner.
"""
    model = "gpt-4o-mini"
    """
    AI Chat Assistant for the aichatapp.
    """
    name = "aichat_assistant"
    instructions = """
    You are a helpful AI assistant embedded in a Django application.
    Respond to user queries in a friendly and informative manner.
    """
    model = "gpt-4o-mini"