from django.urls import path
from . import views

app_name = 'x_scheduler'

urlpatterns = [
    path('', views.schedule_list, name='schedule_list'),
    path('create/', views.schedule_create, name='schedule_create'),
    path('edit/<uuid:pk>/', views.schedule_edit, name='schedule_edit'),
    path('delete/<uuid:pk>/', views.schedule_delete, name='schedule_delete'),
    path('x_auth/callback/', views.x_auth_callback, name='x_auth_callback'),
] 