from django.urls import path
from . import views

app_name = "light_kb"

urlpatterns = [
    path('', views.index, name="index"),
    path('upload', views.upload_file, name="upload"),
    path('ask', views.ask, name="ask"),
]