from django.contrib import admin
from .models import LLMModel, ChatSession, Message


@admin.register(LLMModel)
class LLMModelAdmin(admin.ModelAdmin):
    list_display = ['name', 'model_name', 'provider', 'active', 'created_at']
    list_filter = ['provider', 'active']
    search_fields = ['name', 'model_name']
    list_editable = ['active']


@admin.register(ChatSession)
class ChatSessionAdmin(admin.ModelAdmin):
    list_display = ['title', 'user', 'created_at']
    list_filter = ['created_at', 'user']
    date_hierarchy = 'created_at'


@admin.register(Message)
class MessageAdmin(admin.ModelAdmin):
    list_display = ['session', 'role', 'model', 'created_at']
    list_filter = ['role', 'model', 'created_at']
    date_hierarchy = 'created_at'
    readonly_fields = ['created_at']
