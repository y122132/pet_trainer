from sqladmin import ModelView
from app.db.models.user import User
from app.db.models.character import Character, Stat, ActionLog
from app.db.models.diary import Diary, DiaryLike
from app.db.models.notice import Notice

class UserAdmin(ModelView, model=User):
    column_list = [User.id, User.username, User.nickname, User.is_active, User.created_at]
    column_searchable_list = [User.username, User.nickname]
    icon = "fa-solid fa-user"

class CharacterAdmin(ModelView, model=Character):
    column_list = [Character.id, Character.user_id, Character.name, Character.pet_type, Character.status]
    column_searchable_list = [Character.name]
    icon = "fa-solid fa-paw"

class StatAdmin(ModelView, model=Stat):
    column_list = [Stat.id, Stat.character_id, Stat.level, Stat.happiness, Stat.health]
    icon = "fa-solid fa-chart-bar"

class ActionLogAdmin(ModelView, model=ActionLog):
    column_list = [ActionLog.id, ActionLog.character_id, ActionLog.action_type, ActionLog.created_at]
    column_sortable_list = [ActionLog.created_at]
    icon = "fa-solid fa-history"

class DiaryAdmin(ModelView, model=Diary):
    column_list = [Diary.id, Diary.user_id, Diary.content, Diary.tag, Diary.created_at]
    column_sortable_list = [Diary.created_at]
    icon = "fa-solid fa-book"

class DiaryLikeAdmin(ModelView, model=DiaryLike):
    column_list = [DiaryLike.id, DiaryLike.diary_id, DiaryLike.user_id]
    icon = "fa-solid fa-heart"

class NoticeAdmin(ModelView, model=Notice):
    column_list = [Notice.id, Notice.title, Notice.is_active, Notice.created_at]
    column_searchable_list = [Notice.title, Notice.content]
    column_sortable_list = [Notice.created_at]
    icon = "fa-solid fa-bullhorn"
