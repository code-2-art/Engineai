from django.shortcuts import render, get_object_or_404, redirect
from django.http import JsonResponse
from django.contrib.auth.decorators import login_required
from django.views.decorators.http import require_POST
from django.contrib import messages
from .models import ChatSession, Message, LLMModel
from .services import get_llm_response


@login_required
def chat_home(request):
    """
    AI聊天首页，列出会话列表和可用模型
    """
    models = LLMModel.objects.filter(active=True)
    sessions = ChatSession.objects.filter(user=request.user).order_by('-created_at')[:10]
    return render(request, 'aichat/chat_home.html', {
        'models': models,
        'sessions': sessions
    })


@login_required
@require_POST
def chat_api(request):
    """
    API接口，发送消息获取LLM响应
    """
    session_id = int(request.POST['session_id'])
    message = request.POST['message']
    model_id = int(request.POST['model_id'])

    session = get_object_or_404(ChatSession, id=session_id, user=request.user)
    Message.objects.create(session=session, role='user', content=message)

    history = [
        {"role": msg.role, "content": msg.content}
        for msg in session.messages.all().order_by('created_at')
    ]

    try:
        response = get_llm_response(history, model_id)
        Message.objects.create(
            session=session,
            role='assistant',
            content=response,
            model_id=model_id
        )
        return JsonResponse({'response': response})
    except Exception as e:
        return JsonResponse({'error': str(e)}, status=500)


@login_required
def create_session(request):
    """
    创建新聊天会话
    """
    session = ChatSession.objects.create(user=request.user)
    messages.success(request, '新会话已创建')
    return redirect('aichat:session_detail', session_id=session.id)


@login_required
def session_detail(request, session_id):
    """
    聊天会话详情页
    """
    session = get_object_or_404(ChatSession, id=session_id, user=request.user)
    models = LLMModel.objects.filter(active=True)
    return render(request, 'aichat/chat_detail.html', {
        'session': session,
        'models': models
    })
