from django.urls import path
from . import views

app_name = 'aichat'

urlpatterns = [
    path('', views.chat_home, name='chat_home'),
    path('api/chat/', views.chat_api, name='chat_api'),
    path('new/', views.create_session, name='create_session'),
    path('session/<int:session_id>/', views.session_detail, name='session_detail'),
]