from django.urls import path
from . import views

app_name = 'aichatapp'

urlpatterns = [
    path('', views.index, name='index'),
    path('chat/', views.aichat, name='aichat'),
]