from django.db import models
from django.contrib.auth.models import User

class LLMModel(models.Model):
    name = models.CharField(max_length=100, verbose_name="显示名称")
    model_name = models.CharField(max_length=200, verbose_name="模型ID")
    api_key = models.CharField(max_length=500, blank=True, verbose_name="API密钥")
    provider = models.CharField(max_length=50, default="openrouter", verbose_name="提供商")
    active = models.BooleanField(default=True, verbose_name="启用")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "LLM模型"
        verbose_name_plural = "LLM模型"

    def __str__(self):
        return self.name


class ChatSession(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, verbose_name="用户")
    title = models.CharField(max_length=200, blank=True, verbose_name="会话标题")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "聊天会话"
        verbose_name_plural = "聊天会话"
        ordering = ['-created_at']

    def __str__(self):
        return self.title or f"Chat {self.id}"


class Message(models.Model):
    ROLE_CHOICES = [
        ('user', '用户'),
        ('assistant', '助手'),
    ]
    session = models.ForeignKey(ChatSession, on_delete=models.CASCADE, related_name="messages")
    role = models.CharField(max_length=10, choices=ROLE_CHOICES)
    content = models.TextField()
    model = models.ForeignKey(LLMModel, on_delete=models.SET_NULL, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "消息"
        verbose_name_plural = "消息"
        ordering = ['created_at']

    def __str__(self):
        return f"{self.role}: {self.content[:50]}"
