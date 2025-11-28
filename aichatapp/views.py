from django.http import JsonResponse
from django.shortcuts import render
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods
from .ai_assistants import AIChatAssistant

assistant = AIChatAssistant()

def index(request):
    """Render the AI chat interface."""
    return render(request, 'aichatapp/index.html', {'is_chat': True})

@csrf_exempt
@require_http_methods(["POST"])
def aichat(request):
    """Handle AI chat requests."""
    user_message = request.POST.get('message', '').strip()
    if not user_message:
        return JsonResponse({'error': 'No message provided'}, status=400)
    
    try:
        response = assistant.chat(user_message)
        return JsonResponse({'response': response})
    except Exception as e:
        return JsonResponse({'error': str(e)}, status=500)
